#Requires -Version 5.1
<#
.SYNOPSIS
    GHOST TRACK // APSIS · V17 unified headless regression runner.

.DESCRIPTION
    Runs the tracked Godot 4.7.2 headless test matrix (game_v17/tests/probe_matrix.json)
    as sequential one-process-per-case runs and writes a machine-readable summary.json
    plus a human report.md under .test-results/<run-id>/.

    Works on Windows PowerShell 5.1 and PowerShell 7+ (CI uses pwsh). Cross-platform
    for Linux/macOS pwsh when -GodotBin / $env:GODOT_BIN points at a Godot binary.

    Result policy:
      PASS      exit code 0 AND (probe fail count 0) AND all expected markers present
      FAIL      nonzero exit, probe fail count > 0, missing result line, missing marker,
                or SCRIPT ERROR / parse error in a boot case
      TIMEOUT   per-case process timeout (killed; counted as failure)
      NOT RUN   declared blocked case (declared in matrix) or missing script/scene/import

    Baseline-aware mode (-Baseline <file>, schema known_baseline_failures.v1):
    every case keeps its original status (a FAIL stays FAIL; nothing is renamed PASS,
    hidden, skipped or continue-on-error). On top of that each FAIL is classified as
    known+expected (counts/exit match the declared baseline), baseline drift (declared
    failure whose counts changed, or a declared failure that now passes), or new failure
    (not declared). The console/report print `BASELINE CHECK: known_fail=N new_fail=N
    drift=N`; summary.json gains a `baseline` block and totals known_fail/new_fail/
    baseline_drift. Exit is 0 only when new_fail==0 AND baseline_drift==0 AND timeout==0
    AND unexpected NOT RUN==0; otherwise 1. Without -Baseline behaviour is unchanged:
    any FAIL/TIMEOUT/unexpected NOT RUN -> exit 1.

    Exit codes: 0 all run cases passed (baseline mode: only declared known failures);
                1 any FAIL/TIMEOUT/unexpected NOT RUN (baseline mode: any new failure or
                baseline drift); 2 environment/setup blocked (no Godot, import preflight
                failed, unknown gate, missing/invalid baseline file, bad args).

.PARAMETER GodotBin
    Explicit Godot executable path. Discovery order when omitted:
    $env:GODOT_BIN -> tools/godot/Godot*console.exe -> godot / godot4 on PATH.

.PARAMETER Category
    Comma-separated category filter, e.g. profile, unit, content, integration, e2e, boot.

.PARAMETER Only
    Regular-expression filter matched against case id and target (script/scene path).

.PARAMETER Gate
    Run only the case ids declared in probe_matrix.json gates.<name> (e.g. phase0 =
    profile.build_profile_probe, e2e.orbital_sim and the four boot smoke cases).
    Composable with -Category / -Only. Unknown or empty gate -> exit 2 with the list
    of available gates.

.PARAMETER List
    Print the resolved matrix (after filters) and exit 0 without requiring Godot.

.PARAMETER NoImport
    Skip the `--import` preflight (not recommended on a fresh worktree).

.PARAMETER TimeoutSec
    Override the per-case timeout for every selected case (matrix default is used otherwise).

.PARAMETER Ci
    Non-interactive mode: no ANSI colors.

.PARAMETER Matrix
    Matrix manifest path (default game_v17/tests/probe_matrix.json).

.PARAMETER ResultsDir
    Results root directory (default .test-results). A unique run dir is created inside.

.PARAMETER Baseline
    Baseline-aware mode. Path to a known_baseline_failures.v1 file (default candidate:
    game_v17/tests/known_baseline_failures.json). Case statuses are never changed:
    declared legacy failures stay FAIL (they are only classified and tagged
    KNOWN-BASELINE); any new failure or baseline drift turns the run red. See
    .DESCRIPTION for the exact classification and exit-code semantics.

.EXAMPLE
    pwsh ./run_tests.ps1 -List

.EXAMPLE
    pwsh ./run_tests.ps1 -Category profile

.EXAMPLE
    pwsh ./run_tests.ps1 -Ci

.EXAMPLE
    $env:GODOT_BIN = 'C:\tools\Godot_v4.7.2-stable_win64_console.exe'; pwsh ./run_tests.ps1 -Category boot

.EXAMPLE
    pwsh ./run_tests.ps1 -Gate phase0 -Ci

.EXAMPLE
    pwsh ./run_tests.ps1 -Baseline game_v17/tests/known_baseline_failures.json -Ci
#>
[CmdletBinding()]
param(
    [string]$GodotBin = '',
    [string]$Category = '',
    [string]$Only = '',
    [switch]$List,
    [switch]$NoImport,
    [int]$TimeoutSec = 0,
    [switch]$Ci,
    [string]$Matrix = '',
    [string]$ResultsDir = '',
    [string]$Gate = '',
    [string]$Baseline = ''
)

$ErrorActionPreference = 'Stop'

# Deterministic number formatting regardless of host locale (helpful in CI logs).
try { [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture } catch { }
try { [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture } catch { }

# ── script state ────────────────────────────────────────────────────────────
$script:RepoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:RepoRoot)) { $script:RepoRoot = (Get-Location).Path }
$script:ProjectRel = 'game_v17'
$script:ProjectDir = Join-Path $script:RepoRoot $script:ProjectRel
$script:CiMode = [bool]$Ci
$script:TimeoutOverride = [int]$TimeoutSec
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:TransientRegex = 'file is locked|Access is denied|Failed to open file|Cannot open file|Could not open file|Unable to open file|Text file busy|another instance of Godot'
$script:FatalBootRegex = 'SCRIPT ERROR|(?m)^ERROR: Parse Error|(?m)^Parse Error:'
$script:CaseResults = New-Object System.Collections.ArrayList
$script:ClearedEnv = @{}
$script:MatrixData = $null
$script:Godot = $null
$script:RunId = ''
$script:RunDir = ''
$script:GateProvided = $PSBoundParameters.ContainsKey('Gate')
$script:BaselineProvided = $PSBoundParameters.ContainsKey('Baseline')
$script:BaselineData = $null

# ── console helpers ────────────────────────────────────────────────────────
function Write-Info([string]$Text) { Write-Host $Text }
function Write-Head([string]$Text) {
    if ($script:CiMode) { Write-Host $Text } else { Write-Host $Text -ForegroundColor Cyan }
}
function Write-Ok([string]$Text) {
    if ($script:CiMode) { Write-Host $Text } else { Write-Host $Text -ForegroundColor Green }
}
function Write-Warn([string]$Text) {
    if ($script:CiMode) { Write-Host $Text } else { Write-Host $Text -ForegroundColor Yellow }
}
function Write-Err([string]$Text) {
    if ($script:CiMode) { Write-Host $Text } else { Write-Host $Text -ForegroundColor Red }
}

# ── path helpers ───────────────────────────────────────────────────────────
function Resolve-RepoPath([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $script:RepoRoot $PathValue)
}

function Format-RepoRelative([string]$FullPath) {
    if ([string]::IsNullOrEmpty($FullPath)) { return '' }
    try {
        $full = [System.IO.Path]::GetFullPath($FullPath)
        $root = [System.IO.Path]::GetFullPath($script:RepoRoot).TrimEnd('\', '/')
        if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($root.Length).TrimStart('\', '/')
            if ($rel -eq '') { return '.' }
            return ($rel -replace '\\', '/')
        }
        return ($full -replace '\\', '/')
    } catch { return ($FullPath -replace '\\', '/') }
}

function Format-DisplayPath([string]$FullPath) {
    if ([string]::IsNullOrEmpty($FullPath)) { return '' }
    $rel = Format-RepoRelative $FullPath
    if ($rel -eq '') { return $FullPath }
    return $rel
}

function ConvertFrom-ResPath([string]$ResPath) {
    if ([string]::IsNullOrWhiteSpace($ResPath)) { return '' }
    if ($ResPath.StartsWith('res://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $ResPath.Substring(6)
        return (Join-Path $script:ProjectDir $rel)
    }
    return (Resolve-RepoPath $ResPath)
}

function ConvertTo-ArgumentString {
    param([string[]]$ArgumentList)
    $parts = @()
    foreach ($a in $ArgumentList) {
        $s = [string]$a
        if ($s -eq '') { $parts += '""' }
        elseif ($s -match '[\s"]') { $parts += '"' + ($s -replace '"', '\"') + '"' }
        else { $parts += $s }
    }
    return ($parts -join ' ')
}

# ── process capture (PS 5.1 + PS 7) ────────────────────────────────────────
function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = '',
        [int]$TimeoutSec = 240,
        [hashtable]$Environment = @{},
        [string]$LogPath = ''
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (ConvertTo-ArgumentString -ArgumentList $ArgumentList)
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # Godot prints UTF-8; decode explicitly so Chinese log text survives PS 5.1.
    try { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8 } catch { }
    foreach ($k in @($Environment.Keys)) {
        try { $psi.EnvironmentVariables[[string]$k] = [string]$Environment[$k] } catch { }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $timedOut = $true
        try { $p.Kill() } catch { }
        try { [void]$p.WaitForExit(5000) } catch { }
    }
    $sw.Stop()
    $stdout = ''
    $stderr = ''
    try { if ($outTask.Wait(10000)) { $stdout = $outTask.Result } } catch { }
    try { if ($errTask.Wait(10000)) { $stderr = $errTask.Result } } catch { }
    $exitCode = $null
    if (-not $timedOut) {
        try { $exitCode = $p.ExitCode } catch { $exitCode = $null }
    }
    $p.Dispose()
    if ($LogPath) {
        $merged = $stdout
        if ($stderr -and $stderr.Trim().Length -gt 0) { $merged += "`n--- STDERR ---`n" + $stderr }
        [System.IO.File]::WriteAllText($LogPath, $merged, $script:Utf8)
        if ($stderr -and $stderr.Trim().Length -gt 0) {
            $errPath = $LogPath -replace '\.log$', '.stderr.log'
            [System.IO.File]::WriteAllText($errPath, $stderr, $script:Utf8)
        }
    }
    return [pscustomobject]@{
        stdout     = $stdout
        stderr     = $stderr
        output     = ($stdout + "`n" + $stderr)
        exit_code  = $exitCode
        timed_out  = $timedOut
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}

# ── environment isolation ──────────────────────────────────────────────────
function Get-TestEnvPrefixes {
    $prefixes = @('DSH_', 'V17_')
    if ($script:MatrixData -and $script:MatrixData.env_policy) {
        $declared = @($script:MatrixData.env_policy.clear_prefixes)
        if ($declared.Count -gt 0) { $prefixes = $declared }
    }
    return $prefixes
}

function Clear-InheritedTestEnv {
    $script:ClearedEnv = @{}
    $prefixes = Get-TestEnvPrefixes
    $names = @(Get-ChildItem Env: | Where-Object {
            $name = $_.Name
            $matched = $false
            foreach ($p in $prefixes) { if ($name.StartsWith($p, [System.StringComparison]::Ordinal)) { $matched = $true; break } }
            $matched
        } | ForEach-Object { $_.Name })
    foreach ($n in $names) {
        try { $script:ClearedEnv[$n] = (Get-Item "Env:$n").Value } catch { $script:ClearedEnv[$n] = '' }
        Remove-Item "Env:$n" -ErrorAction SilentlyContinue
    }
    return $names
}

function Restore-InheritedTestEnv {
    foreach ($n in @($script:ClearedEnv.Keys)) {
        try { Set-Item "Env:$n" $script:ClearedEnv[$n] } catch { }
    }
}

# ── matrix loading / filtering ─────────────────────────────────────────────
function Load-Matrix([string]$PathValue) {
    $resolved = Resolve-RepoPath $PathValue
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "matrix manifest not found: $resolved"
    }
    $raw = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
    $m = $raw | ConvertFrom-Json
    if ($null -eq $m -or [string]$m.schema -ne 'probe_matrix.v1') {
        throw "unsupported matrix schema in ${resolved}: '$([string]$m.schema)' (expected probe_matrix.v1)"
    }
    if ($null -eq $m.cases -or @($m.cases).Count -eq 0) { throw "matrix has no cases: $resolved" }
    return $m
}

function Get-CaseTargetInfo {
    param($Case)
    $entry = [string]$Case.entry
    if ([string]::IsNullOrWhiteSpace($entry)) { $entry = 'script' }
    $ref = ''
    switch ($entry) {
        'script' { $ref = [string]$Case.script }
        'scene' { $ref = [string]$Case.scene }
        'main' {
            $mainScene = 'res://main_menu.tscn'
            if ($script:MatrixData -and $script:MatrixData.main_scene) { $mainScene = [string]$script:MatrixData.main_scene }
            $ref = $mainScene
        }
        default { throw "unknown entry '$entry' for case '$([string]$Case.id)'" }
    }
    if ([string]::IsNullOrWhiteSpace($ref)) { throw "case '$([string]$Case.id)' has empty target for entry '$entry'" }
    $fsPath = ConvertFrom-ResPath $ref
    return [pscustomobject]@{
        entry   = $entry
        ref     = $ref
        fs_path = $fsPath
        exists  = (Test-Path -LiteralPath $fsPath -PathType Leaf)
    }
}

function Select-MatrixCases {
    param($Candidates)
    $cats = @()
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $cats = @($Category.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })
    }
    if (-not [string]::IsNullOrWhiteSpace($Only)) {
        try { $null = [regex]::Match('', $Only) } catch { throw "invalid -Only regular expression: $Only" }
    }
    $selected = @()
    foreach ($c in @($Candidates)) {
        if ($cats.Count -gt 0 -and ($cats -notcontains ([string]$c.category).ToLowerInvariant())) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Only)) {
            $target = ''
            try { $target = (Get-CaseTargetInfo -Case $c).ref } catch { $target = '' }
            if (-not (([string]$c.id -match $Only) -or ($target -match $Only))) { continue }
        }
        $selected += $c
    }
    return @($selected)
}

function Get-MatrixCategories {
    return @(@($script:MatrixData.cases) | ForEach-Object { [string]$_.category } | Sort-Object -Unique)
}

# ── gates (probe_matrix.v1 "gates" section) ────────────────────────────────
function Get-MatrixGateNames {
    if ($null -eq $script:MatrixData -or $null -eq $script:MatrixData.gates) { return @() }
    return @($script:MatrixData.gates.PSObject.Properties | ForEach-Object { [string]$_.Name } | Sort-Object)
}

function Get-CaseGateMembership {
    $membership = @{}
    if ($null -ne $script:MatrixData -and $null -ne $script:MatrixData.gates) {
        foreach ($gp in $script:MatrixData.gates.PSObject.Properties) {
            foreach ($cid in @($gp.Value)) {
                $key = [string]$cid
                if (-not $membership.ContainsKey($key)) { $membership[$key] = @() }
                $membership[$key] = @($membership[$key]) + [string]$gp.Name
            }
        }
    }
    return $membership
}

function Select-GateCases {
    param($Candidates)
    if (-not $script:GateProvided) { return @($Candidates) }
    $available = @(Get-MatrixGateNames)
    if ($available.Count -eq 0) {
        throw "matrix has no 'gates' section; -Gate '$Gate' is unavailable"
    }
    if ([string]::IsNullOrWhiteSpace($Gate)) {
        throw ("empty -Gate value. Available gates: " + ($available -join ', '))
    }
    $prop = $script:MatrixData.gates.PSObject.Properties[$Gate]
    if ($null -eq $prop) {
        throw ("unknown gate '$Gate'. Available gates: " + ($available -join ', '))
    }
    $gateIds = @(@($prop.Value) | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    if ($gateIds.Count -eq 0) { throw "gate '$Gate' declares no case ids" }
    $candidateIds = @(@($Candidates) | ForEach-Object { [string]$_.id })
    $missing = @($gateIds | Where-Object { $candidateIds -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw ("gate '$Gate' references case id(s) not present in matrix: " + ($missing -join ', '))
    }
    $selected = @()
    foreach ($c in @($Candidates)) {
        if ($gateIds -contains [string]$c.id) { $selected += $c }
    }
    return @($selected)
}

# ── baseline (known_baseline_failures.v1) ──────────────────────────────────
function Load-Baseline {
    param([string]$PathValue)
    $resolved = Resolve-RepoPath $PathValue
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "baseline file not found: $resolved"
    }
    $raw = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
    try { $b = $raw | ConvertFrom-Json }
    catch { throw "invalid baseline JSON in ${resolved}: $($_.Exception.Message)" }
    if ($null -eq $b) { throw "empty baseline JSON: $resolved" }
    if ([string]$b.schema -ne 'known_baseline_failures.v1') {
        throw "unsupported baseline schema in ${resolved}: '$([string]$b.schema)' (expected known_baseline_failures.v1)"
    }
    if ($null -eq $b.failures -or @($b.failures).Count -eq 0) {
        throw "baseline file has no failures[] entries: $resolved"
    }
    $map = @{}
    foreach ($f in @($b.failures)) {
        if ($null -eq $f -or [string]::IsNullOrWhiteSpace([string]$f.id)) {
            throw "baseline entry missing 'id' in $resolved"
        }
        $id = [string]$f.id
        if ($map.ContainsKey($id)) { throw "duplicate baseline entry for case '$id' in $resolved" }
        foreach ($req in @('expected_exit', 'expected_pass', 'expected_fail')) {
            $prop = $f.PSObject.Properties[$req]
            if ($null -eq $prop -or $null -eq $prop.Value) {
                throw "baseline entry '$id' is missing required field '$req' in $resolved"
            }
        }
        $map[$id] = $f
    }
    $sha = ''
    try { $sha = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant() } catch { $sha = '' }
    return [pscustomobject]@{
        absolute_path = $resolved
        path          = (Format-RepoRelative $resolved)
        schema        = [string]$b.schema
        commit        = [string]$b.baseline_commit
        environment   = $b.environment
        provenance    = [string]$b.evidence_provenance
        file_sha256   = $sha
        map           = $map
        entries_total = [int]@($map.Keys).Count
        raw           = $b
    }
}

function Get-CaseBaselineInfo {
    param($Result, $BaselineData)
    if ($null -eq $BaselineData) { return $null }
    $id = [string]$Result.id
    $status = [string]$Result.status
    if (-not $BaselineData.map.ContainsKey($id)) {
        if ($status -eq 'FAIL') {
            return [ordered]@{
                known    = $false
                matches  = $false
                expected = $false
                reason   = 'case is not listed in known_baseline_failures.json'
            }
        }
        return $null
    }
    $entry = $BaselineData.map[$id]
    $expExit = [int]$entry.expected_exit
    $expPass = [int]$entry.expected_pass
    $expFail = [int]$entry.expected_fail
    if ($status -eq 'FAIL') {
        $actExit = $Result.exit_code
        $actPass = $Result.pass_count
        $actFail = $Result.fail_count
        $exitOk = ($null -ne $actExit) -and ([int]$actExit -eq $expExit)
        $countsOk = ($null -ne $actPass) -and ($null -ne $actFail) -and ([int]$actPass -eq $expPass) -and ([int]$actFail -eq $expFail)
        if ($exitOk -and $countsOk) {
            return [ordered]@{
                known    = $true
                matches  = $true
                expected = $true
                reason   = [string]$entry.reason
            }
        }
        $actualExit = '?'
        if ($null -ne $actExit) { $actualExit = [string]$actExit }
        $actualPass = '?'
        if ($null -ne $actPass) { $actualPass = [string]$actPass }
        $actualFail = '?'
        if ($null -ne $actFail) { $actualFail = [string]$actFail }
        return [ordered]@{
            known    = $true
            matches  = $false
            expected = $false
            reason   = ('expected exit={0} pass={1} fail={2}, got exit={3} pass={4} fail={5}' -f $expExit, $expPass, $expFail, $actualExit, $actualPass, $actualFail)
        }
    }
    if ($status -eq 'PASS') {
        # A declared baseline failure that now passes is also a baseline change: surface
        # it as drift so the baseline file is refreshed after triage. It is never hidden.
        return [ordered]@{
            known    = $true
            matches  = $false
            expected = $false
            reason   = 'known baseline failure no longer reproduces (now PASS); triage and refresh known_baseline_failures.json'
        }
    }
    return [ordered]@{
        known    = $true
        matches  = $false
        expected = $false
        reason   = ('expected FAIL, got ' + $status)
    }
}

function Get-BaselineStats {
    param([object[]]$Results, $BaselineData)
    $knownFail = 0
    $newFail = 0
    $drift = 0
    $seenIds = @{}
    foreach ($r in $Results) {
        $id = [string]$r.id
        $seenIds[$id] = $true
        $info = Get-CaseBaselineInfo -Result $r -BaselineData $BaselineData
        $r['baseline'] = $info
        if ($null -eq $info) { continue }
        $status = [string]$r.status
        if ($status -eq 'FAIL') {
            if ($info.expected) { $knownFail++ }
            elseif ($info.known) { $drift++ }
            else { $newFail++ }
        }
        elseif ($status -eq 'PASS' -and $info.known) {
            $drift++
        }
    }
    $notSelected = 0
    foreach ($id in @($BaselineData.map.Keys)) {
        if (-not $seenIds.ContainsKey([string]$id)) { $notSelected++ }
    }
    return [pscustomobject]@{
        known_fail           = $knownFail
        new_fail             = $newFail
        baseline_drift       = $drift
        entries_total        = [int]$BaselineData.entries_total
        entries_not_selected = $notSelected
    }
}

# ── Godot discovery / version / import ─────────────────────────────────────
function Find-GodotExecutable {
    if (-not [string]::IsNullOrWhiteSpace($GodotBin)) {
        $candidate = Resolve-RepoPath $GodotBin
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [pscustomobject]@{ path = ''; found_via = 'parameter'; error = "-GodotBin not found: $candidate"; candidates = @() }
        }
        return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $candidate).Path; found_via = 'parameter'; error = ''; candidates = @($candidate) }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        $candidate = $env:GODOT_BIN
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [pscustomobject]@{ path = ''; found_via = 'GODOT_BIN'; error = "`$env:GODOT_BIN is set but not found: $candidate"; candidates = @($candidate) }
        }
        return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $candidate).Path; found_via = 'GODOT_BIN'; error = ''; candidates = @($candidate) }
    }
    $toolDir = Join-Path $script:RepoRoot 'tools/godot'
    if (Test-Path -LiteralPath $toolDir -PathType Container) {
        $cands = @(Get-ChildItem -LiteralPath $toolDir -Filter 'Godot*console.exe' -File -ErrorAction SilentlyContinue)
        if ($cands.Count -gt 0) {
            # Deterministic pick: newest-looking name first (e.g. 4.7.2 over 4.7.1).
            $pick = @($cands | Sort-Object Name -Descending)[0]
            return [pscustomobject]@{ path = $pick.FullName; found_via = 'tools/godot'; error = ''; candidates = @($cands | ForEach-Object { $_.FullName }) }
        }
    }
    $pathHits = @()
    foreach ($name in @('godot', 'godot4')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $src = ''
            try { $src = $cmd.Source } catch { $src = '' }
            if ([string]::IsNullOrWhiteSpace($src)) { try { $src = $cmd.Path } catch { $src = '' } }
            if (-not [string]::IsNullOrWhiteSpace($src) -and (Test-Path -LiteralPath $src -PathType Leaf)) {
                return [pscustomobject]@{ path = $src; found_via = 'PATH'; error = ''; candidates = @($src) }
            }
            $pathHits += $name
        }
    }
    return [pscustomobject]@{ path = ''; found_via = 'none'; error = 'no Godot executable found (-GodotBin, $env:GODOT_BIN, tools/godot/Godot*console.exe, PATH godot/godot4)'; candidates = $pathHits }
}

function Get-GodotVersionInfo {
    param([string]$BinPath)
    $expected = '4.7.2'
    if ($script:MatrixData -and $script:MatrixData.godot_version) { $expected = [string]$script:MatrixData.godot_version }
    $res = Invoke-ProcessCapture -FilePath $BinPath -ArgumentList @('--version') -WorkingDirectory $script:RepoRoot -TimeoutSec 60
    $raw = (($res.stdout + "`n" + $res.stderr) -replace '\s+', ' ').Trim()
    $match = $false
    if ($res.exit_code -eq 0 -and $raw -match [regex]::Escape($expected)) { $match = $true }
    return [pscustomobject]@{
        version_raw      = $raw
        version_expected = $expected
        version_match    = $match
        exit_code        = $res.exit_code
        duration_s       = $res.duration_s
    }
}

function Invoke-ImportPreflight {
    param([string]$RunDirPath)
    $logPath = Join-Path $RunDirPath 'import.log'
    $projectArg = $script:ProjectRel
    $res = Invoke-ProcessCapture -FilePath $script:Godot.path -ArgumentList @('--headless', '--path', $projectArg, '--import') -WorkingDirectory $script:RepoRoot -TimeoutSec 300 -LogPath $logPath
    $errorLines = @(($res.output -split "`r?`n") | Where-Object { $_ -match 'SCRIPT ERROR|(?i:parse error)|(?i:failed to load)|(?i:error importing)' })
    $allErrorLines = @(($res.output -split "`r?`n") | Where-Object { $_ -match '(?m)^ERROR:|SCRIPT ERROR' })
    $failed = $false
    $reason = ''
    if ($res.timed_out) { $failed = $true; $reason = 'import preflight TIMEOUT (>300s)' }
    elseif ($null -eq $res.exit_code -or $res.exit_code -ne 0) { $failed = $true; $reason = "import preflight exit code $($res.exit_code)" }
    elseif ($errorLines.Count -gt 0) { $failed = $true; $reason = "import preflight errors: $($errorLines[0].Trim())" }
    return [pscustomobject]@{
        status           = $(if ($failed) { 'FAIL' } else { 'PASS' })
        reason           = $reason
        exit_code        = $res.exit_code
        duration_s       = $res.duration_s
        log_path         = (Format-RepoRelative $logPath)
        error_line_count = $allErrorLines.Count
        error_sample     = @($allErrorLines | Select-Object -First 5)
        timed_out        = $res.timed_out
    }
}

# ── case execution ─────────────────────────────────────────────────────────
function Get-CaseEnvMap {
    param($Case)
    $envMap = @{}
    if ($null -ne $Case.env) {
        foreach ($p in $Case.env.PSObject.Properties) { $envMap[[string]$p.Name] = [string]$p.Value }
    }
    return $envMap
}

function Get-CaseArguments {
    param($Case, $Target)
    $args = @('--headless', '--path', $script:ProjectRel)
    switch ($Target.entry) {
        'script' { $args += @('--script', [string]$Case.script) }
        'scene' { $args += [string]$Case.scene }
        'main' { }
    }
    if ($null -ne $Case.extra_args) { foreach ($a in @($Case.extra_args)) { $args += [string]$a } }
    return $args
}

function Format-CaseCommand {
    param($Case, $Target, [string[]]$ArgList, [hashtable]$EnvMap)
    $parts = @()
    foreach ($k in @($EnvMap.Keys)) { $parts += ('{0}={1}' -f $k, $EnvMap[$k]) }
    $parts += (Format-DisplayPath $script:Godot.path)
    foreach ($a in $ArgList) {
        if ($a -match '\s') { $parts += ('"' + $a + '"') } else { $parts += $a }
    }
    return ($parts -join ' ')
}

function Get-CaseTimeoutSeconds {
    param($Case)
    if ($script:TimeoutOverride -gt 0) { return $script:TimeoutOverride }
    if ($null -ne $Case.timeout_s -and [int]$Case.timeout_s -gt 0) { return [int]$Case.timeout_s }
    if ($script:MatrixData -and $null -ne $script:MatrixData.defaults -and $null -ne $script:MatrixData.defaults.timeout_s) {
        return [int]$script:MatrixData.defaults.timeout_s
    }
    return 240
}

function Get-CaseVerdict {
    param($Case, $Proc)
    $parserName = [string]$Case.result
    if ([string]::IsNullOrWhiteSpace($parserName)) {
        $parserName = 'probe'
        if ($script:MatrixData -and $script:MatrixData.defaults -and $script:MatrixData.defaults.result) { $parserName = [string]$script:MatrixData.defaults.result }
    }
    $output = [string]$Proc.output
    # expected markers
    $expected = @()
    if ($null -ne $Case.expected_markers) { $expected = @($Case.expected_markers | ForEach-Object { [string]$_ }) }
    $missing = @()
    foreach ($m in $expected) {
        if ([string]::IsNullOrEmpty($m)) { continue }
        if ($output.IndexOf($m, [System.StringComparison]::Ordinal) -lt 0) { $missing += $m }
    }
    $markerOk = ($missing.Count -eq 0)
    # PASS/FAIL counts from the declared parser
    $passCount = $null
    $failCount = $null
    $parseOk = $true
    $parsePattern = ''
    if ($parserName -ne 'markers') {
        if ($script:MatrixData -and $script:MatrixData.result_parsers) {
            $prop = $script:MatrixData.result_parsers.PSObject.Properties[$parserName]
            if ($null -ne $prop) { $parsePattern = [string]$prop.Value }
        }
        if ([string]::IsNullOrWhiteSpace($parsePattern)) {
            $parsePattern = 'PROBE RESULT:\s*PASS=(\d+)\s+FAIL=(\d+)'
        }
        $matchesFound = [regex]::Matches($output, $parsePattern)
        if ($matchesFound.Count -eq 0) {
            $parseOk = $false
        }
        else {
            $last = $matchesFound[$matchesFound.Count - 1]
            $passCount = [int]$last.Groups[1].Value
            $failCount = [int]$last.Groups[2].Value
        }
    }
    else {
        $passCount = ($expected.Count - $missing.Count)
        $failCount = $missing.Count
    }
    # fatal runtime patterns: boot cases only (probes may intentionally exercise parse/rejection paths)
    $fatal = $null
    if ($parserName -eq 'markers') {
        $fatalMatch = [regex]::Match($output, $script:FatalBootRegex)
        if ($fatalMatch.Success) { $fatal = "fatal runtime error in boot log: $($fatalMatch.Value)" }
    }
    # status decision
    $status = 'PASS'
    $reason = ''
    if ($Proc.timed_out) { $status = 'TIMEOUT'; $reason = 'process did not exit before per-case timeout' }
    elseif ($null -eq $Proc.exit_code) { $status = 'FAIL'; $reason = 'process exit code unavailable' }
    elseif ($Proc.exit_code -ne 0) { $status = 'FAIL'; $reason = "exit code $($Proc.exit_code)" }
    elseif (-not $parseOk) { $status = 'FAIL'; $reason = "result line missing (parser '$parserName')" }
    elseif ($null -ne $failCount -and $failCount -gt 0) { $status = 'FAIL'; $reason = "$failCount assertion(s) failed" }
    elseif (-not $markerOk) { $status = 'FAIL'; $reason = "missing expected marker(s): $($missing -join ' | ')" }
    elseif ($fatal) { $status = 'FAIL'; $reason = $fatal }
    $errorLineCount = @(($output -split "`r?`n") | Where-Object { $_ -match '(?m)^ERROR:|SCRIPT ERROR' }).Count
    return [pscustomobject]@{
        status         = $status
        reason         = $reason
        pass_count     = $passCount
        fail_count     = $failCount
        marker_ok      = $markerOk
        missing_markers = $missing
        error_lines    = $errorLineCount
        parser         = $parserName
    }
}

function Invoke-MatrixCase {
    param($Case, $Target, [string]$RunDirPath)
    $id = [string]$Case.id
    $logAbs = Join-Path (Join-Path $RunDirPath 'logs') ($id + '.log')
    $envMap = Get-CaseEnvMap -Case $Case
    $argList = Get-CaseArguments -Case $Case -Target $Target
    $commandText = Format-CaseCommand -Case $Case -Target $Target -ArgList $argList -EnvMap $envMap
    $timeout = Get-CaseTimeoutSeconds -Case $Case
    $attempts = 0
    $result = $null
    while ($true) {
        $attempts++
        $proc = Invoke-ProcessCapture -FilePath $script:Godot.path -ArgumentList $argList -WorkingDirectory $script:RepoRoot -TimeoutSec $timeout -Environment $envMap -LogPath $logAbs
        $verdict = Get-CaseVerdict -Case $Case -Proc $proc
        $result = [ordered]@{
            id               = $id
            category         = [string]$Case.category
            profile          = [string]$Case.profile
            entry            = $Target.entry
            purpose          = [string]$Case.purpose
            script           = $(if ($Target.entry -eq 'script') { $Target.ref } else { $null })
            scene            = $(if ($Target.entry -in @('scene', 'main')) { $Target.ref } else { $null })
            env              = $envMap
            command          = $commandText
            exit_code        = $proc.exit_code
            status           = $verdict.status
            duration_s       = $proc.duration_s
            pass_count       = $verdict.pass_count
            fail_count       = $verdict.fail_count
            expected_markers = @($Case.expected_markers)
            marker_ok        = $verdict.marker_ok
            log_path         = (Format-RepoRelative $logAbs)
            reason           = $verdict.reason
            attempts         = $attempts
            blocked          = $false
            error_lines      = $verdict.error_lines
            baseline         = $null
        }
        $transient = ($proc.output -match $script:TransientRegex)
        if ($verdict.status -ne 'PASS' -and $attempts -lt 2 -and -not $proc.timed_out -and $transient) {
            Write-Warn ("      TRANSIENT: {0} matched file-lock pattern; retrying once" -f $id)
            Start-Sleep -Milliseconds 800
            continue
        }
        break
    }
    return $result
}

# ── reporting ──────────────────────────────────────────────────────────────
function Write-ConsoleCaseRow {
    param($Entry)
    $profile = [string]$Entry.profile
    if ([string]::IsNullOrWhiteSpace($profile)) { $profile = '-' }
    $exitText = '-'
    if ($null -ne $Entry.exit_code) { $exitText = [string]$Entry.exit_code }
    $pf = '-'
    if ($null -ne $Entry.pass_count -and $null -ne $Entry.fail_count) {
        if ($Entry.status -eq 'NOT RUN') { $pf = '-' } else { $pf = ('{0}/{1}' -f $Entry.pass_count, $Entry.fail_count) }
    }
    elseif ($Entry.status -ne 'NOT RUN') {
        $pf = ('m:{0}/{1}' -f @($Entry.expected_markers).Count, @($Entry.expected_markers).Count)
    }
    $dur = ('{0:N1}s' -f [double]$Entry.duration_s)
    $linePrefix = ('{0,-36} {1,-12} {2,-10} ' -f $Entry.id, $Entry.category, $profile)
    $lineRest = ('{0,-8} {1,5} {2,8} {3,8} {4}' -f $Entry.status, $exitText, $dur, $pf, $Entry.log_path)
    $color = 'Gray'
    switch ($Entry.status) {
        'PASS' { $color = 'Green' }
        'FAIL' { $color = 'Red' }
        'TIMEOUT' { $color = 'Red' }
        'NOT RUN' { $color = 'Yellow' }
    }
    if ($script:CiMode) {
        Write-Host ($linePrefix + $lineRest)
    }
    else {
        Write-Host $linePrefix -NoNewline
        Write-Host ('{0,-8}' -f $Entry.status) -NoNewline -ForegroundColor $color
        Write-Host (' ' + ('{0,5} {1,8} {2,8} {3}' -f $exitText, $dur, $pf, $Entry.log_path))
    }
}

function Write-ConsoleTableHeader {
    Write-Head ('{0,-36} {1,-12} {2,-10} {3,-8} {4,5} {5,8} {6,8} {7}' -f 'CASE', 'CATEGORY', 'PROFILE', 'STATUS', 'EXIT', 'TIME', 'PASS/FAIL', 'LOG')
}

function Write-HumanReport {
    param(
        [string]$Path,
        [string]$RunIdValue,
        [string]$StartedAt,
        [string]$EndedAt,
        $GitInfo,
        $GodotVersion,
        $ImportInfo,
        [string[]]$ClearedEnvNames,
        [string[]]$Filters,
        [object[]]$Results,
        $Totals,
        [int]$ExitCode,
        [string]$GateName = '',
        $BaselineData = $null,
        $BaselineStats = $null
    )
    $baselineMode = ($null -ne $BaselineData)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# GHOST TRACK // APSIS · V17 headless regression report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> Generated by `run_tests.ps1`. Machine-readable twin: `summary.json` in the same directory.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Run')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| field | value |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine(('| run_id | `{0}` |' -f $RunIdValue))
    [void]$sb.AppendLine(('| started_at | `{0}` |' -f $StartedAt))
    [void]$sb.AppendLine(('| ended_at | `{0}` |' -f $EndedAt))
    if ($null -ne $GitInfo) {
        [void]$sb.AppendLine(('| git branch | `{0}` |' -f $GitInfo.branch))
        [void]$sb.AppendLine(('| git commit | `{0}` |' -f $GitInfo.commit))
        [void]$sb.AppendLine(('| worktree dirty (tracked) | `{0}` |' -f $GitInfo.worktree_dirty))
    }
    if ($null -ne $GodotVersion) {
        [void]$sb.AppendLine(('| godot path | `{0}` |' -f (Format-DisplayPath $script:Godot.path)))
        [void]$sb.AppendLine(('| godot version | `{0}` (expected {1}, match={2}) |' -f $GodotVersion.version_raw, $GodotVersion.version_expected, $GodotVersion.version_match))
    }
    if ($null -ne $ImportInfo) {
        [void]$sb.AppendLine(('| import preflight | `{0}`{1} |' -f $ImportInfo.status, $(if ($ImportInfo.reason) { ': ' + $ImportInfo.reason } else { '' })))
    }
    [void]$sb.AppendLine(('| env isolation | cleared {0} inherited `DSH_*`/`V17_*` var(s) before each case |' -f $ClearedEnvNames.Count))
    [void]$sb.AppendLine(('| filters | {0} |' -f ($Filters -join '; ')))
    if (-not [string]::IsNullOrWhiteSpace($GateName)) {
        [void]$sb.AppendLine(('| gate | `{0}` |' -f $GateName))
    }
    if ($baselineMode) {
        [void]$sb.AppendLine('| baseline mode | enabled (case statuses unchanged) |')
        [void]$sb.AppendLine(('| baseline file | `{0}` |' -f $BaselineData.path))
        [void]$sb.AppendLine(('| baseline commit | `{0}` |' -f $BaselineData.commit))
        [void]$sb.AppendLine(('| baseline schema | `{0}` |' -f $BaselineData.schema))
        [void]$sb.AppendLine(('| baseline sha256 | `{0}` |' -f $BaselineData.file_sha256))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Totals')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| total | pass | fail | timeout | not run (expected) | not run (unexpected) | duration |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- |')
    [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6:N1}s |' -f $Totals.total, $Totals.pass, $Totals.fail, $Totals.timeout, $Totals.not_run_expected, $Totals.not_run_unexpected, $Totals.duration_s))
    if ($baselineMode) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| known_fail | new_fail | baseline_drift |')
        [void]$sb.AppendLine('| --- | --- | --- |')
        [void]$sb.AppendLine(('| {0} | {1} | {2} |' -f $Totals.known_fail, $Totals.new_fail, $Totals.baseline_drift))
    }
    if ($baselineMode) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## Baseline')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('> Case statuses are NOT changed by baseline mode: declared legacy failures remain **FAIL** in the case table; nothing is renamed PASS, hidden, skipped or continue-on-error.')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('`BASELINE CHECK: known_fail={0} new_fail={1} drift={2}`' -f $BaselineStats.known_fail, $BaselineStats.new_fail, $BaselineStats.baseline_drift))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('- baseline file: `{0}`' -f $BaselineData.path))
        [void]$sb.AppendLine(('- baseline commit: `{0}`' -f $BaselineData.commit))
        [void]$sb.AppendLine(('- baseline sha256: `{0}`' -f $BaselineData.file_sha256))
        [void]$sb.AppendLine(('- evidence: {0}' -f ([string]$BaselineData.provenance)))
        [void]$sb.AppendLine(('- entries not selected by filters: {0} of {1}' -f $BaselineStats.entries_not_selected, $BaselineStats.entries_total))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| case | expected exit | expected pass/fail | actual status | actual pass/fail | classification |')
        [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
        $resultById = @{}
        foreach ($r in $Results) { $resultById[[string]$r.id] = $r }
        foreach ($baselineId in @($BaselineData.map.Keys | Sort-Object)) {
            $entry = $BaselineData.map[$baselineId]
            $actualStatus = 'not selected'
            $actualCounts = '-'
            $classification = 'not selected'
            if ($resultById.ContainsKey([string]$baselineId)) {
                $ar = $resultById[[string]$baselineId]
                $actualStatus = [string]$ar.status
                $actualCounts = '-'
                if ($null -ne $ar.pass_count -and $null -ne $ar.fail_count) { $actualCounts = ('{0}/{1}' -f $ar.pass_count, $ar.fail_count) }
                if ($null -ne $ar.baseline) {
                    if ($ar.baseline.expected) { $classification = 'KNOWN-BASELINE' }
                    elseif ($ar.baseline.known) { $classification = 'BASELINE DRIFT' }
                    else { $classification = 'NEW FAILURE' }
                }
            }
            [void]$sb.AppendLine(('| `{0}` | {1} | {2}/{3} | {4} | {5} | {6} |' -f $baselineId, $entry.expected_exit, $entry.expected_pass, $entry.expected_fail, $actualStatus, $actualCounts, $classification))
        }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('## Cases')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| case | category | profile | entry | status | exit | duration | pass/fail | markers | log |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
    foreach ($r in $Results) {
        $exitText = '-'
        if ($null -ne $r.exit_code) { $exitText = [string]$r.exit_code }
        $pf = '-'
        if ($r.status -ne 'NOT RUN' -and $null -ne $r.pass_count) { $pf = ('{0}/{1}' -f $r.pass_count, $r.fail_count) }
        elseif ($r.status -ne 'NOT RUN') { $pf = ('m:{0}/{1}' -f @($r.expected_markers).Count, @($r.expected_markers).Count) }
        $markerText = 'n/a'
        if ($r.status -ne 'NOT RUN') { $markerText = [string]$r.marker_ok }
        $reason = ([string]$r.reason) -replace '\|', '\|'
        $log = ([string]$r.log_path) -replace '\|', '\|'
        [void]$sb.AppendLine(('| `{0}` | {1} | {2} | {3} | **{4}** | {5} | {6:N1}s | {7} | {8} | `{9}` |' -f $r.id, $r.category, $(if ([string]::IsNullOrWhiteSpace([string]$r.profile)) { '-' } else { $r.profile }), $r.entry, $r.status, $exitText, [double]$r.duration_s, $pf, $markerText, $log))
        if ($r.status -ne 'PASS' -and -not [string]::IsNullOrWhiteSpace($reason)) {
            [void]$sb.AppendLine(('  - reason: {0}' -f $reason))
        }
        if ($null -ne $r.baseline) {
            $tag = 'NEW FAILURE'
            if ($r.baseline.expected) { $tag = 'KNOWN-BASELINE' }
            elseif ($r.baseline.known) { $tag = 'BASELINE DRIFT' }
            $blReason = ([string]$r.baseline.reason) -replace '\|', '\|'
            [void]$sb.AppendLine(('  - baseline: {0} — {1}' -f $tag, $blReason))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Interpretation')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- **PASS** — exit code 0, probe fail count 0, all expected markers found. Marker-only boot cases require exit 0 + all markers.')
    [void]$sb.AppendLine('- **FAIL** — nonzero exit, probe fail count > 0, missing result line, missing marker, or (boot cases) `SCRIPT ERROR` / parse error.')
    [void]$sb.AppendLine('- **TIMEOUT** — process killed at the per-case timeout; counts as a failure for the run exit code.')
    [void]$sb.AppendLine('- **NOT RUN** — declared blocked case (matrix `blocked: true`) or missing script/scene. Expected blocked cases do not fail the run; unexpected NOT RUN does (exit 1).')
    [void]$sb.AppendLine('- Benign engine error lines (for example `Parent node is busy adding/removing children...`) do not fail a boot case by themselves; exit code, expected markers and fatal patterns are authoritative.')
    [void]$sb.AppendLine('- Every case runs in a fresh Godot process with inherited `DSH_*`/`V17_*` env vars cleared; only the case-declared env is applied.')
    if ($baselineMode) {
        [void]$sb.AppendLine('- **Baseline mode** — statuses are unchanged. `known_fail` = FAIL matching the declared baseline exactly; `new_fail` = FAIL not declared in the baseline; `baseline_drift` = declared failure with changed exit/counts OR a declared failure that now passes. Exit 0 requires new_fail=0, baseline_drift=0, timeout=0 and unexpected NOT RUN=0.')
    }
    [void]$sb.AppendLine('')
    if ($baselineMode) {
        [void]$sb.AppendLine(('Overall run exit code (baseline-aware): **{0}**' -f $ExitCode))
    }
    else {
        [void]$sb.AppendLine(('Overall run exit code: **{0}**' -f $ExitCode))
    }
    [void]$sb.AppendLine('')
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $script:Utf8)
}

function Write-SummaryJson {
    param(
        [string]$Path,
        [string]$RunIdValue,
        [string]$StartedAt,
        [string]$EndedAt,
        $GitInfo,
        $GodotVersion,
        $ImportInfo,
        [string[]]$ClearedEnvNames,
        [string[]]$Filters,
        [object[]]$Results,
        $Totals,
        [int]$ExitCode,
        [bool]$EnvironmentBlocked,
        [string]$BlockedReason,
        [string]$GateName = '',
        $BaselineData = $null,
        $BaselineStats = $null
    )
    $godotBlock = [ordered]@{
        path             = $(if ($null -ne $script:Godot -and $script:Godot.path) { Format-DisplayPath $script:Godot.path } else { $null })
        found_via        = $(if ($null -ne $script:Godot) { [string]$script:Godot.found_via } else { 'none' })
        version_raw      = $(if ($null -ne $GodotVersion) { [string]$GodotVersion.version_raw } else { $null })
        version_expected = $(if ($null -ne $GodotVersion) { [string]$GodotVersion.version_expected } else { $null })
        version_match    = $(if ($null -ne $GodotVersion) { [bool]$GodotVersion.version_match } else { $false })
    }
    $importBlock = [ordered]@{
        status            = $(if ($null -ne $ImportInfo) { [string]$ImportInfo.status } else { 'NOT RUN' })
        reason            = $(if ($null -ne $ImportInfo) { [string]$ImportInfo.reason } else { $BlockedReason })
        exit_code         = $(if ($null -ne $ImportInfo) { $ImportInfo.exit_code } else { $null })
        duration_s        = $(if ($null -ne $ImportInfo) { $ImportInfo.duration_s } else { 0 })
        log_path          = $(if ($null -ne $ImportInfo) { [string]$ImportInfo.log_path } else { $null })
        error_line_count  = $(if ($null -ne $ImportInfo) { [int]$ImportInfo.error_line_count } else { 0 })
        errors            = $(if ($null -ne $ImportInfo) { @($ImportInfo.error_sample) } else { @() })
    }
    $gitBlock = [ordered]@{
        branch           = $(if ($null -ne $GitInfo) { [string]$GitInfo.branch } else { '' })
        commit           = $(if ($null -ne $GitInfo) { [string]$GitInfo.commit } else { '' })
        commit_short     = $(if ($null -ne $GitInfo) { [string]$GitInfo.commit_short } else { '' })
        worktree_dirty   = $(if ($null -ne $GitInfo) { [bool]$GitInfo.worktree_dirty } else { $false })
        modified_tracked = $(if ($null -ne $GitInfo) { @($GitInfo.modified_tracked) } else { @() })
        read_error       = $(if ($null -ne $GitInfo) { [string]$GitInfo.error } else { '' })
    }
    $hostBlock = [ordered]@{
        os         = [System.Environment]::OSVersion.VersionString
        os_name    = $(if ($env:OS) { [string]$env:OS } else { '' })
        ps_version = $PSVersionTable.PSVersion.ToString()
        pwsh       = [bool]($PSVersionTable.PSEdition -eq 'Core')
    }
    $summary = [ordered]@{
        schema            = 'test_summary.v1'
        run_id            = $RunIdValue
        started_at        = $StartedAt
        ended_at          = $EndedAt
        invocation        = [ordered]@{
            script       = 'run_tests.ps1'
            matrix       = (Format-RepoRelative (Resolve-RepoPath $MatrixPathForSummary))
            project      = $script:ProjectRel
            filters      = @($Filters)
            ci           = $script:CiMode
            no_import    = [bool]$NoImport
            timeout_sec  = $script:TimeoutOverride
            gate         = $(if ([string]::IsNullOrWhiteSpace($GateName)) { $null } else { $GateName })
            baseline     = $(if ($null -ne $BaselineData) { [string]$BaselineData.path } else { $null })
        }
        gate              = $(if ([string]::IsNullOrWhiteSpace($GateName)) { $null } else { $GateName })
        baseline          = [ordered]@{
            mode                = [bool]($null -ne $BaselineData)
            path                = $(if ($null -ne $BaselineData) { [string]$BaselineData.path } else { $null })
            schema              = $(if ($null -ne $BaselineData) { [string]$BaselineData.schema } else { $null })
            baseline_commit     = $(if ($null -ne $BaselineData) { [string]$BaselineData.commit } else { $null })
            file_sha256         = $(if ($null -ne $BaselineData) { [string]$BaselineData.file_sha256 } else { $null })
            evidence_provenance = $(if ($null -ne $BaselineData) { [string]$BaselineData.provenance } else { $null })
            environment         = $(if ($null -ne $BaselineData) { $BaselineData.environment } else { $null })
            known_fail          = $(if ($null -ne $BaselineStats) { [int]$BaselineStats.known_fail } else { $null })
            new_fail            = $(if ($null -ne $BaselineStats) { [int]$BaselineStats.new_fail } else { $null })
            baseline_drift      = $(if ($null -ne $BaselineStats) { [int]$BaselineStats.baseline_drift } else { $null })
            entries_total       = $(if ($null -ne $BaselineData) { [int]$BaselineData.entries_total } else { $null })
            entries_not_selected = $(if ($null -ne $BaselineStats) { [int]$BaselineStats.entries_not_selected } else { $null })
        }
        godot             = $godotBlock
        # Top-level convenience aliases (a few CI consumers only read flat fields).
        godot_version     = $(if ($null -ne $GodotVersion) { [string]$GodotVersion.version_raw } else { $null })
        git               = $gitBlock
        git_branch        = $(if ($null -ne $GitInfo) { [string]$GitInfo.branch } else { '' })
        git_commit        = $(if ($null -ne $GitInfo) { [string]$GitInfo.commit } else { '' })
        host              = $hostBlock
        host_os           = [System.Environment]::OSVersion.VersionString
        import            = $importBlock
        env_isolation     = [ordered]@{
            cleared_prefixes = @(Get-TestEnvPrefixes)
            cleared_vars     = @($ClearedEnvNames)
        }
        environment_blocked = $EnvironmentBlocked
        blocked_reason    = $(if ($EnvironmentBlocked) { $BlockedReason } else { '' })
        cases             = @($Results)
        totals            = $Totals
        exit_code         = $ExitCode
    }
    $json = ConvertTo-Json -InputObject $summary -Depth 12
    [System.IO.File]::WriteAllText($Path, $json + "`n", $script:Utf8)
}

# Matrix path is remembered for summary/report after resolution.
$script:MatrixPathForSummary = ''
if (-not [string]::IsNullOrWhiteSpace($Matrix)) { $script:MatrixPathForSummary = $Matrix } else { $script:MatrixPathForSummary = 'game_v17/tests/probe_matrix.json' }
$MatrixPathForSummary = $script:MatrixPathForSummary

function Get-GitInfo {
    $info = [ordered]@{
        branch = ''; commit = ''; commit_short = ''; worktree_dirty = $false; modified_tracked = @(); error = ''
    }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) { $info.error = 'git not found'; return [pscustomobject]$info }
    try {
        $branchOut = & git -C $script:RepoRoot branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0) { $info.branch = (($branchOut | Out-String).Trim()) }
        $commitOut = & git -C $script:RepoRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            $info.commit = (($commitOut | Out-String).Trim())
            if ($info.commit.Length -gt 8) { $info.commit_short = $info.commit.Substring(0, 8) }
            else { $info.commit_short = $info.commit }
        }
        $statusOut = & git -C $script:RepoRoot status --porcelain --untracked-files=no 2>$null
        $statusLines = @($statusOut | Where-Object { $_ -and ([string]$_).Trim().Length -gt 0 })
        if ($statusLines.Count -gt 0) {
            $info.worktree_dirty = $true
            $info.modified_tracked = @($statusLines | ForEach-Object { ([string]$_).Trim() } | Select-Object -First 30)
        }
    }
    catch { $info.error = "git read failed: $($_.Exception.Message)" }
    return [pscustomobject]$info
}

function Get-HostInfo {
    return [ordered]@{
        os         = [System.Environment]::OSVersion.VersionString
        os_name    = $(if ($env:OS) { [string]$env:OS } else { '' })
        ps_version = $PSVersionTable.PSVersion.ToString()
        pwsh       = [bool]($PSVersionTable.PSEdition -eq 'Core')
    }
}

function Get-Totals {
    param([object[]]$Results, [double]$DurationSeconds)
    $pass = 0; $fail = 0; $timeout = 0; $notRunExpected = 0; $notRunUnexpected = 0
    foreach ($r in $Results) {
        switch ([string]$r.status) {
            'PASS' { $pass++ }
            'FAIL' { $fail++ }
            'TIMEOUT' { $timeout++ }
            'NOT RUN' {
                if ($r.blocked -eq $true) { $notRunExpected++ } else { $notRunUnexpected++ }
            }
        }
    }
    return [ordered]@{
        total              = @($Results).Count
        pass               = $pass
        fail               = $fail
        timeout            = $timeout
        not_run            = ($notRunExpected + $notRunUnexpected)
        not_run_expected   = $notRunExpected
        not_run_unexpected = $notRunUnexpected
        ran                = ($pass + $fail + $timeout)
        duration_s         = [math]::Round($DurationSeconds, 2)
    }
}

function Get-ExitCodeForTotals {
    param($Totals, [bool]$BaselineMode = $false)
    if ($null -ne $Totals.timeout -and [int]$Totals.timeout -gt 0) { return 1 }
    if ($null -ne $Totals.not_run_unexpected -and [int]$Totals.not_run_unexpected -gt 0) { return 1 }
    if ($BaselineMode) {
        # Baseline-aware gate: declared known failures are accepted, but any new failure
        # or any change vs the declared baseline (counts/exit or a now-passing known
        # failure) must turn the run red.
        if ($null -ne $Totals.new_fail -and [int]$Totals.new_fail -gt 0) { return 1 }
        if ($null -ne $Totals.baseline_drift -and [int]$Totals.baseline_drift -gt 0) { return 1 }
        return 0
    }
    if ($null -ne $Totals.fail -and [int]$Totals.fail -gt 0) { return 1 }
    return 0
}

# ── main ───────────────────────────────────────────────────────────────────
# Wrapped in a function so early `return` paths still reach the final `exit`.
function Invoke-Runner {
$exitCode = 2
$globalTimer = [System.Diagnostics.Stopwatch]::StartNew()
$startedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$filters = @()
$importInfo = $null
$godotVersion = $null
$gitInfo = $null
$totals = $null

try {
    if (-not (Test-Path -LiteralPath (Join-Path $script:ProjectDir 'project.godot') -PathType Leaf)) {
        throw "not a GHOST TRACK repository root (game_v17/project.godot missing): $script:RepoRoot"
    }
    if ($script:TimeoutOverride -lt 0) { throw "-TimeoutSec must be >= 0 (0 = use per-case matrix timeout)" }

    $script:MatrixData = Load-Matrix $script:MatrixPathForSummary
    $allCases = @($script:MatrixData.cases)

    # ── optional baseline file (baseline-aware mode) ──
    if ($script:BaselineProvided) {
        if ([string]::IsNullOrWhiteSpace($Baseline)) {
            throw 'empty -Baseline path; expected e.g. game_v17/tests/known_baseline_failures.json'
        }
        $script:BaselineData = Load-Baseline $Baseline
        $caseIdsForBaseline = @($allCases | ForEach-Object { [string]$_.id })
        $unknownBaselineIds = @($script:BaselineData.map.Keys | Where-Object { $caseIdsForBaseline -notcontains [string]$_ })
        if ($unknownBaselineIds.Count -gt 0) {
            throw ("baseline file references case id(s) not present in matrix: " + ($unknownBaselineIds -join ', '))
        }
    }

    # ── optional gate selection (composable with -Category / -Only) ──
    $gateCandidates = @(Select-GateCases -Candidates $allCases)
    $selected = @(Select-MatrixCases -Candidates $gateCandidates)
    if ($script:GateProvided) { $filters += "gate=$Gate" } else { $filters += 'gate=(none)' }
    if ($null -ne $script:BaselineData) { $filters += "baseline=$($script:BaselineData.path)" } else { $filters += 'baseline=(none)' }
    if ($Category) { $filters += "category=$Category" } else { $filters += 'category=all' }
    if ($Only) { $filters += "only=$Only" } else { $filters += 'only=(none)' }
    if ($NoImport) { $filters += 'import=skipped' } else { $filters += 'import=on' }
    if ($script:TimeoutOverride -gt 0) { $filters += "timeout=$($script:TimeoutOverride)s" } else { $filters += 'timeout=per-case' }

    if ($List) {
        Write-Head 'GHOST TRACK // APSIS - V17 headless regression matrix'
        Write-Info ("repo:   {0}" -f (Format-RepoRelative $script:RepoRoot))
        Write-Info ("matrix: {0} v{1} ({2} cases total)" -f (Format-RepoRelative (Resolve-RepoPath $script:MatrixPathForSummary)), [string]$script:MatrixData.version, $allCases.Count)
        if ($script:GateProvided) {
            Write-Info ("gate:   {0} ({1} case(s))" -f $Gate, $selected.Count)
        }
        else {
            Write-Info ("gates:  {0}" -f $(if ((Get-MatrixGateNames).Count -gt 0) { (Get-MatrixGateNames) -join ', ' } else { '(none)' }))
        }
        if ($null -ne $script:BaselineData) {
            Write-Info ("baseline: {0} (commit {1}, mode=CHECK)" -f $script:BaselineData.path, $script:BaselineData.commit)
        }
        Write-Info ("filter: {0}" -f ($filters -join '; '))
        Write-Info ''
        $gateMembership = Get-CaseGateMembership
        Write-Head ('{0,-36} {1,-12} {2,-10} {3,-8} {4,7} {5,-14} {6}' -f 'CASE', 'CATEGORY', 'PROFILE', 'ENTRY', 'TIMEOUT', 'GATES', 'TARGET')
        foreach ($c in $selected) {
            $profile = [string]$c.profile
            if ([string]::IsNullOrWhiteSpace($profile)) { $profile = '-' }
            try { $target = (Get-CaseTargetInfo -Case $c).ref } catch { $target = '?' }
            $gateText = '-'
            if ($gateMembership.ContainsKey([string]$c.id)) { $gateText = (@($gateMembership[[string]$c.id]) -join ',') }
            $blockedSuffix = ''
            if ($c.blocked -eq $true) { $blockedSuffix = '  [BLOCKED: ' + [string]$c.blocked_reason + ']' }
            Write-Info ('{0,-36} {1,-12} {2,-10} {3,-8} {4,7} {5,-14} {6}{7}' -f $c.id, $c.category, $profile, $c.entry, $(if ($c.timeout_s) { ([string]$c.timeout_s) + 's' } else { 'default' }), $gateText, $target, $blockedSuffix)
        }
        Write-Info ''
        Write-Ok ("{0} case(s) selected, {1} blocked by matrix precondition." -f $selected.Count, @($selected | Where-Object { $_.blocked -eq $true }).Count)
        $exitCode = 0
        return $exitCode
    }

    if ($selected.Count -eq 0) {
        Write-Err ("No matrix cases matched filters: {0}" -f ($filters -join '; '))
        Write-Info ("Available categories: {0}" -f ((Get-MatrixCategories) -join ', '))
        $gateNames = @(Get-MatrixGateNames)
        if ($gateNames.Count -gt 0) { Write-Info ("Available gates: {0}" -f ($gateNames -join ', ')) }
        Write-Info 'Use -List to inspect the matrix.'
        $exitCode = 2
        return $exitCode
    }

    # ── Godot discovery ──
    $script:Godot = Find-GodotExecutable
    $blockedReason = ''
    if (-not $script:Godot.path) {
        $blockedReason = [string]$script:Godot.error
        Write-Err 'BLOCKED: no Godot executable available.'
        Write-Err ("  {0}" -f $blockedReason)
        Write-Info '  Set -GodotBin <path>, $env:GODOT_BIN, place tools/godot/Godot*console.exe, or put godot/godot4 on PATH.'
    }
    else {
        Write-Info ("godot:  {0}" -f (Format-DisplayPath $script:Godot.path))
        Write-Info ("        found via {0}" -f $script:Godot.found_via)
        try {
            $godotVersion = Get-GodotVersionInfo -BinPath $script:Godot.path
            Write-Info ("version: {0}" -f $godotVersion.version_raw)
            if ($godotVersion.version_match) {
                Write-Ok ("        expected Godot {0}: MATCH" -f $godotVersion.version_expected)
            }
            else {
                Write-Warn ("        expected Godot {0}: MISMATCH (recorded, not a hard failure)" -f $godotVersion.version_expected)
            }
        }
        catch {
            $blockedReason = "Godot version check failed: $($_.Exception.Message)"
            Write-Err ("BLOCKED: {0}" -f $blockedReason)
        }
    }

    # ── run id / run dir ──
    $gitInfo = Get-GitInfo
    $shaPart = 'nogit'
    if ($gitInfo.commit_short) { $shaPart = $gitInfo.commit_short }
    $script:RunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $shaPart
    $resultsRoot = Resolve-RepoPath $(if ($ResultsDir) { $ResultsDir } else { '.test-results' })
    if (-not (Test-Path -LiteralPath $resultsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
    }
    $script:RunDir = Join-Path $resultsRoot $script:RunId
    if (Test-Path -LiteralPath $script:RunDir -PathType Container) {
        $suffix = 2
        while (Test-Path -LiteralPath ($script:RunDir + '-' + $suffix) -PathType Container) { $suffix++ }
        $script:RunDir = $script:RunDir + '-' + $suffix
        $script:RunId = $script:RunId + '-' + $suffix
    }
    New-Item -ItemType Directory -Path $script:RunDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:RunDir 'logs') -Force | Out-Null

    Write-Info ''
    Write-Head 'GHOST TRACK // APSIS - V17 unified headless regression'
    Write-Info ("repo:    {0}" -f (Format-RepoRelative $script:RepoRoot))
    Write-Info ("matrix:  {0} ({1} cases selected / {2} total)" -f (Format-RepoRelative (Resolve-RepoPath $script:MatrixPathForSummary)), $selected.Count, $allCases.Count)
    Write-Info ("filters: {0}" -f ($filters -join '; '))
    if ($script:GateProvided) {
        Write-Info ("gate:    {0} ({1} case(s): {2})" -f $Gate, $selected.Count, (($selected | ForEach-Object { [string]$_.id }) -join ', '))
    }
    if ($null -ne $script:BaselineData) {
        Write-Info ("baseline: {0} (commit {1}, mode=CHECK; statuses unchanged)" -f $script:BaselineData.path, $script:BaselineData.commit)
    }
    if ($gitInfo.commit) { Write-Info ("git:     {0} @ {1}{2}" -f $gitInfo.branch, $gitInfo.commit_short, $(if ($gitInfo.worktree_dirty) { ' (worktree has tracked modifications)' } else { '' })) }
    Write-Info ("run dir: {0}" -f (Format-RepoRelative $script:RunDir))
    Write-Info ''

    # environment isolation: clear inherited DSH_* / V17_* for the whole run, restore in finally
    $clearedEnvNames = @(Clear-InheritedTestEnv)
    if ($clearedEnvNames.Count -gt 0) {
        Write-Warn ("env:     cleared {0} inherited DSH_*/V17_* var(s): {1}" -f $clearedEnvNames.Count, ($clearedEnvNames -join ', '))
    }
    else {
        Write-Info 'env:     no inherited DSH_*/V17_* vars to clear'
    }

    $envBlocked = [string]::IsNullOrWhiteSpace([string]$script:Godot.path)
    if (-not $envBlocked) {
        # ── import preflight ──
        if ($NoImport) {
            $importInfo = [pscustomobject]@{
                status = 'SKIPPED'; reason = '-NoImport supplied'; exit_code = $null; duration_s = 0
                log_path = ''; error_line_count = 0; error_sample = @(); timed_out = $false
            }
            Write-Warn 'import:  SKIPPED (-NoImport); scene boot cases may fail on a fresh worktree'
        }
        else {
            Write-Info 'import:  running headless import preflight ...'
            $importInfo = Invoke-ImportPreflight -RunDirPath $script:RunDir
            if ($importInfo.status -eq 'PASS') {
                Write-Ok ("import:  PASS exit={0} duration={1:N1}s warnings/errors={2} log={3}" -f $importInfo.exit_code, $importInfo.duration_s, $importInfo.error_line_count, $importInfo.log_path)
            }
            else {
                Write-Err ("import:  FAIL exit={0} duration={1:N1}s reason={2}" -f $importInfo.exit_code, $importInfo.duration_s, $importInfo.reason)
                Write-Err ("         log: {0}" -f $importInfo.log_path)
                foreach ($line in @($importInfo.error_sample)) { Write-Err ("         " + [string]$line) }
            }
        }
    }

    $importBlocked = (-not $envBlocked) -and ($null -ne $importInfo) -and ($importInfo.status -eq 'FAIL')
    Write-Info ''

    if ($envBlocked -or $importBlocked) {
        $blockedReason = $(if ($envBlocked) { [string]$blockedReason } else { 'import preflight failed: ' + [string]$importInfo.reason })
        # environment blocked: report every selected case as NOT RUN, exit 2
        $results = New-Object System.Collections.ArrayList
        foreach ($c in $selected) {
            $target = $null
            try { $target = Get-CaseTargetInfo -Case $c } catch { $target = [pscustomobject]@{ entry = 'script'; ref = ''; fs_path = ''; exists = $false } }
            [void]$results.Add([ordered]@{
                    id = [string]$c.id; category = [string]$c.category; profile = [string]$c.profile
                    entry = $target.entry; purpose = [string]$c.purpose
                    script = $(if ($target.entry -eq 'script') { $target.ref } else { $null })
                    scene = $(if ($target.entry -in @('scene', 'main')) { $target.ref } else { $null })
                    env = (Get-CaseEnvMap -Case $c); command = ''
                    exit_code = $null; status = 'NOT RUN'; duration_s = 0
                    pass_count = $null; fail_count = $null
                    expected_markers = @($c.expected_markers); marker_ok = $false
                    log_path = ''; reason = $blockedReason; attempts = 0; blocked = $true; error_lines = 0; baseline = $null
                })
        }
        Write-Head 'BLOCKED - all cases NOT RUN'
        Write-ConsoleTableHeader
        foreach ($r in $results) { Write-ConsoleCaseRow -Entry $r }
        $totals = Get-Totals -Results @($results) -DurationSeconds $globalTimer.Elapsed.TotalSeconds
        $baselineStats = $null
        if ($null -ne $script:BaselineData) {
            $baselineStats = Get-BaselineStats -Results @($results) -BaselineData $script:BaselineData
            $totals['known_fail'] = $baselineStats.known_fail
            $totals['new_fail'] = $baselineStats.new_fail
            $totals['baseline_drift'] = $baselineStats.baseline_drift
            $totals['baseline_entries'] = $baselineStats.entries_total
            $totals['baseline_entries_not_selected'] = $baselineStats.entries_not_selected
        }
        else {
            $totals['known_fail'] = $null
            $totals['new_fail'] = $null
            $totals['baseline_drift'] = $null
        }
        $endedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        Write-Info ''
        Write-Err ("TOTALS: total={0} pass={1} fail={2} timeout={3} not_run={4} (environment blocked)" -f $totals.total, $totals.pass, $totals.fail, $totals.timeout, $totals.not_run)
        Write-Err ("BLOCKED: {0}" -f $blockedReason)
        $summaryPath = Join-Path $script:RunDir 'summary.json'
        $reportPath = Join-Path $script:RunDir 'report.md'
        $summaryEntries = @($results)
        Write-SummaryJson -Path $summaryPath -RunIdValue $script:RunId -StartedAt $startedAt -EndedAt $endedAt -GitInfo $gitInfo -GodotVersion $godotVersion -ImportInfo $importInfo -ClearedEnvNames $clearedEnvNames -Filters $filters -Results $summaryEntries -Totals $totals -ExitCode 2 -EnvironmentBlocked $true -BlockedReason $blockedReason -GateName $Gate -BaselineData $script:BaselineData -BaselineStats $baselineStats
        Write-HumanReport -Path $reportPath -RunIdValue $script:RunId -StartedAt $startedAt -EndedAt $endedAt -GitInfo $gitInfo -GodotVersion $godotVersion -ImportInfo $importInfo -ClearedEnvNames $clearedEnvNames -Filters $filters -Results $summaryEntries -Totals $totals -ExitCode 2 -GateName $Gate -BaselineData $script:BaselineData -BaselineStats $baselineStats
        Write-Info ("summary: {0}" -f (Format-RepoRelative $summaryPath))
        Write-Info ("report:  {0}" -f (Format-RepoRelative $reportPath))
        $exitCode = 2
        return $exitCode
    }

    # ── sequential case execution ──
    Write-ConsoleTableHeader
    $caseIndex = 0
    foreach ($c in $selected) {
        $caseIndex++
        $id = [string]$c.id
        $target = $null
        try { $target = Get-CaseTargetInfo -Case $c }
        catch {
            $result = [ordered]@{
                id = $id; category = [string]$c.category; profile = [string]$c.profile; entry = 'script'
                purpose = [string]$c.purpose; script = $null; scene = $null; env = @{}; command = ''
                exit_code = $null; status = 'NOT RUN'; duration_s = 0; pass_count = $null; fail_count = $null
                expected_markers = @($c.expected_markers); marker_ok = $false; log_path = ''
                reason = "invalid matrix case: $($_.Exception.Message)"; attempts = 0; blocked = $false; error_lines = 0; baseline = $null
            }
            [void]$script:CaseResults.Add($result)
            Write-ConsoleCaseRow -Entry $result
            continue
        }
        if ($c.blocked -eq $true) {
            $result = [ordered]@{
                id = $id; category = [string]$c.category; profile = [string]$c.profile; entry = $target.entry
                purpose = [string]$c.purpose
                script = $(if ($target.entry -eq 'script') { $target.ref } else { $null })
                scene = $(if ($target.entry -in @('scene', 'main')) { $target.ref } else { $null })
                env = (Get-CaseEnvMap -Case $c); command = ''
                exit_code = $null; status = 'NOT RUN'; duration_s = 0; pass_count = $null; fail_count = $null
                expected_markers = @($c.expected_markers); marker_ok = $false; log_path = ''
                reason = 'blocked by matrix precondition: ' + [string]$c.blocked_reason; attempts = 0; blocked = $true; error_lines = 0; baseline = $null
            }
            [void]$script:CaseResults.Add($result)
            Write-ConsoleCaseRow -Entry $result
            continue
        }
        if (-not $target.exists) {
            $missingKind = $(if ($target.entry -eq 'script') { 'script' } elseif ($target.entry -eq 'scene') { 'scene' } else { 'main scene' })
            $result = [ordered]@{
                id = $id; category = [string]$c.category; profile = [string]$c.profile; entry = $target.entry
                purpose = [string]$c.purpose
                script = $(if ($target.entry -eq 'script') { $target.ref } else { $null })
                scene = $(if ($target.entry -in @('scene', 'main')) { $target.ref } else { $null })
                env = (Get-CaseEnvMap -Case $c); command = ''
                exit_code = $null; status = 'NOT RUN'; duration_s = 0; pass_count = $null; fail_count = $null
                expected_markers = @($c.expected_markers); marker_ok = $false; log_path = ''
                reason = ("missing {0} (not present in worktree): {1}" -f $missingKind, $target.ref); attempts = 0; blocked = $false; error_lines = 0; baseline = $null
            }
            [void]$script:CaseResults.Add($result)
            Write-ConsoleCaseRow -Entry $result
            continue
        }
        $caseHeader = '[' + $caseIndex + '/' + $selected.Count + '] ' + $id
        if ($script:CiMode) { Write-Host ("RUN " + $caseHeader) } else { Write-Host ("RUN " + $caseHeader) -ForegroundColor DarkGray }
        $result = Invoke-MatrixCase -Case $c -Target $target -RunDirPath $script:RunDir
        if ($null -ne $script:BaselineData) {
            $result['baseline'] = Get-CaseBaselineInfo -Result $result -BaselineData $script:BaselineData
        }
        [void]$script:CaseResults.Add($result)
        Write-ConsoleCaseRow -Entry $result
        if ($result.status -eq 'FAIL' -or $result.status -eq 'TIMEOUT') {
            if (-not [string]::IsNullOrWhiteSpace([string]$result.reason)) { Write-Err ("      {0}: {1}" -f $result.status, $result.reason) }
        }
        if ($null -ne $result.baseline) {
            $tag = 'NEW FAILURE'
            if ($result.baseline.expected) { $tag = 'KNOWN-BASELINE' }
            elseif ($result.baseline.known) { $tag = 'BASELINE DRIFT' }
            $baselineLine = ("      BASELINE: [{0}] {1}" -f $tag, $result.baseline.reason)
            if ($result.baseline.expected) { Write-Warn $baselineLine } else { Write-Err $baselineLine }
        }
    }

    # ── summary / report / exit ──
    $resultsArray = @($script:CaseResults)
    $totals = Get-Totals -Results $resultsArray -DurationSeconds $globalTimer.Elapsed.TotalSeconds
    $baselineStats = $null
    if ($null -ne $script:BaselineData) {
        $baselineStats = Get-BaselineStats -Results $resultsArray -BaselineData $script:BaselineData
        $totals['known_fail'] = $baselineStats.known_fail
        $totals['new_fail'] = $baselineStats.new_fail
        $totals['baseline_drift'] = $baselineStats.baseline_drift
        $totals['baseline_entries'] = $baselineStats.entries_total
        $totals['baseline_entries_not_selected'] = $baselineStats.entries_not_selected
    }
    else {
        $totals['known_fail'] = $null
        $totals['new_fail'] = $null
        $totals['baseline_drift'] = $null
    }
    $exitCode = Get-ExitCodeForTotals -Totals $totals -BaselineMode ($null -ne $script:BaselineData)
    $endedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $summaryPath = Join-Path $script:RunDir 'summary.json'
    $reportPath = Join-Path $script:RunDir 'report.md'
    Write-SummaryJson -Path $summaryPath -RunIdValue $script:RunId -StartedAt $startedAt -EndedAt $endedAt -GitInfo $gitInfo -GodotVersion $godotVersion -ImportInfo $importInfo -ClearedEnvNames $clearedEnvNames -Filters $filters -Results $resultsArray -Totals $totals -ExitCode $exitCode -EnvironmentBlocked $false -BlockedReason '' -GateName $Gate -BaselineData $script:BaselineData -BaselineStats $baselineStats
    Write-HumanReport -Path $reportPath -RunIdValue $script:RunId -StartedAt $startedAt -EndedAt $endedAt -GitInfo $gitInfo -GodotVersion $godotVersion -ImportInfo $importInfo -ClearedEnvNames $clearedEnvNames -Filters $filters -Results $resultsArray -Totals $totals -ExitCode $exitCode -GateName $Gate -BaselineData $script:BaselineData -BaselineStats $baselineStats

    Write-Info ''
    Write-Head '-- TOTALS ------------------------------------------------------'
    Write-Info ("total={0}  pass={1}  fail={2}  timeout={3}  not_run={4} (expected={5} unexpected={6})  duration={7:N1}s" -f $totals.total, $totals.pass, $totals.fail, $totals.timeout, $totals.not_run, $totals.not_run_expected, $totals.not_run_unexpected, $totals.duration_s)
    if ($null -ne $baselineStats) {
        Write-Head '-- BASELINE ----------------------------------------------------'
        Write-Info ("BASELINE CHECK: known_fail={0} new_fail={1} drift={2}" -f $baselineStats.known_fail, $baselineStats.new_fail, $baselineStats.baseline_drift)
        Write-Info ("baseline file: {0} (commit {1}, sha256 {2})" -f $script:BaselineData.path, $script:BaselineData.commit, $script:BaselineData.file_sha256)
        if ($baselineStats.entries_not_selected -gt 0) {
            Write-Info ("baseline entries not selected by filters: {0} of {1} (informational, not drift)" -f $baselineStats.entries_not_selected, $baselineStats.entries_total)
        }
    }
    Write-Info ("summary: {0}" -f (Format-RepoRelative $summaryPath))
    Write-Info ("report:  {0}" -f (Format-RepoRelative $reportPath))
    if ($exitCode -eq 0) {
        if ($null -ne $baselineStats) {
            Write-Ok ("RESULT: BASELINE MATCH - no new failures and no drift (known_fail={0})" -f $baselineStats.known_fail)
        }
        else {
            Write-Ok 'RESULT: ALL RUN CASES PASS'
        }
    }
    else {
        if ($null -ne $baselineStats) {
            Write-Err ("RESULT: BASELINE CHECK FAILED - new_fail={0} drift={1} timeout={2} unexpected_not_run={3}" -f $baselineStats.new_fail, $baselineStats.baseline_drift, $totals.timeout, $totals.not_run_unexpected)
        }
        else {
            Write-Err 'RESULT: FAILURES PRESENT'
        }
    }
}
catch {
    Write-Err ("FATAL: {0}" -f $_.Exception.Message)
    $exitCode = 2
}
$globalTimer.Stop()
return $exitCode
}

$finalExitCode = 2
try {
    $finalExitCode = Invoke-Runner
}
catch {
    Write-Err ("FATAL: {0}" -f $_.Exception.Message)
    $finalExitCode = 2
}
finally {
    # always restore the caller's DSH_* / V17_* environment, even on failure
    if ($script:ClearedEnv -and $script:ClearedEnv.Count -gt 0) { Restore-InheritedTestEnv }
}

exit $finalExitCode
