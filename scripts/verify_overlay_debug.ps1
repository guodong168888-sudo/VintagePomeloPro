param(
  [Parameter(Mandatory = $true)]
  [string]$HapPath,
  [string]$Target = '127.0.0.1:5555',
  [string]$BundleName = 'com.vintage.pomelopro',
  [string]$HdcPath = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$artifactDir = Join-Path $repoRoot ".hvigor/outputs/overlay-v2/$runId"
$deviceTmp = '/data/local/tmp/overlay-v2'
$script:uiInputScaleX = 1.0
$script:uiInputScaleY = 1.0

if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) {
  throw "Debug HAP not found: $HapPath"
}
if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) {
  throw "hdc not found: $HdcPath"
}
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$apiLevel = (& $HdcPath -t $Target shell param get const.ohos.apiversion).Trim()
if ($LASTEXITCODE -ne 0 -or $apiLevel -notmatch '^\d+$' -or [int]$apiLevel -lt 23) {
  throw "Overlay verification requires an API 23+ target; detected '$apiLevel'."
}

function Invoke-Hdc([string[]]$Arguments) {
  & $HdcPath -t $Target @Arguments
  if ($LASTEXITCODE -ne 0) { throw "hdc failed: $($Arguments -join ' ')" }
}

function Capture([string]$Name) {
  $remoteLayout = "$deviceTmp/$Name-layout.json"
  $remoteShot = "$deviceTmp/$Name.png"
  $null = Invoke-Hdc @('shell', 'mkdir', '-p', $deviceTmp)
  $null = Invoke-Hdc @('shell', 'uitest', 'dumpLayout', '-p', $remoteLayout)
  $null = Invoke-Hdc @('shell', 'uitest', 'screenCap', '-p', $remoteShot)
  # 部分 API 23 HDC 版本会在 dumpLayout 命令返回后继续刷新目标文件。
  Start-Sleep -Milliseconds 200
  $null = Invoke-Hdc @('file', 'recv', $remoteLayout, (Join-Path $artifactDir "$Name-layout.json"))
  $null = Invoke-Hdc @('file', 'recv', $remoteShot, (Join-Path $artifactDir "$Name.png"))
  Set-UiInputTransform $Name
}

function Read-Layout([string]$Name) {
  $path = Join-Path $artifactDir "$Name-layout.json"
  # uitest 以 UTF-8 写出布局；Windows PowerShell 默认 ANSI 解码会让包含
  # 中文文本的节点 JSON 解析失败，因此必须显式指定 UTF-8。
  return Get-Content -Raw -Encoding utf8 -LiteralPath $path | ConvertFrom-Json
}

function Get-PngSize([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 24 -or $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50) {
    throw "Invalid screenshot PNG: $Path"
  }
  $width = (([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19])
  $height = (([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23])
  return @($width, $height)
}

function Set-UiInputTransform([string]$Name) {
  # dumpLayout 的 bounds 与 uitest uiInput 都使用 ArkUI 逻辑坐标；只有
  # screenCap 是物理像素。此前按截图缩放会点到错误卡片，导致覆盖层测试
  # 偶发在应用库而不是 Wine 桌面执行。
  $script:uiInputScaleX = 1.0
  $script:uiInputScaleY = 1.0
}

function Find-Node($Node, [string]$Id) {
  if ($null -eq $Node) { return $null }
  if ($Node.attributes.id -eq $Id) { return $Node }
  foreach ($child in $Node.children) {
    $found = Find-Node $child $Id
    if ($null -ne $found) { return $found }
  }
  return $null
}

function Find-NodeInLayout($Layout, [string]$Id) {
  if ($null -ne $Layout.attributes) {
    return Find-Node $Layout $Id
  }
  foreach ($root in $Layout) {
    $found = Find-Node $root $Id
    if ($null -ne $found) { return $found }
  }
  return $null
}

function Find-NodeFromRawLayout([string]$RawLayout, [string]$Id) {
  # HDC API 23 的 attributes 是扁平 JSON 对象。此回退只在递归解析没有
  # 返回节点时使用，保持 test ID、bounds、颜色、zIndex 和 hostWindow 的
  # 真实设备值，避免 stdout 流边缘行为干扰自动化。
  $escapedId = [regex]::Escape($Id)
  $pattern = '"attributes":\{(?=[^{}]*"id":"' + $escapedId + '")(?=[^{}]*"bounds":"(?<bounds>[^"]+)")(?=[^{}]*"backgroundColor":"(?<backgroundColor>[^"]*)")(?=[^{}]*"opacity":"(?<opacity>[^"]*)")(?=[^{}]*"zIndex":"(?<zIndex>[^"]*)")(?=[^{}]*"hostWindowId":"(?<hostWindowId>[^"]*)")[^{}]*\}'
  $match = [regex]::Match($RawLayout, $pattern)
  if (-not $match.Success) { return $null }
  return [pscustomobject]@{
    attributes = [pscustomobject]@{
      id = $Id
      bounds = $match.Groups['bounds'].Value
      backgroundColor = $match.Groups['backgroundColor'].Value
      opacity = $match.Groups['opacity'].Value
      zIndex = $match.Groups['zIndex'].Value
      hostWindowId = $match.Groups['hostWindowId'].Value
    }
    children = @()
  }
}

function Wait-ForNode([string]$Id, [int]$TimeoutSeconds = 20) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $null = Invoke-Hdc @('shell', 'uitest', 'dumpLayout', '-p', "$deviceTmp/wait-layout.json")
    Start-Sleep -Milliseconds 150
    $null = Invoke-Hdc @('file', 'recv', "$deviceTmp/wait-layout.json", (Join-Path $artifactDir 'wait-layout.json'))
    if ((Get-Item -LiteralPath (Join-Path $artifactDir 'wait-layout.json')).Length -eq 0) {
      Start-Sleep -Milliseconds 250
      continue
    }
    $layout = Read-Layout 'wait'
    $rawLayout = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $artifactDir 'wait-layout.json')
    # 当前 uitest 的 API 23 输出是单个 ROOT 节点；直接从根递归，避免
    # Windows PowerShell 对 PSCustomObject/单元素数组的参数展开差异。
    $node = Find-Node $layout $Id
    if ($null -eq $node -or $node.attributes.id -ne $Id) {
      $node = Find-NodeFromRawLayout $rawLayout $Id
    }
    if ($null -ne $node -and $node.attributes.id -eq $Id) {
      return $node
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  throw "Timed out waiting for UI node '$Id'. Evidence: $artifactDir"
}

function Get-NodeCenter($Node) {
  if ($Node.attributes.bounds -notmatch '^\[(?<x1>\d+),(?<y1>\d+)\]\[(?<x2>\d+),(?<y2>\d+)\]$') {
    throw "Unsupported bounds: $($Node.attributes.bounds)"
  }
  return @(
    [Math]::Round((([int]$Matches.x1) + ([int]$Matches.x2)) / 2),
    [Math]::Round((([int]$Matches.y1) + ([int]$Matches.y2)) / 2)
  )
}

function Click-ResolvedNode($Node) {
  $center = Get-NodeCenter $Node
  # 该 API 23 模拟器的 uitest uiInput 偶发只注入鼠标事件。uinput 的
  # touch 通道会稳定提供真实 Down/Up，ArkUI 卡片和虚拟按键都能收到。
  Invoke-Hdc @('shell', 'uinput', '-T', '-c', "$($center[0])", "$($center[1])", '60')
}

function Click-Node([string]$Id) {
  Click-ResolvedNode (Wait-ForNode $Id)
}

function Find-NodeByText($Node, [string]$Text) {
  if ($null -eq $Node) { return $null }
  if ($Node.attributes.originalText -eq $Text) { return $Node }
  foreach ($child in $Node.children) {
    $found = Find-NodeByText $child $Text
    if ($null -ne $found) { return $found }
  }
  return $null
}

function Wait-ForText([string]$Text, [int]$TimeoutSeconds = 20) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $null = Invoke-Hdc @('shell', 'uitest', 'dumpLayout', '-p', "$deviceTmp/text-wait-layout.json")
    Start-Sleep -Milliseconds 150
    $null = Invoke-Hdc @('file', 'recv', "$deviceTmp/text-wait-layout.json", (Join-Path $artifactDir 'text-wait-layout.json'))
    $layout = Read-Layout 'text-wait'
    $node = Find-NodeByText $layout $Text
    if ($null -ne $node) { return $node }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  throw "Timed out waiting for text '$Text'. Evidence: $artifactDir"
}

function Drag-Node([string]$Id) {
  $node = Wait-ForNode $Id
  if ($node.attributes.bounds -notmatch '^\[(?<x1>\d+),(?<y1>\d+)\]\[(?<x2>\d+),(?<y2>\d+)\]$') {
    throw "Unsupported bounds: $($node.attributes.bounds)"
  }
  $x1 = [int]$Matches.x1; $y1 = [int]$Matches.y1; $x2 = [int]$Matches.x2; $y2 = [int]$Matches.y2
  Invoke-Hdc @('shell', 'uitest', 'uiInput', 'drag',
    "$([Math]::Round(($x1 + $x2) / 2))",
    "$([Math]::Round(($y1 + $y2) / 2))",
    "$($x2 - 8)",
    "$($y1 + 8)", '600')
}

function Launch-DesktopForVerification() {
  Click-Node 'wine-app-card-builtin-desktop'
  # 首次 prefix 初始化需要约 30 秒。期间应用库仍显示卡片，但再次点击会
  # 干扰同一引擎的准备状态；因此只发送一次真实点击，并等待真实子窗口。
  return Wait-ForNode 'wine-overlay-diagnostics-state' 90
}

function Get-TextTree($Node) {
  $pieces = @()
  if ($null -ne $Node.attributes.originalText -and $Node.attributes.originalText.Length -gt 0) {
    $pieces += $Node.attributes.originalText
  }
  foreach ($child in $Node.children) { $pieces += Get-TextTree $child }
  return $pieces -join ' '
}

function Wait-ForRendererStress([int]$TimeoutSeconds = 120) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $state = Wait-ForNode 'wine-overlay-diagnostics-state' 8
    $text = Get-TextTree $state
    if ($text -match 'rebind (3[0-9]{2}|[4-9][0-9]{2,})' -and $text -notmatch '自检中') {
      return $state
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  throw "Renderer stress did not finish within $TimeoutSeconds seconds."
}

function Get-InjectedEventCount() {
  $events = Wait-ForNode 'wine-overlay-input-events' 12
  $text = Get-TextTree $events
  if ($text -notmatch 'events\s+(?<count>\d+)') {
    throw "Input diagnostics did not expose an event count: $text"
  }
  return [int]$Matches.count
}

function ConfigureSingleAppModeForCmd() {
  Click-Node 'wine-app-settings-builtin-cmd'
  $null = Wait-ForNode 'app-settings-mode-single' 15
  Click-Node 'app-settings-mode-single'
  Click-Node 'app-settings-save'
  $null = Wait-ForNode 'wine-app-card-builtin-cmd' 15
}

function RestoreCmdModeToGlobalDefault() {
  Click-Node 'wine-app-settings-builtin-cmd'
  $null = Wait-ForNode 'app-settings-mode-inherit' 15
  Click-Node 'app-settings-mode-inherit'
  Click-Node 'app-settings-save'
  $null = Wait-ForNode 'wine-app-card-builtin-cmd' 15
}

function Get-VisualState($Node) {
  return [ordered]@{
    id = $Node.attributes.id
    bounds = $Node.attributes.bounds
    backgroundColor = $Node.attributes.backgroundColor
    opacity = $Node.attributes.opacity
    zIndex = $Node.attributes.zIndex
    hostWindowId = $Node.attributes.hostWindowId
  }
}

function Assert-VisualStable($Before, $After, [string]$Name) {
  if ($Before.bounds -ne $After.bounds -or $Before.backgroundColor -ne $After.backgroundColor -or
      $Before.hostWindowId -ne $After.hostWindowId) {
    throw "$Name visual node changed across renderer rebind. before=$($Before | ConvertTo-Json -Compress) after=$($After | ConvertTo-Json -Compress)"
  }
}

try {
  # 压力回归可持续一分钟以上。仅在本次验证期间覆盖休眠时长，避免锁屏
  # 让 ArkTS 窗口树消失；finally 中会立即恢复设备原先的超时策略。
  Invoke-Hdc @('shell', 'power-shell', 'wakeup')
  Invoke-Hdc @('shell', 'power-shell', 'timeout', '-o', '600000')
  Invoke-Hdc @('shell', 'mkdir', '-p', $deviceTmp)
  Invoke-Hdc @('file', 'send', $HapPath, "$deviceTmp/overlay-v2-debug.hap")
  Invoke-Hdc @('shell', 'bm', 'install', '-r', '-d', '-p', "$deviceTmp/overlay-v2-debug.hap")
  Invoke-Hdc @('shell', 'aa', 'force-stop', $BundleName)
  # API 23 模拟器在开发者模式下不允许 aa 自动解锁。先用标准解锁手势
  # 唤醒/离开锁屏，再由 aa 启动应用；这不修改任何设备设置。
  Invoke-Hdc @('shell', 'uitest', 'uiInput', 'swipe', '1440', '1700', '1440', '700', '500')
  Start-Sleep -Milliseconds 400
  Invoke-Hdc @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $BundleName)
  Start-Sleep -Seconds 2
  Capture 'library-start'
  Start-Sleep -Seconds 1

  # Stable IDs mean the test stays valid when dpi, orientation, or visual spacing changes.
  $overlayState = Launch-DesktopForVerification
  $touchpadOpen = Wait-ForNode 'wine-input-control-touchpad' 15
  $aButtonOpen = Wait-ForNode 'wine-input-control-a' 15
  Capture 'overlay-open'
  # 使用刚刚经由真实设备等待到的节点。API 23 的 dumpLayout 在截图完成后
  # 偶尔会返回跨窗口的过渡根节点；重新解析它会把已可见的控件误判为空。
  if ($null -eq $touchpadOpen -or $null -eq $aButtonOpen) {
    throw "Input controls are absent before renderer stress."
  }
  $touchpadBefore = Get-VisualState $touchpadOpen
  $aButtonBefore = Get-VisualState $aButtonOpen
  if ([string]::IsNullOrWhiteSpace($touchpadBefore.backgroundColor) -or [string]::IsNullOrWhiteSpace($aButtonBefore.backgroundColor)) {
    throw "Input controls do not expose visual state in the layout tree."
  }

  $eventsBefore = Get-InjectedEventCount
  Click-Node 'wine-input-control-a'
  Drag-Node 'wine-input-control-touchpad'
  Start-Sleep -Milliseconds 350
  $eventsAfter = Get-InjectedEventCount
  if ($eventsAfter -le $eventsBefore) {
    throw "Virtual controls did not reach InputDispatcher. before=$eventsBefore after=$eventsAfter"
  }
  Click-Node 'wine-overlay-diagnostics-run'
  $stressState = Wait-ForRendererStress 120
  Capture 'stress-finished'

  $layout = Read-Layout 'stress-finished'
  $state = Find-NodeInLayout $layout 'wine-overlay-diagnostics-state'
  $touchpad = Find-NodeInLayout $layout 'wine-input-control-touchpad'
  $aButton = Find-NodeInLayout $layout 'wine-input-control-a'
  if ($null -eq $state -or $null -eq $touchpad -or $null -eq $aButton) {
    throw "Overlay diagnostics or input controls are absent after renderer stress. Evidence: $artifactDir"
  }
  Assert-VisualStable $touchpadBefore (Get-VisualState $touchpad) 'touchpad'
  Assert-VisualStable $aButtonBefore (Get-VisualState $aButton) 'A button'
  $diagnosticText = Get-TextTree $stressState
  if ($diagnosticText -notmatch 'Overlay 1/z9000') {
    throw "Expected exactly one zLevel-9000 overlay, got: $diagnosticText"
  }
  if ($diagnosticText -notmatch 'rebind (3[0-9]{2}|[4-9][0-9]{2,})') {
    throw "Renderer stress did not complete 300 rebinds: $diagnosticText"
  }
  if ($diagnosticText -notmatch 'keys 0 .* buttons 0 .* pointers 0') {
    throw "Input cancellation left pressed state behind: $diagnosticText"
  }

  Click-Node 'wine-input-overlay-hide'
  Start-Sleep -Milliseconds 500
  Capture 'overlay-hidden'
  $hidden = Find-NodeInLayout (Read-Layout 'overlay-hidden') 'wine-virtual-input-overlay'
  if ($null -ne $hidden) { throw "Overlay controls are still touch-visible after hide action." }

  # 按真实用户路径先回应用库，再点“Wine 桌面”。它会重新激活同一 desktop
  # session，而不是销毁 Wine 或创建第二个 ArkTS 输入子窗口。
  Invoke-Hdc @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $BundleName)
  $libraryCard = Wait-ForNode 'wine-app-card-builtin-desktop' 15
  $overlayState = Launch-DesktopForVerification
  Capture 'overlay-restored'
  $restoredText = Get-TextTree (Find-NodeInLayout (Read-Layout 'overlay-restored') 'wine-overlay-diagnostics-state')
  if ($restoredText -notmatch 'Overlay 1/z9000') {
    throw "Overlay was recreated or lost zLevel after hide/restore: $restoredText"
  }

  # 单应用覆盖层必须同样是独立 ArkTS 子窗口。先从桌面会话回到应用库，
  # 为命令提示符写入单应用覆盖；随后走用户可见的模式冲突确认路径。
  Invoke-Hdc @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $BundleName)
  $null = Wait-ForNode 'wine-app-settings-builtin-cmd' 15
  ConfigureSingleAppModeForCmd
  Click-Node 'wine-app-card-builtin-cmd'
  Click-ResolvedNode (Wait-ForText '关闭并切换' 15)
  $null = Wait-ForNode 'wine_single_app_xc' 90
  $singleOverlay = Wait-ForNode 'wine-overlay-diagnostics-state' 20
  Capture 'single-app-open'
  $singleText = Get-TextTree $singleOverlay
  if ($singleText -notmatch 'Overlay 1/z9000') {
    throw "Single-app session did not preserve exactly one zLevel-9000 overlay: $singleText"
  }

  # 测试不得把用户默认显示方式留在单应用模式。回应用库后恢复为全局默认。
  Invoke-Hdc @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $BundleName)
  $null = Wait-ForNode 'wine-app-settings-builtin-cmd' 15
  RestoreCmdModeToGlobalDefault

  @{ target = $Target; apiLevel = $apiLevel; bundle = $BundleName; status = 'passed'; artifacts = $artifactDir; diagnostics = $restoredText; singleAppDiagnostics = $singleText; visual = @{ touchpad = $touchpadBefore; aButton = $aButtonBefore } } |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $artifactDir 'summary.json')
  Write-Host "Overlay verification passed. Evidence: $artifactDir"
} catch {
  @{ target = $Target; apiLevel = $apiLevel; bundle = $BundleName; status = 'failed'; artifacts = $artifactDir; error = $_.Exception.Message } |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $artifactDir 'summary.json')
  throw
} finally {
  try { Invoke-Hdc @('shell', 'power-shell', 'timeout', '-r') } catch {}
}
