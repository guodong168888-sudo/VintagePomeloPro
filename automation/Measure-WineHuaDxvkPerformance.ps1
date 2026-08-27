[CmdletBinding()]
param(
    [ValidateRange(1, 6)]
    [int]$Rounds = 2,
    [ValidateRange(10, 180)]
    [int]$WarmupSeconds = 25,
    [ValidateRange(20, 600)]
    [int]$SampleSeconds = 60,
    [ValidateRange(0, 180)]
    [int]$CooldownSeconds = 15,
    [switch]$IncludeModernBatchMappedFlushOff,
    [switch]$CollectModernMappedFlushStats,
    [string]$DeviceId = '',
    [string]$HdcPath = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$bundle = 'com.vintage.pomelopro'
$startScript = Join-Path $PSScriptRoot 'Start-WineHuaGameTest.ps1'
$observationExperiment = 'observe-frame-timeline'
if (-not $OutputRoot) {
    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $OutputRoot = Join-Path $repositoryRoot 'output\dxvk-performance'
}

if (-not (Test-Path -LiteralPath $HdcPath)) {
    throw "Windows HDC not found: $HdcPath"
}
if (-not (Test-Path -LiteralPath $startScript)) {
    throw "WineHua launcher not found: $startScript"
}
if (-not $DeviceId) {
    $targets = @(& $HdcPath list targets |
        Where-Object { $_ -and $_ -notmatch '^\[Empty\]' } |
        ForEach-Object { ($_ -split '\s+')[0] })
    if ($targets.Count -ne 1) {
        throw "Expected one connected Windows HDC target, found $($targets.Count)"
    }
    $DeviceId = $targets[0]
}

$sessionId = 'dxvk-ab-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$sessionRoot = Join-Path $OutputRoot $sessionId
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
Add-Type -AssemblyName System.Drawing

function Invoke-Hdc {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & $HdcPath -t $DeviceId @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($result -join "`n")"
    }
    return $result
}

function Convert-KeyValueLogLine {
    param([Parameter(Mandatory)][string]$Line)
    $values = [ordered]@{}
    foreach ($match in [regex]::Matches(
        $Line, '(?<key>[A-Za-z][A-Za-z0-9_]*)=(?<value>[^\s]+)')) {
        $key = $match.Groups['key'].Value
        $rawValue = $match.Groups['value'].Value
        [long]$integerValue = 0
        [double]$floatingValue = 0
        if ([long]::TryParse($rawValue, [ref]$integerValue)) {
            $values[$key] = $integerValue
        } elseif ([double]::TryParse(
            $rawValue, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$floatingValue)) {
            $values[$key] = $floatingValue
        } else {
            $values[$key] = $rawValue
        }
    }
    return [pscustomobject]$values
}

function Get-NearestRankPercentile {
    param(
        [Parameter(Mandatory)][double[]]$Values,
        [Parameter(Mandatory)][ValidateRange(0.0, 1.0)][double]$Percentile
    )
    if ($Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Max(0, [Math]::Ceiling($Percentile * $sorted.Count) - 1)
    return [Math]::Round([double]$sorted[$index], 3)
}

function Get-TimelineStatistics {
    param([Parameter(Mandatory)][object[]]$Samples)
    $result = [ordered]@{ sampleCount = $Samples.Count }
    foreach ($name in @(
        'present_cpu_us', 'release_wait_us', 'wait_fence_us', 'acquire_us',
        'submit_us', 'queue_present_us', 'release_signal_us', 'flush_us',
        'gpu_present_copy_us')) {
        [double[]]$values = @($Samples | ForEach-Object {
            $property = $_.PSObject.Properties[$name]
            if ($property -and $null -ne $property.Value) {
                [double]$property.Value
            }
        })
        if ($values.Count -eq 0) { continue }
        $result[$name] = [ordered]@{
            p50 = Get-NearestRankPercentile -Values $values -Percentile 0.50
            p95 = Get-NearestRankPercentile -Values $values -Percentile 0.95
            p99 = Get-NearestRankPercentile -Values $values -Percentile 0.99
            max = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 3)
        }
    }
    return [pscustomobject]$result
}

function Test-PresentActionContract {
    param([AllowNull()][object]$Present)
    if (-not $Present) { return $null }
    $transport = $Present.PSObject.Properties['transport']
    $postWait = $Present.PSObject.Properties['post_present_cpu_wait']
    if (-not $transport -or -not $postWait) { return $null }
    switch ([string]$transport.Value) {
        'direct-native-buffer' { return [long]$postWait.Value -eq 0 }
        'wsi' { return [long]$postWait.Value -eq 1 }
        default { return $false }
    }
}

function Get-ImageSignal {
    param([Parameter(Mandatory)][string]$Path)
    $bitmap = [System.Drawing.Bitmap]::new($Path)
    try {
        [double]$sum = 0
        [double]$sumSquares = 0
        [long]$count = 0
        for ($y = 0; $y -lt $bitmap.Height; $y += 8) {
            for ($x = 0; $x -lt $bitmap.Width; $x += 8) {
                $pixel = $bitmap.GetPixel($x, $y)
                $luma = 0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B
                $sum += $luma
                $sumSquares += $luma * $luma
                ++$count
            }
        }
        $mean = if ($count) { $sum / $count } else { 0.0 }
        $variance = if ($count) {
            [Math]::Max(0.0, ($sumSquares / $count) - ($mean * $mean))
        } else { 0.0 }
        return [pscustomobject]@{
            sampledPixels = $count
            meanLuma = [Math]::Round($mean, 3)
            lumaStandardDeviation = [Math]::Round([Math]::Sqrt($variance), 3)
            blankLike = $mean -lt 3.0 -or [Math]::Sqrt($variance) -lt 1.0
        }
    } finally {
        $bitmap.Dispose()
    }
}

function Save-Snapshot {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunDirectory
    )
    $remote = "/data/local/tmp/$RunId.jpeg"
    $local = Join-Path $RunDirectory 'final.jpeg'
    Invoke-Hdc -Arguments @('shell', 'snapshot_display', '-f', $remote) | Out-Null
    Invoke-Hdc -Arguments @('file', 'recv', $remote, $local) | Out-Null
    Invoke-Hdc -Arguments @('shell', 'rm', '-f', $remote) | Out-Null
    return $local
}

function Invoke-Measurement {
    param(
        [Parameter(Mandatory)][pscustomobject]$Condition,
        [Parameter(Mandatory)][int]$Round,
        [Parameter(Mandatory)][int]$Order
    )
    $runId = 'r{0:d2}-o{1:d2}-{2}' -f $Round, $Order, $Condition.id
    $runDirectory = Join-Path $sessionRoot $runId
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $startedAt = [DateTimeOffset]::Now
    $result = [ordered]@{
        schemaVersion = 3
        runId = $runId
        condition = $Condition.id
        d3dBackend = $Condition.backend
        batchMappedFlushMode = $Condition.batchMappedFlushMode
        collectModernMappedFlushStats = [bool]$CollectModernMappedFlushStats
        round = $Round
        order = $Order
        observationExperiment = $observationExperiment
        warmupSeconds = $WarmupSeconds
        sampleSeconds = $SampleSeconds
        startedAt = $startedAt.ToString('o')
        status = 'INFRA_ERROR'
    }

    try {
        Invoke-Hdc -Arguments @('shell', 'hilog', '-r') | Out-Null
        $d3dEnvironment = @{
            DXVK_LOG_LEVEL = 'info'
        }
        if ($CollectModernMappedFlushStats -and
            $Condition.backend -eq 'dxvk_modern_2_6' -and
            $Condition.batchMappedFlushMode -ne 'off') {
            $d3dEnvironment['DXVK_WINEHUA_BATCH_MAPPED_FLUSH_STATS'] = '1'
        }
        $launchParameters = @{
            D3DBackend = $Condition.backend
            GraphicsExperiment = $observationExperiment
            GamePreset = 'heaven-dx11'
            DeviceId = $DeviceId
            HdcPath = $HdcPath
            D3DEnvironment = $d3dEnvironment
            BatchMappedFlushMode = $Condition.batchMappedFlushMode
        }
        & $startScript @launchParameters |
            Set-Content -LiteralPath (Join-Path $runDirectory 'launch.txt') -Encoding UTF8
        if ($LASTEXITCODE -ne 0) {
            throw 'WineHua Heaven launcher failed'
        }

        Start-Sleep -Seconds $WarmupSeconds
        $measurementStartedAt = [DateTimeOffset]::Now
        Start-Sleep -Seconds $SampleSeconds
        $measurementEndedAt = [DateTimeOffset]::Now

        $screenshot = Save-Snapshot -RunId $runId -RunDirectory $runDirectory
        $hilog = @(Invoke-Hdc -Arguments @('shell', 'hilog', '-x'))
        $interesting = @($hilog | Where-Object {
            $_ -match 'WineEngine|product D3D backend|WINEHUA_D3D_BACKEND|' +
                '\[VENUS-PRESENT\]|\[VENUS-FRAME-TIMELINE\]|\[VIRGL-PERF\]|' +
                'WineHuaModernMappedFlushPerf|VK_ERROR|device.?lost|CRASH|FATAL'
        })
        $interesting | Set-Content -LiteralPath (Join-Path $runDirectory 'graphics-hilog.txt') -Encoding UTF8

        $presentLines = @($interesting | Where-Object {
            $_ -match '\[VENUS-PRESENT\]\[NCP\].*\bframes=' })
        $timelineSamples = @($interesting | Where-Object {
            $_ -match '\[VENUS-FRAME-TIMELINE\]\[NCP\]' } |
            ForEach-Object { Convert-KeyValueLogLine -Line $_ })
        $perfMarkers = @($interesting | Where-Object {
            $_ -match '\[VIRGL-PERF\]|WineHuaModernMappedFlushPerf' } |
            Select-Object -Last 80)
        $mappedFlushLines = @($interesting | Where-Object {
            $_ -match 'WineHuaModernMappedFlushPerf' })
        $graphicsContextPattern = [regex]::Escape($bundle) +
            '|WineHua|WineEngine|DXVK|VENUS|VIRGL|WL_NAPI|WL_Broker'
        $criticalErrors = @($interesting | Where-Object {
            $_ -match 'VK_ERROR|device.?lost|CRASH|FATAL' -and
            $_ -match $graphicsContextPattern
        })
        $backendObserved = [bool]($interesting | Where-Object {
            $_ -match [regex]::Escape("backend=$($Condition.backend)") -or
            $_ -match [regex]::Escape("WINEHUA_D3D_BACKEND=$($Condition.backend)")
        } | Select-Object -First 1)

        $result['measurementStartedAt'] = $measurementStartedAt.ToString('o')
        $result['measurementEndedAt'] = $measurementEndedAt.ToString('o')
        $result['actualSampleSeconds'] = [Math]::Round(
            ($measurementEndedAt - $measurementStartedAt).TotalSeconds, 3)
        $result['backendObserved'] = $backendObserved
        $result['screenshot'] = $screenshot
        $result['imageSignal'] = Get-ImageSignal -Path $screenshot
        $result['venusPresent'] = if ($presentLines.Count) {
            Convert-KeyValueLogLine -Line $presentLines[-1]
        } else { $null }
        $result['presentTransport'] = if ($result['venusPresent']) {
            $result['venusPresent'].transport
        } else { $null }
        $result['presentActionContract'] =
            Test-PresentActionContract -Present $result['venusPresent']
        $result['venusTimeline'] = Get-TimelineStatistics -Samples $timelineSamples
        $result['graphicsPerfMarkers'] = $perfMarkers
        $result['modernMappedFlush'] = if ($mappedFlushLines.Count) {
            Convert-KeyValueLogLine -Line $mappedFlushLines[-1]
        } else { $null }
        $result['criticalErrors'] = $criticalErrors
        $result['status'] = if (-not $backendObserved -or $presentLines.Count -eq 0 -or
            $null -eq $result['presentActionContract']) {
            'INCONCLUSIVE'
        } elseif ($criticalErrors.Count -gt 0 -or
            -not $result['presentActionContract']) {
            'FAIL'
        } else {
            'MEASURED'
        }
    } catch {
        $result['message'] = $_.Exception.Message
    } finally {
        try {
            Invoke-Hdc -Arguments @('shell', 'aa', 'force-stop', $bundle) | Out-Null
        } catch {
            $result['forceStopError'] = $_.Exception.Message
        }
        $result['endedAt'] = [DateTimeOffset]::Now.ToString('o')
        $result | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $runDirectory 'result.json') -Encoding UTF8
    }
    return [pscustomobject]$result
}

$conditions = @(
    [pscustomobject]@{
        id = 'legacy-1.10-product'
        backend = 'dxvk_legacy'
        batchMappedFlushMode = 'product'
    },
    [pscustomobject]@{
        id = 'modern-2.6-product'
        backend = 'dxvk_modern_2_6'
        batchMappedFlushMode = 'product'
    }
)
if ($IncludeModernBatchMappedFlushOff) {
    $conditions += [pscustomobject]@{
        id = 'modern-2.6-batch-flush-off'
        backend = 'dxvk_modern_2_6'
        batchMappedFlushMode = 'off'
    }
}

$results = [System.Collections.Generic.List[object]]::new()
for ($round = 0; $round -lt $Rounds; ++$round) {
    for ($order = 0; $order -lt $conditions.Count; ++$order) {
        $condition = $conditions[($order + $round) % $conditions.Count]
        Write-Host "DXVK performance run: round=$($round + 1) order=$($order + 1) condition=$($condition.id)"
        $results.Add((Invoke-Measurement -Condition $condition -Round ($round + 1) -Order ($order + 1)))
        if ($CooldownSeconds -gt 0 -and
            -not ($round -eq $Rounds - 1 -and $order -eq $conditions.Count - 1)) {
            Start-Sleep -Seconds $CooldownSeconds
        }
    }
}

$aggregates = [System.Collections.Generic.List[object]]::new()
$legacyAverageFps = $null
foreach ($condition in $conditions) {
    $conditionResults = @($results | Where-Object condition -eq $condition.id)
    [double[]]$fpsValues = @($conditionResults | ForEach-Object {
        if ($_.venusPresent -and $null -ne $_.venusPresent.fps) {
            [double]$_.venusPresent.fps
        }
    })
    $averageFps = if ($fpsValues.Count) {
        [Math]::Round(($fpsValues | Measure-Object -Average).Average, 3)
    } else { $null }
    if ($condition.id -eq 'legacy-1.10-product') {
        $legacyAverageFps = $averageFps
    }
    $aggregates.Add([pscustomobject][ordered]@{
        condition = $condition.id
        runs = $conditionResults.Count
        measuredRuns = @($conditionResults | Where-Object status -eq 'MEASURED').Count
        transportsObserved = @($conditionResults |
            ForEach-Object { $_.presentTransport } | Where-Object { $_ } |
            Sort-Object -Unique)
        actionContractPasses = @($conditionResults |
            Where-Object presentActionContract -eq $true).Count
        averagePresenterFps = $averageFps
        presenterFpsP50 = Get-NearestRankPercentile -Values $fpsValues -Percentile 0.50
        presenterFpsMin = if ($fpsValues.Count) {
            [Math]::Round(($fpsValues | Measure-Object -Minimum).Minimum, 3)
        } else { $null }
        presenterFpsMax = if ($fpsValues.Count) {
            [Math]::Round(($fpsValues | Measure-Object -Maximum).Maximum, 3)
        } else { $null }
    })
}
if ($legacyAverageFps) {
    foreach ($aggregate in $aggregates) {
        if ($null -ne $aggregate.averagePresenterFps) {
            $aggregate | Add-Member -NotePropertyName relativeToLegacyPercent -NotePropertyValue (
                [Math]::Round((($aggregate.averagePresenterFps / $legacyAverageFps) - 1.0) * 100.0, 2))
        }
    }
}

$comparison = [ordered]@{
    schemaVersion = 3
    sessionId = $sessionId
    observationExperiment = $observationExperiment
    rounds = $Rounds
    warmupSeconds = $WarmupSeconds
    sampleSeconds = $SampleSeconds
    cooldownSeconds = $CooldownSeconds
    collectModernMappedFlushStats = [bool]$CollectModernMappedFlushStats
    status = if (@($results | Where-Object status -ne 'MEASURED').Count) {
        'INCONCLUSIVE'
    } else {
        'MEASURED'
    }
    aggregates = @($aggregates)
    runs = @($results)
}
$comparisonPath = Join-Path $sessionRoot 'comparison.json'
$comparison | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $comparisonPath -Encoding UTF8
$comparison | ConvertTo-Json -Depth 5
Write-Host "DXVK performance archive: $comparisonPath"
if ($comparison.status -eq 'MEASURED') { exit 0 }
exit 2
