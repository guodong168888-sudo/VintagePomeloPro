#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NormalSmoke.ps1')
function Assert-Rejected($Action) {
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsupported legacy contract accepted' }
}
Assert-Rejected { Assert-NormalSmokeSuite 'dxvk' 'reuse' $false }
Assert-Rejected { Assert-NormalSmokeSuite 'core' 'clean' $false }
Assert-Rejected { Assert-NormalSmokeSuite 'core' 'reuse' $true }
$tests = @(Get-NormalSmokeTests 'core')
if ($tests.Count -ne 4 -or @((Get-NormalSmokeTests 'audio')).Count -ne 2 -or
    @((Get-NormalSmokeTests 'opengl')).Count -ne 2) { throw 'Wrong normal probe matrix' }
$result = @{ runId='current'; testId='audio-x64'; status='PASS'
    architecture=@{peArchitecture='x86_64'}
    metrics=@{hostConsumptionVerified=$true; framesSubmitted=144000; rms=1000} }
if (-not (Test-NormalSmokeResult $result $tests[0] 'current')) { throw 'Valid audio rejected' }
if (Test-NormalSmokeResult $result $tests[0] 'old') { throw 'Stale result accepted' }
$result.architecture.peArchitecture = 'x86'
if (Test-NormalSmokeResult $result $tests[0] 'current') { throw 'Wrong PE architecture accepted' }
$result.architecture.peArchitecture = 'x86_64'
$result.metrics.hostConsumptionVerified = $false
if (Test-NormalSmokeResult $result $tests[0] 'current') { throw 'Unconsumed audio accepted' }
$result.testId='opengl-x64'
$result.metrics=@{frames=60; width=960; height=540; fallbackDetected=$false}
if (-not (Test-NormalSmokeResult $result $tests[2] 'current')) { throw 'Valid GL rejected' }
$result.metrics.fallbackDetected=$true
if (Test-NormalSmokeResult $result $tests[2] 'current') { throw 'GL fallback accepted' }
$result.metrics.fallbackDetected=$null
if (Test-NormalSmokeResult $result $tests[2] 'current') { throw 'Missing metrics accepted' }
if (Test-NormalSmokeResult $null $tests[2] 'current') { throw 'Missing result accepted' }
Write-Host 'Normal smoke contract PASS (matrix, legacy rejection, identity, PE architecture, audio drain, GL metrics)'
