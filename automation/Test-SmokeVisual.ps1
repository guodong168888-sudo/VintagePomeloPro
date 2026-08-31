#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Invoke-WineHuaAutomation.ps1'), [ref]$null, [ref]$null)
$functionAst = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-FixedFrame'
}, $false)
. ([scriptblock]::Create($functionAst.Extent.Text))
Add-Type -AssemblyName System.Drawing
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('winehua-visual-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    foreach ($mode in @('identity', 'rotate90', 'reflection', 'missing', 'desktop-only')) {
        $bitmap = [Drawing.Bitmap]::new(1000, 650)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            # Previously classified as probe blue; it is larger than the probe.
            $graphics.Clear([Drawing.Color]::FromArgb(62, 112, 169))
            if ($mode -ne 'desktop-only') {
                $colors = switch ($mode) {
                    'rotate90' { @('Blue', 'Red', 'Yellow', 'Lime') }
                    'reflection' { @('Lime', 'Red', 'Yellow', 'Blue') }
                    'missing' { @('Red', 'Lime', 'Black', 'Yellow') }
                    default { @('Red', 'Lime', 'Blue', 'Yellow') }
                }
                for ($i=0; $i -lt 4; ++$i) {
                    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromName($colors[$i]))
                    try { $graphics.FillRectangle($brush, 10 + ($i % 2)*240, 30 + [int][Math]::Floor($i/2)*180, 240, 180) }
                    finally { $brush.Dispose() }
                }
            }
            $path = Join-Path $testRoot "$mode.png"
            $bitmap.Save($path)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
        $actual = Test-FixedFrame $path (Join-Path $testRoot "$mode.json")
        if ($actual -ne ($mode -in @('identity', 'rotate90'))) { throw "Visual contract failed: $mode" }
    }
    Write-Host 'Smoke visual PASS (windowed desktop, rotation, reflection, missing colour, no probe)'
} finally {
    $resolved = (Resolve-Path -LiteralPath $testRoot).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^winehua-visual-[0-9a-f]{32}$') { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
