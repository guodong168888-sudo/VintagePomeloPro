# Read-only analysis of `hiperf dump -d`. Address-shaped data is NOT proof of
# correct unwinding or Guest/JIT symbol attribution. Keep those review gates.
function ConvertFrom-HiperfSampleDump {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$TargetPid,
        [Parameter(Mandatory)][ValidateRange(1, 10000000)][int]$ExpectedSamples
    )
    function Get-UserAddress([string]$Hex) {
        if (-not $Hex) { return $null }
        $value = [Convert]::ToUInt64(($Hex -replace '^0x', ''), 16)
        # This tool targets the current ARM64 user-only capture. Exclude null,
        # kernel/context markers and the observed ffffff0000000fff placeholder.
        if ($value -eq 0 -or $value -ge 0x0001000000000000) { return $null }
        return ('0x{0:x}' -f $value)
    }
    $records = [regex]::Matches($Text, '(?ms)^record sample:[^\r\n]*\r?\n.*?(?=^record |\z)')
    if ($records.Count -ne $ExpectedSamples) {
        throw "Sample count mismatch: dump=$($records.Count), record=$ExpectedSamples"
    }
    $leaves = @{}
    $threads = @{}
    $placeholder = 0
    $rawUserIps = 0
    $chainCandidates = 0
    $missingCandidates = 0
    $unwindSamples = 0
    $expandedSamples = 0
    $namedLeaves = 0
    $entryLeaves = 0
    [decimal]$totalPeriod = 0
    foreach ($record in $records) {
        $body = $record.Value
        $identity = [regex]::Match($body, '(?m)^  pid (\d+), tid (\d+)\r?$')
        $periodMatch = [regex]::Match($body, '(?m)^  period (\d+)\r?$')
        $ipMatch = [regex]::Match($body, '(?m)^  ip ([a-fA-F0-9]+)\r?$')
        $chain = [regex]::Match($body, '(?m)^  callchain nr=(\d+)\r?\n((?:    0x[a-fA-F0-9]+[^\r\n]*\r?\n)*)')
        if (-not $identity.Success -or [int]$identity.Groups[1].Value -ne $TargetPid) {
            throw 'Missing or mixed process identity; select the actual game process'
        }
        if (-not $ipMatch.Success -or -not $periodMatch.Success -or -not $chain.Success) {
            throw 'Incomplete sample: IP, period and callchain are required'
        }
        $addresses = [regex]::Matches($chain.Groups[2].Value, '(?m)^    (0x[a-fA-F0-9]+)([^\r\n]*)')
        if ($addresses.Count -ne [int]$chain.Groups[1].Value) { throw 'Truncated raw callchain' }
        if ($chain.Value.Contains('<unwind callstack>')) { $unwindSamples++ }
        if ($chain.Value.Contains('<expand callstack>')) { $expandedSamples++ }
        $rawIp = $ipMatch.Groups[1].Value
        if ($rawIp -eq 'ffffff0000000fff') { $placeholder++ }
        $candidate = Get-UserAddress $rawIp
        if ($candidate) {
            $rawUserIps++
        } else {
            foreach ($address in $addresses) {
                # Do not recover a leaf from a cached/expanded stack fragment.
                if ($address.Groups[2].Value.Contains('<expand callstack>')) { break }
                $candidate = Get-UserAddress $address.Groups[1].Value
                if ($candidate) { break }
            }
            if ($candidate) { $chainCandidates++ }
        }
        if (-not $candidate) { $missingCandidates++; $candidate = 'unavailable' }
        $leafSymbol = ''
        foreach ($symbol in [regex]::Matches($body, '(?m)^  \d+:(0x[a-fA-F0-9]+) : (.+)\r?$')) {
            if ((Get-UserAddress $symbol.Groups[1].Value) -eq $candidate) {
                $leafSymbol = $symbol.Groups[2].Value.Trim()
                break
            }
        }
        $named = $leafSymbol -and $leafSymbol -notmatch '@0x[0-9a-fA-F]+'
        if ($named) { $namedLeaves++ }
        if ($leafSymbol -match '^(pthread_routine|my___libc_start_main)(@|\+|$)') { $entryLeaves++ }
        [decimal]$period = $periodMatch.Groups[1].Value
        $totalPeriod += $period
        $tid = $identity.Groups[2].Value
        if (-not $threads.ContainsKey($tid)) {
            $threads[$tid] = [ordered]@{ tid = [int]$tid; samples = 0; period = [decimal]0 }
        }
        $threads[$tid].samples++
        $threads[$tid].period += $period
        $key = "$tid/$candidate"
        if (-not $leaves.ContainsKey($key)) {
            $leaves[$key] = [ordered]@{
                tid = [int]$tid; address = $candidate; symbol = $leafSymbol
                samples = 0; period = [decimal]0
            }
        }
        $leaves[$key].samples++
        $leaves[$key].period += $period
    }
    if ($totalPeriod -le 0) { throw 'No positive sampled event period' }
    $warnings = [Collections.Generic.List[string]]::new()
    if ($placeholder) { $warnings.Add('Raw IP placeholders present: inspect unwind candidates, not raw IP alone.') }
    if ($chainCandidates) { $warnings.Add('Recovered addresses are callchain candidates, not verified Guest/JIT functions.') }
    if ($expandedSamples) { $warnings.Add('Expanded-stack markers present; check the recorded mode and inspect them even if expansion was disabled.') }
    if ($missingCandidates) { $warnings.Add('Some samples contain no user address candidate.') }
    if ($namedLeaves -lt $records.Count) { $warnings.Add('Unresolved leaf symbols: do not attribute them to the module/process label.') }
    if ($entryLeaves) { $warnings.Add('Thread-entry leaf detected: rule out truncated unwinding before calling it a hotspot.') }
    return [pscustomobject]@{
        status = 'ATTRIBUTION_REVIEW_REQUIRED'
        samples = $records.Count; eventPeriod = $totalPeriod
        rawPlaceholderSamples = $placeholder; rawUserAddressSamples = $rawUserIps
        callchainCandidateSamples = $chainCandidates; missingCandidateSamples = $missingCandidates
        unwindMarkedSamples = $unwindSamples; expandedStackSamples = $expandedSamples
        namedLeafSamples = $namedLeaves; threadEntryLeafSamples = $entryLeaves
        warnings = $warnings.ToArray()
        # Hardware cycles must be period-weighted; raw sample counts differ
        # significantly between threads/cores and must not be called CPU share.
        threads = @($threads.Values | ForEach-Object {
            [pscustomobject]@{ tid = $_.tid; samples = $_.samples; periodPercent = [double]($_.period * 100 / $totalPeriod) }
        } | Sort-Object periodPercent -Descending)
        topCandidates = @($leaves.Values | Sort-Object { $_.period } -Descending | Select-Object -First 12 | ForEach-Object {
            [pscustomobject]@{
                tid = $_.tid; address = $_.address; symbol = $_.symbol; samples = $_.samples
                periodPercent = [double]($_.period * 100 / $totalPeriod)
            }
        })
    }
}
