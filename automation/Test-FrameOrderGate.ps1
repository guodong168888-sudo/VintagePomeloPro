#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Measure-WineHuaFrameOrder.ps1'), [ref]$null, [ref]$null)
$assignment = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$status'
}, $false)
$evaluate = [scriptblock]::Create($assignment.Extent.Text)
$minimumValid=6
$valid=@(1..8)
$regressions=@()
$trailingInvalid=0
$forwardDeltas=@(1,2)
. $evaluate
if ($status -ne 'PASS') { throw 'Forward sequence rejected' }
$forwardDeltas=@()
. $evaluate
if ($status -ne 'FAIL') { throw 'Frozen sequence passed' }
$forwardDeltas=@(1,2)
$regressions=@('reverse')
. $evaluate
if ($status -ne 'FAIL') { throw 'Reverse sequence passed' }
$regressions=@()
$trailingInvalid=3
. $evaluate
if ($status -ne 'FAIL') { throw 'Lost trailing frames passed' }
$trailingInvalid=0
$valid=@(1,2)
. $evaluate
if ($status -ne 'INCONCLUSIVE') { throw 'Insufficient samples passed' }
$hdcFunction = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Hdc'
}, $false)
. ([scriptblock]::Create($hdcFunction.Extent.Text))
function Invoke-MockFrameHdc { $global:LASTEXITCODE=0; '[Fail] disconnected' }
$hdc='Invoke-MockFrameHdc'
$DeviceId='synthetic'
$rejected=$false
try { Invoke-Hdc -Arguments @('shell', 'ps') } catch { $rejected=$true }
if (-not $rejected) { throw 'Zero-exit HDC failure passed' }
Write-Host 'Frame-order gate PASS (forward, freeze, reverse, missing frames, disconnect)'
