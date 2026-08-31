param([Parameter(Mandatory = $true)][string]$LayoutPath)
$ErrorActionPreference = 'Stop'
$layout = Get-Content -Raw -Encoding utf8 -LiteralPath $LayoutPath | ConvertFrom-Json
function Find-Node($node, [string]$id) {
  if ($node.attributes.id -eq $id) { return $node }
  foreach ($child in $node.children) {
    $found = Find-Node $child $id
    if ($null -ne $found) { return $found }
  }
  return $null
}
function Bounds($node) {
  $values = @([regex]::Matches($node.attributes.bounds, '-?\d+') | ForEach-Object { [double]$_.Value })
  if ($values.Count -ne 4) { throw 'Missing/invalid layout bounds' }
  return $values
}
$container = Find-Node $layout 'library-bottom-bar'
if ($null -eq $container) { throw 'Navigation bar is not visible' }
$bar = @($container.children | Where-Object { $_.attributes.type -eq 'TabBar' })[0]
$barRect = Bounds $bar
$barCenter = ($barRect[1] + $barRect[3]) / 2
for ($index = 0; $index -lt 5; $index++) {
  $id = 'library-nav-tab-' + $index
  $slot = @($bar.children | Where-Object { $null -ne (Find-Node $_ $id) })[0]
  $tab = Find-Node $slot $id
  if ($null -eq $tab) { throw "Missing tab $index" }
  $slotRect = Bounds $slot
  $tabRect = Bounds $tab
  if ($tabRect[1] -lt $slotRect[1] -or $tabRect[3] -gt $slotRect[3]) {
    throw "Tab $index overflows HDS inner slot: $($tab.attributes.bounds) / $($slot.attributes.bounds)"
  }
  $icon = @($tab.children | Where-Object { $_.attributes.type -eq 'SymbolGlyph' })[0]
  $label = @($tab.children | Where-Object { $_.attributes.type -eq 'Text' })[0]
  $iconRect = Bounds $icon
  $labelRect = Bounds $label
  $contentTop = [Math]::Min($iconRect[1], $labelRect[1])
  $contentBottom = [Math]::Max($iconRect[3], $labelRect[3])
  $offset = ($contentTop + $contentBottom) / 2 - $barCenter
  if ([Math]::Abs($offset) -gt 2) { throw "Tab $index vertical center offset is $offset px" }
  if ($contentTop -lt $slotRect[1] -or $contentBottom -gt $slotRect[3]) {
    throw "Tab $index content is clipped"
  }
  $xOffset = ($iconRect[0] + $iconRect[2] - $labelRect[0] - $labelRect[2]) / 2
  if ([Math]::Abs($xOffset) -gt 2) { throw "Tab $index icon/label horizontal centers differ by $xOffset px" }
  Write-Output "Tab $index ($($label.attributes.text)): no overflow, center delta=$offset px"
}
Write-Output 'Bottom navigation device layout: PASS'
