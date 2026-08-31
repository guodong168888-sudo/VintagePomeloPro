# Normal game-launcher contract. No second Wine environment or App smoke mode.
function Assert-NormalSmokeSuite {
    param([string]$Suite, [string]$Prefix, [bool]$Gate)
    if ($Suite -notin @('core', 'audio', 'opengl') -or $Prefix -ne 'reuse' -or $Gate) {
        throw 'Current EntryAbility only supports game launch. Use core/audio/opengl with Prefix reuse; legacy smoke suites and clean/Gate require migration, not a new App environment.'
    }
}

function Get-NormalSmokeTests {
    param([string]$Suite)
    Assert-NormalSmokeSuite $Suite 'reuse' $false
    foreach ($kind in @('audio', 'opengl')) {
        if ($Suite -ne 'core' -and $Suite -ne $kind) { continue }
        foreach ($arch in @('x64', 'x86')) {
            $program = if ($kind -eq 'opengl') { 'graphics' } else { 'audio' }
            [pscustomobject]@{
                id = "$kind-$arch"
                executable = "C:/smoke/$arch/winehua_${program}_smoke.exe"
                peArchitecture = if ($arch -eq 'x64') { 'x86_64' } else { 'x86' }
                visual = $kind -eq 'opengl'
                seconds = if ($kind -eq 'opengl') { 12 } else { 3 }
            }
        }
    }
}

function Test-NormalSmokeResult {
    param($Result, $Test, [string]$RunId)
    if (-not $Result -or $Result.runId -cne $RunId -or $Result.testId -cne $Test.id -or
        $Result.architecture.peArchitecture -cne $Test.peArchitecture -or $Result.status -cne 'PASS') {
        return $false
    }
    if ($Test.visual) {
        return $Result.metrics.frames -gt 0 -and
            $Result.metrics.fallbackDetected -ceq $false -and
            $Result.metrics.width -gt 0 -and $Result.metrics.height -gt 0
    }
    return $Result.metrics.hostConsumptionVerified -ceq $true -and
        $Result.metrics.framesSubmitted -gt 0 -and $Result.metrics.rms -gt 0
}

# Called from Invoke-WineHuaAutomation after its pinned-artifact/device checks.
function Invoke-NormalSmokeRun {
    param([string]$RunSuite, [string]$RunId, [string]$RootDirectory)
    $runDirectory = Join-Path $RootDirectory $RunId
    New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
    $records = @()
    foreach ($test in @(Get-NormalSmokeTests $RunSuite)) {
        $testDirectory = Join-Path $runDirectory $test.id
        New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
        $result = $null
        $visual = $false
        $failure = ''
        $testAppPid = ''
        $warnings = @()
        try {
            Stop-AutomationApp
            $remoteResult = "$DeviceSandbox/files/.wine/drive_c/smoke/results/$RunId/$($test.id).json"
            $gameResult = "C:/smoke/results/$RunId/$($test.id).json"
            $arguments = @('--automation', '--run-id', $RunId, '--test-id', $test.id,
                '--seconds', [string]$test.seconds, '--result', $gameResult)
            $launch = @{ D3DBackend = 'wined3d'; GamePath = $test.executable
                GameArguments = $arguments; DeviceId = $script:DeviceId; HdcPath = $Hdc
                BatchMappedFlushMode = 'product'; GraphicsExperiment = $GraphicsExperiment }
            if ($batchMappedFlushOverrideRequested) { $launch.BatchMappedFlushMode = 'on' }
            & (Join-Path $PSScriptRoot 'Start-WineHuaGameTest.ps1') @launch 6>&1 |
                Set-Content -LiteralPath (Join-Path $testDirectory 'start.log') -Encoding UTF8
            $testAppPid = ((Invoke-Hdc shell pidof $Bundle) -join '').Trim()
            if ($testAppPid -notmatch '^\d+$') { throw 'Cannot identify this test application process' }
            $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
            while ((Get-Date) -lt $deadline) {
                $resultText = Get-DeviceText $remoteResult
                if ($resultText) {
                    $result = $resultText | ConvertFrom-Json
                    if ($result.runId -cne $RunId -or $result.testId -cne $test.id) {
                        throw 'Result identity mismatch; refusing stale evidence'
                    }
                    if ($test.visual -and $result.message -ceq 'fixed-frame' -and -not $visual) {
                        $remoteImage = "/data/local/tmp/$RunId-$($test.id).jpeg"
                        $localImage = Join-Path $testDirectory 'fixed-frame.jpeg'
                        Invoke-Hdc shell snapshot_display -f $remoteImage | Out-Null
                        Invoke-Hdc file recv $remoteImage $localImage | Out-Null
                        if (-not (Test-Path -LiteralPath $localImage)) { throw 'Screenshot transfer produced no file' }
                        $visual = Test-FixedFrame $localImage (Join-Path $testDirectory 'visual.json')
                    }
                    if ($result.status -cin @('PASS', 'FAIL')) { break }
                }
                Start-Sleep -Milliseconds 200
            }
            if (-not $result -or $result.status -cnotin @('PASS', 'FAIL')) {
                throw 'Normal-launch probe timed out without a final result'
            }
        } catch {
            $failure = $_.Exception.Message
        }
        if ($result) {
            $result | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $testDirectory 'result.json') -Encoding UTF8
        }
        # Retain only this app's diagnostics, never serialized launch environments.
        try {
            $logs = @(Invoke-Hdc shell hilog -x | Where-Object {
                $_ -match "^\S+\s+\S+\s+$testAppPid\s+" -and
                $_ -match 'com\.vintage\.pomelopro/' -and $_ -notmatch '__env|entryParams='
            })
            $logs | Set-Content -LiteralPath (Join-Path $testDirectory 'hilog.log') -Encoding UTF8
            $warnings = @($logs | Where-Object {
                $_ -match 'blit dropped|failed_swaps=[1-9]|Fatal signal|SIGSEGV|SIGABRT'
            })
        } catch { $failure += ' Log collection failed.' }
        $passed = -not $failure -and $warnings.Count -eq 0 -and
            (Test-NormalSmokeResult $result $test $RunId) -and
            (-not $test.visual -or $visual)
        $record = [ordered]@{ testId = $test.id; status = if ($passed) { 'PASS' } else { 'FAIL' }
            visualStatus = if (-not $test.visual) { 'NOT_APPLICABLE' } elseif ($visual) { 'PASS' } else { 'FAIL' }
            failure = $failure; diagnosticWarnings = $warnings }
        $records += $record
        Write-Host "$($test.id): $($record.status)"
    }
    $passed = @($records | Where-Object { $_.status -ne 'PASS' }).Count -eq 0
    [ordered]@{ schemaVersion = 1; runId = $RunId; suite = $RunSuite; prefix = 'reuse'
        launcher = 'game'; environment = 'normal-product'; graphicsExperiment = $GraphicsExperiment
        batchMappedFlushPolicy = if ($batchMappedFlushOverrideRequested) { 'explicit-on' } else { 'product-default-on' }
        tests = $records
        status = if ($passed) { 'PASS' } else { 'FAIL' }
        limits = 'Short functional probes only; audio audibility, lifecycle and sustained stability are separate gates.'
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $runDirectory 'host-summary.json') -Encoding UTF8
    return $passed
}
