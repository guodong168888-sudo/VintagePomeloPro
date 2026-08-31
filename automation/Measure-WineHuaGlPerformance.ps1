[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunLabel,
    [ValidateSet('egl-window', 'gles-direct')][string]$ExpectedTransport = 'egl-window',
    [string]$GamePath = 'Z:/games/Warcraft III/Warcraft III/Frozen Throne.exe',
    [ValidateRange(0, 180)][int]$WarmupSeconds = 30,
    [ValidateRange(20, 600)][int]$SampleSeconds = 90,
    [ValidateRange(10, 300)][int]$ReadyTimeoutSeconds = 180,
    [int]$ExpectedWidth = 800, [int]$ExpectedHeight = 600,
    [switch]$Attach,
    [string]$DeviceId = '',
    [string]$HdcPath = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$OutputRoot = '',
    [string]$HapSha256 = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GlTiming.ps1')
if ($RunLabel -notmatch '^[a-zA-Z0-9_-]+$') { throw 'RunLabel must be ASCII letters, digits, dash or underscore' }
if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot '../.hvigor/outputs/gl-performance' }
if (-not $DeviceId) {
    $targets = @(& $HdcPath list targets | Where-Object { $_ -and $_ -notmatch '\[Empty\]' })
    if ($targets.Count -ne 1) { throw 'Exactly one HDC device required' }
    $DeviceId = ($targets[0] -split '\s+')[0]
}
function Read-GlLogs {
    $lines = @(& $HdcPath -t $DeviceId shell "hilog -x | grep -E 'VIRGL-ZC|timestamp regression'" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'HDC log collection failed' }
    return $lines
}
$seen = [Collections.Generic.HashSet[string]]::new()
foreach ($line in @(Read-GlLogs)) { [void]$seen.Add($line) }
if (-not $Attach) {
    & (Join-Path $PSScriptRoot 'Start-WineHuaGameTest.ps1') -GamePath $GamePath `
        -D3DBackend wined3d -GraphicsExperiment observe-product-summary `
        -DeviceId $DeviceId -HdcPath $HdcPath
}
$readyDeadline = [DateTime]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
$ready = $false
do {
    foreach ($line in @(Read-GlLogs)) {
        if ($seen.Add($line) -and $line -match '\[VIRGL-ZC\]\[NCP\] blit frames=(\d+)' -and
            [long]$Matches[1] -ge 120 -and $line -match "size=${ExpectedWidth}x${ExpectedHeight}(\s|$)") {
            $ready = $true
        }
    }
    if (-not $ready) { Start-Sleep -Seconds 2 }
} while (-not $ready -and [DateTime]::UtcNow -lt $readyDeadline)
if (-not $ready) { throw 'No ready GL workload with expected dimensions; focus/menu must be checked' }
Write-Host "Ready: $RunLabel. Warmup ${WarmupSeconds}s; sampling ${SampleSeconds}s."
for ($i = 0; $i -lt $WarmupSeconds; $i++) { Start-Sleep -Seconds 1 }
foreach ($line in @(Read-GlLogs)) { [void]$seen.Add($line) }
$captured = [Collections.Generic.List[string]]::new()
$sampleDeadline = [DateTime]::UtcNow.AddSeconds($SampleSeconds)
$skipBoundaryWindow = $true
do {
    Start-Sleep -Seconds 2
    foreach ($line in @(Read-GlLogs)) {
        if (-not $seen.Add($line)) { continue }
        if ($line -match '\[TIMING\]' -and $skipBoundaryWindow) {
            $skipBoundaryWindow = $false
            continue # This window began during warmup.
        }
        $captured.Add($line)
    }
} while ([DateTime]::UtcNow -lt $sampleDeadline)
$runDir = Join-Path $OutputRoot ("$RunLabel-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$captured | Set-Content -LiteralPath (Join-Path $runDir 'graphics.log') -Encoding UTF8
$result = [ordered]@{
    label = $RunLabel; sourceCommit = (git -C (Join-Path $PSScriptRoot '..') rev-parse HEAD)
    hapSha256 = $HapSha256; batchMappedFlush = 'product-default-no-override'; backend = 'wined3d'
    width = $ExpectedWidth; height = $ExpectedHeight; status = 'INCONCLUSIVE'
    visualReviewRequired = $true; metrics = $null
}
try {
    if (@($captured | Where-Object { $_ -match 'timestamp regression|CPU_FALLBACK|blit dropped|update failed' }).Count) {
        throw 'GL correctness warning during sample'
    }
    $result.metrics = ConvertFrom-GlTiming $captured.ToArray() $ExpectedTransport
    if ($result.metrics.sampledSeconds -lt $SampleSeconds * 0.75) { throw 'Insufficient timing coverage' }
    $result.status = 'MEASURED'
} catch { $result['reason'] = $_.Exception.Message }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'result.json') -Encoding UTF8
& $HdcPath -t $DeviceId shell snapshot_display -f /data/local/tmp/winehua-gl-measure.jpeg | Out-Null
& $HdcPath -t $DeviceId file recv /data/local/tmp/winehua-gl-measure.jpeg (Join-Path $runDir 'frame.jpeg') | Out-Null
Write-Host ($result | ConvertTo-Json -Depth 8)
Write-Host "Evidence: $runDir"
if ($result.status -ne 'MEASURED') { throw $result.reason }
