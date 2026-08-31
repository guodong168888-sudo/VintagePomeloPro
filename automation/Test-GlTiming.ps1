$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GlTiming.ps1')
$cpu = (@(1..120) -join ',')
$interval = ((@(10000) * 120) -join ',')
$first = "[VIRGL-ZC][TIMING] key=1 frames=120 transport=egl-window count=120 request_us=120 draw_us=240 publish_us=360 restore_us=480 cpu_us=$cpu interval_us=$interval"
$second = $first.Replace('frames=120', 'frames=240')
$result = ConvertFrom-GlTiming @($first, $second, $second) 'egl-window'
if ($result.windows -ne 2 -or $result.presenterFps -ne 100 -or
    $result.cpuUs.p95 -ne 114 -or $result.stageMeanUs.publish -ne 3) { throw 'Timing aggregation failed' }
foreach ($bad in @(
    $second.Replace('transport=egl-window', 'transport=gles-direct'),
    $second.Replace('frames=240', 'frames=360'),
    $second.Replace('request_us=120 ', ''),
    $second.Replace('draw_us=240', 'draw_us=-1'),
    $second.Replace('cpu_us=1,', 'cpu_us=NaN,'),
    $second.Replace("cpu_us=$cpu", 'cpu_us=1,2'),
    $second.Replace('key=1', 'key=2'))) {
    $rejected = $false
    try { ConvertFrom-GlTiming @($first, $bad) 'egl-window' | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid sample was accepted' }
}
Write-Host 'GlTiming parser PASS (aggregation, dedup, transport, gap, truncation, invalid numbers, surface isolation)'
