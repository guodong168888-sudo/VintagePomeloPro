$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HiperfSampleQuality.ps1')
function New-TestSample([string]$Ip, [int]$Thread, [int]$Period, [string]$Symbol, [string]$Marker = '') {
    return @"
record sample: type 9, misc 2, size 144
  ip $Ip
  pid 321, tid $Thread
  period $Period
  callchain nr=2
    0xfffffffffffffe00$Marker
    0x500004
  user stack: size 0 dyn_size 0

 callchain: 1
  01:0x0000000000500004 : $Symbol

"@
}
$placeholder = New-TestSample 'ffffff0000000fff' 322 90 'wine@0x500004@wine:0' ' <unwind callstack>'
$entry = New-TestSample '500004' 321 10 'pthread_routine@box64.so:0'
$mixed = $placeholder + "`n" + $entry
$result = ConvertFrom-HiperfSampleDump $mixed 321 2
if ($result.samples -ne 2 -or $result.rawPlaceholderSamples -ne 1 -or
    $result.callchainCandidateSamples -ne 1 -or $result.rawUserAddressSamples -ne 1 -or
    $result.unwindMarkedSamples -ne 1 -or $result.threadEntryLeafSamples -ne 1 -or
    $result.namedLeafSamples -ne 1 -or $result.threads[0].periodPercent -ne 90 -or
    $result.status -ne 'ATTRIBUTION_REVIEW_REQUIRED') { throw 'Quality/period weighting failed' }
$expanded = New-TestSample 'ffffff0000000fff' 321 1 'wine@0x500004@wine:0' ' <expand callstack>'
$result = ConvertFrom-HiperfSampleDump $expanded 321 1
if ($result.expandedStackSamples -ne 1 -or $result.missingCandidateSamples -ne 1) {
    throw 'Expanded-only stack incorrectly accepted as leaf'
}
$noChain = $placeholder.Replace('callchain nr=2', 'callchain nr=0').Replace("    0xfffffffffffffe00 <unwind callstack>`n", '').Replace("    0x500004`n", '')
$result = ConvertFrom-HiperfSampleDump $noChain 321 1
if ($result.missingCandidateSamples -ne 1) { throw 'Empty stack classified as useful' }
foreach ($invalid in @(
    $placeholder.Replace('pid 321', 'pid 456'),
    $placeholder.Replace('callchain nr=2', 'callchain nr=3'),
    $placeholder.Replace('  period 90', ''),
    $placeholder.Replace('period 90', 'period 0'),
    'not a sample dump')) {
    $rejected = $false
    try { ConvertFrom-HiperfSampleDump $invalid 321 1 | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid profile was accepted' }
}
$rejected = $false
try { ConvertFrom-HiperfSampleDump $placeholder 321 2 | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Record/dump sample-count mismatch was accepted' }
$crlf = $placeholder.Replace("`n", "`r`n")
ConvertFrom-HiperfSampleDump $crlf 321 1 | Out-Null
Write-Host 'Hiperf sample quality PASS (placeholders, candidates, symbols, period weighting, expansion, truncation, PID, CRLF)'

# Exercise orchestration without a device or Wine launch. Generated fixture
# evidence is tiny and stays in the ignored test-output tree.
$testRoot = Join-Path $PSScriptRoot ("../.hvigor/outputs/cpu-profile-tool-tests-" + [guid]::NewGuid().ToString('N'))
$testProfileState = @{ recordCalls = 0; transfers = 0; lostRecords = $false; dump = $placeholder }
function Invoke-TestHdc {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'list' -and $args[1] -eq 'targets') { return 'test-device' }
    if ($args[0] -ne '-t' -or $args[1] -ne 'test-device') { throw 'Missing explicit test device' }
    if ($args[2] -eq 'shell') {
        $command = $args[3]
        if ($command -eq 'ps -A -o PID,UID,NAME') {
            return @('PID UID NAME', '321 200123 com.vintage.pomelopro', '456 0 unrelated')
        }
        if ($command -like 'hiperf record *') {
            if ($command -notmatch '-p 321 -d 5 -f 99 -e hw-cpu-cycles:u --call-stack dwarf,8192 --callchain-useronly --disable-callstack-expand -o /data/local/tmp/winehua-cpu-') {
                throw 'Changed profile scope or sampling mode'
            }
            $testProfileState.recordCalls++
            $lost = if ($testProfileState.lostRecords) { 1 } else { 0 }
            return @('[ Sample records: 1, Non sample records: 10 ]', "[ Sample lost: $lost, Non sample lost: 0 ]")
        }
        if ($command -match '^hiperf (dump|report) -i /data/local/tmp/winehua-cpu-') { return 'done' }
        throw "Unexpected test shell command: $command"
    }
    if ($args[2] -eq 'file' -and $args[3] -eq 'recv') {
        $destination = [string]$args[5]
        if (-not [IO.Path]::IsPathRooted($destination)) { throw 'Transfer destination is not absolute' }
        $content = if ($destination.EndsWith('dump.txt')) { $testProfileState.dump } else { 'fixture' }
        Set-Content -LiteralPath $destination -Value $content -Encoding UTF8
        $testProfileState.transfers++
        return 'FileTransfer finish'
    }
    throw 'Unexpected test HDC command'
}
& (Join-Path $PSScriptRoot 'Measure-WineHuaCpuProfile.ps1') -TargetPid 321 -RunLabel mock-pass `
    -SceneLabel 'synthetic tool test' -SampleSeconds 5 -HdcPath Invoke-TestHdc -OutputRoot $testRoot
$summaryFile = @(Get-ChildItem -LiteralPath $testRoot -Filter result.json -Recurse)
if ($summaryFile.Count -ne 1) { throw 'Missing profile result' }
$summary = Get-Content -LiteralPath $summaryFile[0].FullName -Raw | ConvertFrom-Json
if ($summary.quality.samples -ne 1 -or $summary.environmentChanged -or $summary.performanceBenchmark -or
    $testProfileState.recordCalls -ne 1 -or $testProfileState.transfers -ne 3) { throw 'Runner provenance/transfer failed' }
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'Measure-WineHuaCpuProfile.ps1') -TargetPid 456 -RunLabel wrong-owner `
        -SceneLabel 'must reject' -SampleSeconds 5 -HdcPath Invoke-TestHdc -OutputRoot $testRoot
} catch { $rejected = $true }
if (-not $rejected -or $testProfileState.recordCalls -ne 1) { throw 'Unrelated UID was profiled' }
$testProfileState.lostRecords = $true
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'Measure-WineHuaCpuProfile.ps1') -TargetPid 321 -RunLabel sample-loss `
        -SceneLabel 'must reject' -SampleSeconds 5 -HdcPath Invoke-TestHdc -OutputRoot $testRoot
} catch { $rejected = $true }
if (-not $rejected -or $testProfileState.transfers -ne 3) { throw 'Lost-record capture was accepted' }
Write-Host 'Hiperf runner mock PASS (attach scope, UID guard, loss rejection, transfer, provenance)'
