$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GraphicsTestPolicy.ps1')
function Assert-RejectedBeforeDevice {
    param([scriptblock]$Action, [string]$Expected)
    $message = ''
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notmatch $Expected -or $message -match 'Windows HDC not found') {
        throw "Expected policy/parameter rejection before device access, got: $message"
    }
}
Assert-GraphicsTestMappedFlush 'product' @{}
Assert-GraphicsTestMappedFlush 'on' @{DXVK_WINEHUA_BATCH_MAPPED_FLUSH='1'}
foreach ($value in @('0', '', 'false', '2')) {
    Assert-RejectedBeforeDevice {
        Assert-GraphicsTestMappedFlush 'product' @{DXVK_WINEHUA_BATCH_MAPPED_FLUSH=$value}
    } 'cannot override'
}
Assert-RejectedBeforeDevice { Assert-GraphicsTestMappedFlush 'off' @{} } 'keep batchMappedFlush enabled'
foreach ($set in @('product', 'legacy', 'modern')) {
    $conditions = @(Get-DxvkProductTestConditions $set)
    $expectedCount = if ($set -eq 'product') { 2 } else { 1 }
    if ($conditions.Count -ne $expectedCount -or @($conditions | Where-Object {
        $_.batchMappedFlushMode -ne 'product' -or $_.PSObject.Properties['batchMappedFlushOverride']
    }).Count) { throw "Invalid product test matrix: $set" }
    $expectedBackends = if ($set -eq 'product') { 'dxvk_legacy,dxvk_modern_2_6' }
        elseif ($set -eq 'legacy') { 'dxvk_legacy' } else { 'dxvk_modern_2_6' }
    if (($conditions.backend -join ',') -ne $expectedBackends) { throw "Wrong runtime selected: $set" }
}

# All rejected executions use a nonexistent HDC path: reaching its validation
# would fail the test. They cannot launch a device or mutate an app session.
$invalidHdc = Join-Path $PSScriptRoot 'nonexistent-policy-test-hdc.exe'
foreach ($script in @('Start-WineHuaGameTest.ps1', 'Measure-WineHuaFrameOrder.ps1')) {
    Assert-RejectedBeforeDevice {
        & (Join-Path $PSScriptRoot $script) -BatchMappedFlushMode off -HdcPath $invalidHdc
    } 'ValidateSet|does not belong|Cannot validate'
}
foreach ($mode in @('product', 'on')) {
    Assert-RejectedBeforeDevice {
        & (Join-Path $PSScriptRoot 'Start-WineHuaGameTest.ps1') -BatchMappedFlushMode $mode `
            -D3DEnvironment @{DXVK_WINEHUA_BATCH_MAPPED_FLUSH='0'} -HdcPath $invalidHdc
    } 'cannot override'
}
foreach ($retired in @('modern-batch', 'legacy-batch', 'all')) {
    Assert-RejectedBeforeDevice {
        & (Join-Path $PSScriptRoot 'Measure-WineHuaDxvkPerformance.ps1') -ConditionSet $retired -HdcPath $invalidHdc
    } 'ValidateSet|does not belong|Cannot validate'
}
Assert-RejectedBeforeDevice {
    & (Join-Path $PSScriptRoot 'Measure-WineHuaDxvkPerformance.ps1') -IncludeModernBatchMappedFlushOff -HdcPath $invalidHdc
} 'parameter.*IncludeModernBatchMappedFlushOff'
Write-Host 'Graphics test policy PASS (product matrices, mode/env bypass rejection, retired CLI rejected before HDC)'
