[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Executable,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '../.hvigor/outputs/guest-inspector-tests')
)
$ErrorActionPreference = 'Stop'
# ProcessStartInfo needs a native path, not PowerShell's FileSystem:: UNC prefix.
$exe = (Resolve-Path -LiteralPath $Executable).ProviderPath
$name = Split-Path -Leaf $exe
function Invoke-Inspect([string[]]$Arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $exe
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    try {
        if (!$process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Self-test helper exceeded 10 seconds'
        }
        return $process.ExitCode
    } finally { $process.Dispose() }
}
$run = Join-Path $OutputRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$run = (Resolve-Path -LiteralPath $run).ProviderPath
$self = Join-Path $run 'self.jsonl'
$code = Invoke-Inspect @('--process', $name, '--duration-ms', '200', '--output', $self)
if ($code -ne 0) { throw "Self inspection failed: $code" }
$rows = @(Get-Content -LiteralPath $self | ForEach-Object { $_ | ConvertFrom-Json })
if ($rows[0].type -ne 'capture' -or $rows[0].readerBits -ne 64 -or
    $rows[-1].type -ne 'complete' -or $rows[-1].status -ne 0) { throw 'Invalid capture envelope' }
if (@($rows | Where-Object type -eq 'process').Count -ne 1) { throw 'Process scope failure' }
if (@($rows | Where-Object { $_.type -eq 'module' -and $_.name -ieq 'ntdll.dll' }).Count -ne 1) {
    throw 'Module enumeration failed'
}
$threads = @($rows | Where-Object type -eq 'thread')
if (!$threads.Count -or @($threads | Where-Object { $_.cpuValid -and ($_.cpuPercent -lt 0 -or $_.cpuPercent -gt 110) }).Count) {
    throw 'Invalid CPU interval'
}
$summary = @($rows | Where-Object type -eq 'thread_summary')
if ($summary.Count -ne 1 -or $summary[0].startAddressIsHotspot -ne $false) { throw 'Start address attribution guard missing' }
$before = (Get-FileHash -LiteralPath $self -Algorithm SHA256).Hash
$code = Invoke-Inspect @('--list', '--output', $self)
if ($code -ne 3 -or (Get-FileHash -LiteralPath $self -Algorithm SHA256).Hash -ne $before) {
    throw 'Existing evidence was not protected'
}
$missing = Join-Path $run 'missing.jsonl'
$code = Invoke-Inspect @('--process', ('missing-' + [guid]::NewGuid().ToString('N') + '.exe'), '--output', $missing)
if ($code -ne 1) { throw 'Missing process not rejected' }
$rows = @(Get-Content -LiteralPath $missing | ForEach-Object { $_ | ConvertFrom-Json })
if (@($rows | Where-Object { $_.type -eq 'error' -and $_.operation -eq 'unique_process_required' }).Count -ne 1) {
    throw 'Missing process evidence absent'
}
foreach ($duration in @('0', '99', '5001', '-1', 'abc', '200x')) {
    $code = Invoke-Inspect @('--process', $name, '--duration-ms', $duration, '--output', (Join-Path $run 'invalid.jsonl'))
    if ($code -ne 2) { throw "Invalid duration accepted: $duration" }
}
if (Test-Path -LiteralPath (Join-Path $run 'invalid.jsonl')) { throw 'Invalid invocation created output' }
Write-Output 'PASS: guest inspector scope, JSONL, modules, CPU bounds, attribution, duration and overwrite guards'
