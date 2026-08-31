# Pure parsing helpers: no HDC calls, environment changes, or product policy.
function Get-GlPercentiles {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $result = [ordered]@{ count = $sorted.Count }
    foreach ($p in @(50, 95, 99)) {
        $index = [Math]::Max(0, [Math]::Ceiling($sorted.Count * $p / 100.0) - 1)
        $result["p$p"] = $sorted[$index]
    }
    return [pscustomobject]$result
}

function ConvertFrom-GlTiming {
    param([string[]]$Lines, [string]$ExpectedTransport)
    $rows = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new()
    foreach ($line in $Lines) {
        if ($line -notmatch '\[VIRGL-ZC\]\[TIMING\]') { continue }
        $fields = @{}
        foreach ($match in [regex]::Matches($line, '(?<key>\w+)=(?<value>[^\s]+)')) {
            $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
        }
        foreach ($key in @('key', 'frames', 'transport', 'count', 'cpu_us', 'interval_us',
                           'request_us', 'draw_us', 'publish_us', 'restore_us')) {
            if (-not $fields.ContainsKey($key)) { throw "Incomplete GL timing field: $key" }
        }
        if ($fields.transport -ne $ExpectedTransport) { throw 'Unexpected GL transport; do not mix baselines' }
        if (-not $seen.Add("$($fields.key):$($fields.frames)")) { continue }
        $cpu = @($fields.cpu_us.Split(',') | ForEach-Object { [double]$_ })
        $intervals = @($fields.interval_us.Split(',') | ForEach-Object { [double]$_ })
        if ($cpu.Count -ne 120 -or $intervals.Count -ne 120 -or $fields.count -ne '120') {
            throw 'Truncated GL timing window'
        }
        if (@(($cpu + $intervals) | Where-Object {
            $_ -lt 0 -or [double]::IsNaN($_) -or [double]::IsInfinity($_)
        }).Count) { throw 'Invalid GL timing number' }
        foreach ($stage in @('request_us', 'draw_us', 'publish_us', 'restore_us')) {
            if ([long]$fields[$stage] -lt 0) { throw 'Negative stage duration' }
        }
        $rows.Add([pscustomobject]@{
            key = $fields.key; frames = [long]$fields.frames
            cpu = $cpu; intervals = $intervals
            requestUs = [long]$fields.request_us; drawUs = [long]$fields.draw_us
            publishUs = [long]$fields.publish_us; restoreUs = [long]$fields.restore_us
        })
    }
    if ($rows.Count -lt 2) { throw 'Insufficient complete GL timing windows' }
    $keys = @($rows | ForEach-Object key | Sort-Object -Unique)
    if ($keys.Count -ne 1) { throw 'Multiple GL surfaces; select one workload before comparison' }
    $ordered = @($rows | Sort-Object frames)
    for ($i = 1; $i -lt $ordered.Count; $i++) {
        if ($ordered[$i].frames - $ordered[$i - 1].frames -ne 120) {
            throw 'Missing GL timing window: log loss invalidates percentiles'
        }
    }
    $cpuValues = @($ordered | ForEach-Object { $_.cpu })
    $intervalValues = @($ordered | ForEach-Object { $_.intervals } | Where-Object { $_ -gt 0 })
    $durationUs = ($intervalValues | Measure-Object -Sum).Sum
    if ($durationUs -le 0) { throw 'No progressing GL timestamps' }
    return [pscustomobject]@{
        transport = $ExpectedTransport; windows = $ordered.Count
        sampledSeconds = $durationUs / 1000000.0
        presenterFps = $intervalValues.Count * 1000000.0 / $durationUs
        cpuUs = Get-GlPercentiles $cpuValues
        frameIntervalUs = Get-GlPercentiles $intervalValues
        # Stage sums / frame, not percentiles of sparse averages.
        stageMeanUs = [pscustomobject]@{
            request = ($ordered | Measure-Object requestUs -Sum).Sum / $cpuValues.Count
            drawSubmit = ($ordered | Measure-Object drawUs -Sum).Sum / $cpuValues.Count
            publish = ($ordered | Measure-Object publishUs -Sum).Sum / $cpuValues.Count
            restore = ($ordered | Measure-Object restoreUs -Sum).Sum / $cpuValues.Count
        }
    }
}
