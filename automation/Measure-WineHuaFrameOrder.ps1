[CmdletBinding()]
param(
    [ValidateSet('dxvk_legacy', 'dxvk_modern_2_6', 'wined3d')]
    [string]$D3DBackend = 'dxvk_legacy',
    [AllowEmptyString()]
    [string]$GraphicsExperiment = '',
    [ValidateSet('product', 'on', 'off')]
    [string]$BatchMappedFlushMode = 'product',
    [string]$GamePath = 'C:\smoke\x64\winehua_d3d_switch_cube.exe',
    [string[]]$GameArguments = @(),
    [ValidateRange(8, 120)]
    [int]$Samples = 40,
    [ValidateRange(50, 2000)]
    [int]$IntervalMs = 120,
    [ValidateRange(5, 120)]
    [int]$StartupTimeoutSeconds = 45,
    [string]$DeviceId = '',
    [string]$HdcPath = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$OutputRoot = 'D:\MyProject\winehua-logs\automation'
)

$ErrorActionPreference = 'Stop'
$hdc = $HdcPath
$bundle = 'com.vintage.pomelopro'
$startScript = Join-Path $PSScriptRoot 'Start-WineHuaGameTest.ps1'
$batchLabel = if ($BatchMappedFlushMode -eq 'product') {
    ''
} else {
    "-batch-flush-$BatchMappedFlushMode"
}
$runId = 'frame-order-{0}{1}-{2}' -f $D3DBackend, $batchLabel,
    (Get-Date -Format 'yyyyMMdd-HHmmss')
$output = Join-Path $OutputRoot $runId
$frames = Join-Path $output 'frames'
$remoteRoot = '/data/local/tmp/winehua-frame-order'
# Keep in sync with FRAME_MARKER_STEP_FRAMES in winehua_d3d_switch_cube.c.
# The probe encodes a marker step, while the report exposes actual frames.
$markerFramesPerStep = 8

if (-not (Test-Path -LiteralPath $hdc)) { throw "Windows HDC not found: $hdc" }
if (-not (Test-Path -LiteralPath $startScript)) { throw "Launcher not found: $startScript" }
if (-not $DeviceId) {
    $targets = @(& $hdc list targets | Where-Object { $_ -and $_ -notmatch '^\[Empty\]' } |
        ForEach-Object { ($_ -split '\s+')[0] })
    if ($targets.Count -ne 1) {
        throw "Expected one connected Windows HDC target, found $($targets.Count)"
    }
    $DeviceId = $targets[0]
}
New-Item -ItemType Directory -Path $frames -Force | Out-Null
Add-Type -AssemblyName System.Drawing

function Invoke-Hdc {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & $hdc -t $DeviceId @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($result -join "`n")"
    }
    return $result
}

function Get-FrameMarker {
    param([Parameter(Mandatory)][string]$Path)

    $bitmap = [System.Drawing.Bitmap]::new($Path)
    try {
        # The marker is a blue-dominant quad in the upper-left part of the D3D
        # client. R and G store the high/low nibbles as 4 + nibble * 8.
        $maxX = [Math]::Min($bitmap.Width - 1,
            [Math]::Max(260, [Math]::Min(360, [int]($bitmap.Width * 0.18))))
        $upperMaxY = [Math]::Min($bitmap.Height - 1,
            [Math]::Max(180, [Math]::Min(320, [int]($bitmap.Height * 0.22))))
        # Older tablet transforms placed the marker at lower-left, while the
        # current phone transform preserves the original upper-left position.
        # Start below the Wine title bar: its blue chrome otherwise qualifies
        # as a second marker region and contaminates the encoded colour read.
        $regions = @(
            [pscustomobject]@{
                minY = [Math]::Max(64, [int]($bitmap.Height * 0.05))
                maxY = $upperMaxY
            },
            [pscustomobject]@{
                minY = [Math]::Max(90, [int]($bitmap.Height * 0.60))
                maxY = [Math]::Min($bitmap.Height - 1, [int]($bitmap.Height * 0.90))
            }
        )
        foreach ($region in $regions) {
            [long]$sumR = 0
            [long]$sumG = 0
            [long]$sumB = 0
            [long]$sumSquareR = 0
            [long]$sumSquareG = 0
            [long]$sumSquareB = 0
            [int]$count = 0
            [int]$minHitX = $bitmap.Width
            [int]$maxHitX = -1
            [int]$minHitY = $bitmap.Height
            [int]$maxHitY = -1
            for ($y = $region.minY; $y -le $region.maxY; $y += 2) {
                for ($x = 0; $x -le $maxX; $x += 2) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    if ($pixel.B -ge 180 -and
                        ($pixel.B - $pixel.R) -ge 70 -and
                        ($pixel.B - $pixel.G) -ge 70) {
                        $sumR += $pixel.R
                        $sumG += $pixel.G
                        $sumB += $pixel.B
                        $sumSquareR += $pixel.R * $pixel.R
                        $sumSquareG += $pixel.G * $pixel.G
                        $sumSquareB += $pixel.B * $pixel.B
                        $minHitX = [Math]::Min($minHitX, $x)
                        $maxHitX = [Math]::Max($maxHitX, $x)
                        $minHitY = [Math]::Min($minHitY, $y)
                        $maxHitY = [Math]::Max($maxHitY, $y)
                        ++$count
                    }
                }
            }
            if ($count -lt 500) { continue }

            $averageR = [double]$sumR / $count
            $averageG = [double]$sumG / $count
            $averageB = [double]$sumB / $count
            $stddevR = [Math]::Sqrt([Math]::Max(0.0, [double]$sumSquareR / $count - $averageR * $averageR))
            $stddevG = [Math]::Sqrt([Math]::Max(0.0, [double]$sumSquareG / $count - $averageG * $averageG))
            $stddevB = [Math]::Sqrt([Math]::Max(0.0, [double]$sumSquareB / $count - $averageB * $averageB))
            $hitWidth = $maxHitX - $minHitX + 2
            $hitHeight = $maxHitY - $minHitY + 2
            $sampledArea = [Math]::Max(1.0, ($hitWidth / 2.0) * ($hitHeight / 2.0))
            $fillRatio = $count / $sampledArea
            # Reject blue UI artwork and status icons: the encoded marker is a
            # nearly uniform, filled horizontal rectangle with nibble channels
            # restricted to 4..124 (allowing a small JPEG margin).
            if ($averageR -gt 132 -or $averageG -gt 132 -or $averageB -lt 210 -or
                $stddevR -gt 18 -or $stddevG -gt 18 -or $stddevB -gt 18 -or
                $hitWidth -lt 60 -or $hitHeight -lt 30 -or
                $hitWidth -lt (1.35 * $hitHeight) -or $fillRatio -lt 0.55) {
                continue
            }

            $high = [Math]::Max(0, [Math]::Min(15, [int][Math]::Round(($averageR - 4.0) / 8.0)))
            $low = [Math]::Max(0, [Math]::Min(15, [int][Math]::Round(($averageG - 4.0) / 8.0)))
            return [pscustomobject]@{
                valid = $true
                pixels = $count
                value = (($high -shl 4) -bor $low)
                averageR = [Math]::Round($averageR, 2)
                averageG = [Math]::Round($averageG, 2)
                averageB = [Math]::Round($averageB, 2)
            }
        }
        return [pscustomobject]@{ valid = $false; pixels = 0; value = $null }
    } finally {
        $bitmap.Dispose()
    }
}

function Save-Snapshot {
    param([Parameter(Mandatory)][string]$Name)
    $remote = "$remoteRoot-$Name.jpeg"
    $local = Join-Path $frames "$Name.jpeg"
    Invoke-Hdc -Arguments @('shell', 'snapshot_display', '-f', $remote) | Out-Null
    Invoke-Hdc -Arguments @('file', 'recv', $remote, $local) | Out-Null
    Invoke-Hdc -Arguments @('shell', 'rm', '-f', $remote) | Out-Null
    return [pscustomobject]@{ path = $local; marker = Get-FrameMarker -Path $local }
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

$records = [System.Collections.Generic.List[object]]::new()
$started = $false
$summary = $null
try {
    Invoke-Hdc -Arguments @('shell', 'hilog', '-r') | Out-Null
    $launchParameters = @{
        D3DBackend = $D3DBackend
        GraphicsExperiment = $GraphicsExperiment
        GamePath = $GamePath
        GameArguments = $GameArguments
        DeviceId = $DeviceId
        HdcPath = $hdc
        BatchMappedFlushMode = $BatchMappedFlushMode
    }
    & $startScript @launchParameters |
        Tee-Object -FilePath (Join-Path $output 'launch.txt')
    if ($LASTEXITCODE -ne 0) { throw 'WineHua game launcher failed' }
    $started = $true

    $profileObserved = $false
    $profileDeadline = (Get-Date).AddSeconds(10)
    $expectedGraphicsPolicy = if ($GraphicsExperiment) {
        $GraphicsExperiment
    } elseif ($D3DBackend -eq 'wined3d') {
        'product-virgl'
    } else {
        'product-vulkan'
    }
    $profileNeedle = "graphics profile=$expectedGraphicsPolicy "
    do {
        Start-Sleep -Milliseconds 300
        $profileLog = @(Invoke-Hdc -Arguments @('shell', 'hilog', '-x'))
        if (($profileLog -join "`n").Contains($profileNeedle)) {
            $profileObserved = $true
            break
        }
    } while ((Get-Date) -lt $profileDeadline)
    if (-not $profileObserved) {
        throw "Requested graphics policy was not observed: $expectedGraphicsPolicy"
    }

    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    $startupIndex = 0
    do {
        Start-Sleep -Milliseconds 800
        $snapshot = Save-Snapshot -Name ('startup-{0:d2}' -f $startupIndex++)
        if ($snapshot.marker.valid) { break }
    } while ((Get-Date) -lt $deadline)
    if (-not $snapshot.marker.valid) {
        throw "Frame marker was not found within $StartupTimeoutSeconds seconds"
    }

    for ($i = 0; $i -lt $Samples; ++$i) {
        $capturedAt = [DateTimeOffset]::Now
        $snapshot = Save-Snapshot -Name ('sample-{0:d3}' -f $i)
        $records.Add([pscustomobject]@{
            index = $i
            capturedAt = $capturedAt.ToString('o')
            markerValid = [bool]$snapshot.marker.valid
            marker = $snapshot.marker.value
            pixels = $snapshot.marker.pixels
            averageR = $snapshot.marker.averageR
            averageG = $snapshot.marker.averageG
            averageB = $snapshot.marker.averageB
            image = [IO.Path]::GetFileName($snapshot.path)
        })
        Start-Sleep -Milliseconds $IntervalMs
    }

    $valid = @($records | Where-Object markerValid)
    $regressions = [System.Collections.Generic.List[object]]::new()
    $duplicates = 0
    $forwardDeltas = [System.Collections.Generic.List[int]]::new()
    for ($i = 1; $i -lt $valid.Count; ++$i) {
        $previous = [int]$valid[$i - 1].marker
        $current = [int]$valid[$i].marker
        $delta = ($current - $previous + 256) % 256
        if ($delta -eq 0) {
            ++$duplicates
        } elseif ($delta -gt 128) {
            $regressions.Add([pscustomobject]@{
                fromIndex = $valid[$i - 1].index
                toIndex = $valid[$i].index
                previous = $previous
                current = $current
                moduloDelta = $delta
            })
        } else {
            $forwardDeltas.Add($delta)
        }
    }

    $minimumValid = [Math]::Ceiling($Samples * 0.75)
    $trailingInvalid = 0
    for ($i = $records.Count - 1; $i -ge 0 -and -not $records[$i].markerValid; --$i) {
        ++$trailingInvalid
    }
    $status = if ($valid.Count -lt $minimumValid) {
        'INCONCLUSIVE'
    } elseif ($regressions.Count -gt 0 -or $trailingInvalid -gt 2) {
        'FAIL'
    } else {
        'PASS'
    }

    [long]$forwardFrames = 0
    $frameTimeMs = [System.Collections.Generic.List[double]]::new()
    for ($i = 1; $i -lt $valid.Count; ++$i) {
        $previous = [int]$valid[$i - 1].marker
        $current = [int]$valid[$i].marker
        $delta = ($current - $previous + 256) % 256
        if ($delta -le 0 -or $delta -gt 128) { continue }
        $previousAt = [DateTimeOffset]::Parse($valid[$i - 1].capturedAt)
        $currentAt = [DateTimeOffset]::Parse($valid[$i].capturedAt)
        $elapsedMs = ($currentAt - $previousAt).TotalMilliseconds
        if ($elapsedMs -le 0) { continue }
        $forwardFrames += $delta * $markerFramesPerStep
        $frameTimeMs.Add($elapsedMs / ($delta * $markerFramesPerStep))
    }
    $measurementSeconds = if ($valid.Count -gt 1) {
        ([DateTimeOffset]::Parse($valid[-1].capturedAt) -
            [DateTimeOffset]::Parse($valid[0].capturedAt)).TotalSeconds
    } else { 0.0 }
    $estimatedDisplayedFps = if ($measurementSeconds -gt 0) {
        [Math]::Round($forwardFrames / $measurementSeconds, 3)
    } else { $null }
    $summary = [ordered]@{
        schemaVersion = 3
        runId = $runId
        status = $status
        d3dBackend = $D3DBackend
        graphicsExperiment = $GraphicsExperiment
        batchMappedFlushMode = $BatchMappedFlushMode
        gamePath = $GamePath
        markerFramesPerStep = $markerFramesPerStep
        samplesRequested = $Samples
        samplesValid = $valid.Count
        duplicates = $duplicates
        trailingInvalid = $trailingInvalid
        regressions = @($regressions)
        averageForwardDelta = if ($forwardDeltas.Count) {
            [Math]::Round(($forwardDeltas | Measure-Object -Average).Average, 2)
        } else { $null }
        maxForwardDelta = if ($forwardDeltas.Count) {
            ($forwardDeltas | Measure-Object -Maximum).Maximum
        } else { $null }
        measurementSeconds = [Math]::Round($measurementSeconds, 3)
        estimatedDisplayedFps = $estimatedDisplayedFps
        estimatedFrameTimeMsP50 = if ($frameTimeMs.Count) {
            Get-NearestRankPercentile -Values $frameTimeMs.ToArray() -Percentile 0.50
        } else { $null }
        estimatedFrameTimeMsP95 = if ($frameTimeMs.Count) {
            Get-NearestRankPercentile -Values $frameTimeMs.ToArray() -Percentile 0.95
        } else { $null }
        estimatedFrameTimeMsP99 = if ($frameTimeMs.Count) {
            Get-NearestRankPercentile -Values $frameTimeMs.ToArray() -Percentile 0.99
        } else { $null }
        records = @($records)
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding UTF8
} catch {
    $summary = [ordered]@{
        schemaVersion = 2
        runId = $runId
        status = 'INFRA_ERROR'
        d3dBackend = $D3DBackend
        graphicsExperiment = $GraphicsExperiment
        batchMappedFlushMode = $BatchMappedFlushMode
        gamePath = $GamePath
        message = $_.Exception.Message
        records = @($records)
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding UTF8
} finally {
    try {
        $hilog = Invoke-Hdc -Arguments @('shell', 'hilog', '-x')
        $hilog | Set-Content -LiteralPath (Join-Path $output 'hilog.txt') -Encoding UTF8
        $presentLines = @($hilog | Where-Object {
            $_ -match '\[VENUS-PRESENT\]\[NCP\].*\bframes=' })
        if ($presentLines.Count -gt 0) {
            $summary['venusPresent'] = Convert-KeyValueLogLine -Line $presentLines[-1]
            $summary['presentTransport'] = $summary['venusPresent'].transport
            $summary['presentActionContract'] =
                Test-PresentActionContract -Present $summary['venusPresent']
            if ($summary['status'] -eq 'PASS' -and
                $summary['presentActionContract'] -ne $true) {
                $summary['status'] = 'INCONCLUSIVE'
            }
        }
        $timelineLines = @($hilog | Where-Object {
            $_ -match '\[VENUS-FRAME-TIMELINE\]\[NCP\]' } |
            Select-Object -Last 32)
        if ($timelineLines.Count -gt 0) {
            $summary['venusFrameTimeline'] = @($timelineLines | ForEach-Object {
                Convert-KeyValueLogLine -Line $_
            })
        }
        $graphicsPerfLines = @($hilog | Where-Object {
            $_ -match '\[VIRGL-PERF\]' } | Select-Object -Last 48)
        if ($graphicsPerfLines.Count -gt 0) {
            $summary['graphicsPerfMarkers'] = $graphicsPerfLines
        }
        $summary | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding UTF8
    } catch {
        $_ | Out-String | Set-Content -LiteralPath (Join-Path $output 'hilog-error.txt') -Encoding UTF8
    }
    if ($started) {
        try { Invoke-Hdc -Arguments @('shell', 'aa', 'force-stop', $bundle) | Out-Null } catch {}
    }
}

$summary | ConvertTo-Json -Depth 4
Write-Host "Frame-order archive: $output"
if ($summary.status -eq 'PASS') { exit 0 }
if ($summary.status -eq 'FAIL') { exit 1 }
exit 2
