[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$TargetPid,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$RunLabel,
    [Parameter(Mandatory)][string]$SceneLabel,
    [ValidateRange(5, 30)][int]$SampleSeconds = 10,
    [string]$DeviceId = '',
    [string]$HdcPath = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$OutputRoot = '',
    [string]$HapSha256 = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HiperfSampleQuality.ps1')
if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot '../.hvigor/outputs/cpu-performance' }
if (-not $DeviceId) {
    $targets = @(& $HdcPath list targets | Where-Object { $_ -and $_ -notmatch '^\[Empty\]' })
    if ($LASTEXITCODE -ne 0 -or $targets.Count -ne 1) { throw 'Exactly one HDC device required' }
    $DeviceId = ($targets[0] -split '\s+')[0]
}
function Invoke-ProfileShell([string]$Command) {
    $lines = @(& $HdcPath -t $DeviceId shell $Command 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'HDC profiling command failed' }
    return $lines
}
# Attach only. Launch through the normal application first; neither hdc-shell
# Wine startup nor another environment/profile is introduced by this tool.
$processes = @(Invoke-ProfileShell 'ps -A -o PID,UID,NAME' | ForEach-Object {
    if ($_ -match '^\s*(\d+)\s+(\d+)\s+(\S+)\s*$') {
        [pscustomobject]@{ id = [int]$Matches[1]; uid = $Matches[2]; name = $Matches[3] }
    }
})
$appUids = @($processes | Where-Object name -eq 'com.vintage.pomelopro' | ForEach-Object uid | Sort-Object -Unique)
$target = @($processes | Where-Object id -eq $TargetPid)
if ($appUids.Count -ne 1 -or $target.Count -ne 1 -or $target[0].uid -ne $appUids[0]) {
    throw 'Target PID is absent or not owned by the running WineHua application'
}
$runName = "$RunLabel-" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runDir = [IO.Path]::GetFullPath((Join-Path $OutputRoot $runName))
New-Item -ItemType Directory -Path $runDir | Out-Null
$remote = "/data/local/tmp/winehua-cpu-$runName"
$record = @(Invoke-ProfileShell "hiperf record -p $TargetPid -d $SampleSeconds -f 99 -e hw-cpu-cycles:u --call-stack dwarf,8192 --callchain-useronly --disable-callstack-expand -o $remote.data")
$record | Set-Content -LiteralPath (Join-Path $runDir 'record.txt') -Encoding UTF8
$recordText = $record -join "`n"
$count = [regex]::Match($recordText, 'Sample records:\s*(\d+)')
$loss = [regex]::Match($recordText, 'Sample lost:\s*(\d+),\s*Non sample lost:\s*(\d+)')
if (-not $count.Success -or [int]$count.Groups[1].Value -eq 0 -or -not $loss.Success -or
    $loss.Groups[1].Value -ne '0' -or $loss.Groups[2].Value -ne '0') {
    throw 'Recording incomplete, empty or lost records; do not produce a hotspot conclusion'
}
Invoke-ProfileShell "hiperf dump -i $remote.data -d -o $remote.dump.txt" | Out-Null
Invoke-ProfileShell "hiperf report -i $remote.data --sort tid,dso,func -o $remote.report.txt" | Out-Null
foreach ($suffix in @('data', 'dump.txt', 'report.txt')) {
    # Absolute Windows paths, not D:/ paths: Windows HDC misresolves the latter.
    $destination = Join-Path $runDir "profile.$suffix"
    & $HdcPath -t $DeviceId file recv "$remote.$suffix" $destination | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destination) -or
        (Get-Item -LiteralPath $destination).Length -eq 0) { throw 'Profile transfer failed' }
}
$quality = ConvertFrom-HiperfSampleDump -Text (Get-Content -LiteralPath (Join-Path $runDir 'profile.dump.txt') -Raw) `
    -TargetPid $TargetPid -ExpectedSamples ([int]$count.Groups[1].Value)
$result = [ordered]@{
    sourceCommit = (git -C (Join-Path $PSScriptRoot '..') rev-parse HEAD)
    hapSha256 = $HapSha256; scene = $SceneLabel; targetPid = $TargetPid
    seconds = $SampleSeconds; mode = 'dwarf-8192-no-stack-expansion'
    environmentChanged = $false; batchMappedFlush = 'untouched'
    # Profiling perturbs workload timing. Do not use this capture as an FPS A/B.
    performanceBenchmark = $false; quality = $quality
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'result.json') -Encoding UTF8
Write-Host "Recorded $($quality.samples) samples; $($quality.status). Evidence: $runDir"
foreach ($warning in $quality.warnings) { Write-Warning $warning }
