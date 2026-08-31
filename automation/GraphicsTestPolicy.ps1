# Test-side invariants only. Product route resolution remains in Native code.
function Assert-GraphicsTestMappedFlush {
    param([string]$Mode = 'product', [hashtable]$Environment = @{})
    if ($Mode -notin @('product', 'on')) {
        throw 'Graphics tests must keep batchMappedFlush enabled (product or on)'
    }
    foreach ($key in $Environment.Keys) {
        if ([string]$key -ieq 'DXVK_WINEHUA_BATCH_MAPPED_FLUSH' -and
            [string]$Environment[$key] -cne '1') {
            throw 'Graphics tests cannot override DXVK_WINEHUA_BATCH_MAPPED_FLUSH to a disabled value'
        }
    }
}

function Get-DxvkProductTestConditions {
    param([ValidateSet('product', 'legacy', 'modern')][string]$ConditionSet = 'product')
    if ($ConditionSet -ne 'modern') {
        [pscustomobject]@{ id='legacy-1.10-product'; backend='dxvk_legacy'; batchMappedFlushMode='product' }
    }
    if ($ConditionSet -ne 'legacy') {
        [pscustomobject]@{ id='modern-2.6-product'; backend='dxvk_modern_2_6'; batchMappedFlushMode='product' }
    }
}
