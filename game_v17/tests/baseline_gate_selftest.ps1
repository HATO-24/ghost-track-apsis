#Requires -Version 5.1
<#
.SYNOPSIS
    GHOST TRACK // APSIS - repeatable regression self-test for the fail-closed
    -Baseline gate of run_tests.ps1 (Issue #14 follow-up).

.DESCRIPTION
    Verifies, with real runner invocations, that the baseline gate is FAIL-CLOSED:

      Scenario A  a declared baseline case is forced `blocked: true` -> NOT RUN
                  => strict run must exit 1, report unverified>0 and never claim
                     "BASELINE MATCH".
      Scenario B  declared baseline entries are filtered out by -Only (strict)
                  => exit 1, unselected=7 (8 entries - 1 selected), no "BASELINE MATCH".
      Scenario C  same filtered run + -AllowPartialBaseline (local debugging)
                  => exit 0, output says "BASELINE PARTIAL - NOT a complete baseline
                     verification", summary baseline.complete=false / verified=false.
      Scenario D  optional (-IncludeFullRun): real full strict baseline run
                  => exit 0, complete=true, all 8 entries verified, 4-5 minutes.

    Scenarios A/B/C run in seconds (with -NoImport) plus one Godot process for B/C.
    Scenario D is opt-in because the CI matrix itself already covers the full run.

    Temp files only: matrix/baseline copies and runner results all live under the
    system TEMP directory and are removed on exit. The repository is never modified.

.PARAMETER GodotBin
    Optional Godot executable path, passed through to run_tests.ps1 (-GodotBin).

.PARAMETER NoImport
    Import is SKIPPED by default for speed (the runner is invoked with -NoImport).
    Pass -NoImport:$false to exercise the `--import` preflight in every runner call.

.PARAMETER IncludeFullRun
    Also run Scenario D (full 72-case strict baseline run, ~4-5 minutes). Off by default.

.OUTPUTS
    Prints [PASS]/[FAIL] per assertion and ends with:
      BASELINE GATE SELFTEST RESULT: PASS=n FAIL=m
    Exit code 0 only when every selected scenario/assertion passed.
#>
[CmdletBinding()]
param(
    [string]$GodotBin = '',
    [switch]$NoImport,
    [switch]$IncludeFullRun
)

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Pass = 0
$script:Fail = 0
$script:FailureDetails = New-Object System.Collections.ArrayList
$script:TempRoot = ''

# Import skipped by default (documented); -NoImport:$false exercises the preflight.
$script:SkipImport = $true
if ($PSBoundParameters.ContainsKey('NoImport')) { $script:SkipImport = [bool]$NoImport }

# ── paths ──────────────────────────────────────────────────────────────────
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RunnerPath = Join-Path $script:RepoRoot 'run_tests.ps1'
$script:MatrixPath = Join-Path $script:RepoRoot 'game_v17/tests/probe_matrix.json'
$script:BaselinePath = Join-Path $script:RepoRoot 'game_v17/tests/known_baseline_failures.json'
$script:GodotBinArg = $GodotBin

foreach ($required in @($script:RunnerPath, $script:MatrixPath, $script:BaselinePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        Write-Host ("FATAL: required file not found: {0}" -f $required) -ForegroundColor Red
        exit 1
    }
}

# Locate a PowerShell host to invoke the runner with (works from PS 5.1 and PS 7+).
$script:ShellExe = ''
try { $script:ShellExe = (Get-Process -Id $PID).Path } catch { }
if ([string]::IsNullOrWhiteSpace($script:ShellExe) -or -not (Test-Path -LiteralPath $script:ShellExe)) {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command powershell -ErrorAction SilentlyContinue }
    if (-not $cmd) {
        Write-Host 'FATAL: cannot locate a PowerShell host executable to invoke run_tests.ps1' -ForegroundColor Red
        exit 1
    }
    $script:ShellExe = $cmd.Source
}

$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gt_baseline_selftest_' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '_' + ([guid]::NewGuid().ToString('N').Substring(0, 6)))
New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

# ── tiny assertion harness ─────────────────────────────────────────────────
function Check-True {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        $script:Pass++
        Write-Host ("  [PASS] {0}" -f $Label)
    }
    else {
        $script:Fail++
        $script:FailureDetails.Add($Label) | Out-Null
        Write-Host ("  [FAIL] {0}{1}" -f $Label, $(if ($Detail) { ' | ' + $Detail } else { '' })) -ForegroundColor Red
    }
}

function Check-Contains {
    param([string]$Text, [string]$Needle, [string]$Label)
    Check-True ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) $Label ("missing expected text: '" + $Needle + "'")
}

function Check-NotContains {
    param([string]$Text, [string]$Needle, [string]$Label)
    Check-True ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) $Label ("unexpected text present: '" + $Needle + "'")
}

function Check-Regex {
    param([string]$Text, [string]$Pattern, [string]$Label)
    $m = [regex]::Match($Text, $Pattern)
    Check-True $m.Success $Label ("missing expected regex: '" + $Pattern + "'")
}

function Show-KeyLines {
    param([string]$Text)
    $lines = @(($Text -split "`r?`n") | Where-Object { $_ -match 'BASELINE CHECK|RESULT: BASELINE|BASELINE PARTIAL|NOT VERIFIED|NOT SELECTED|unverified=|unselected=|known_fail=' } | Select-Object -First 10)
    foreach ($line in $lines) { Write-Host ("    | " + $line.Trim()) }
}

function Get-LatestSummaryPath {
    param([string]$ResultsDirPath)
    if (-not (Test-Path -LiteralPath $ResultsDirPath -PathType Container)) { return '' }
    $dirs = @(Get-ChildItem -LiteralPath $ResultsDirPath -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($dirs.Count -eq 0) { return '' }
    $candidate = Join-Path $dirs[0].FullName 'summary.json'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return ''
}

function Invoke-RunnerCli {
    param([string[]]$RunnerArgs, [string]$ResultsDirPath)
    $argsList = @('-NoProfile', '-File', $script:RunnerPath)
    if (-not [string]::IsNullOrWhiteSpace($script:GodotBinArg)) { $argsList += @('-GodotBin', $script:GodotBinArg) }
    $argsList += $RunnerArgs
    if ($script:SkipImport) { $argsList += '-NoImport' }
    $argsList += '-Ci'
    $argsList += @('-ResultsDir', $ResultsDirPath)
    $display = @($argsList | ForEach-Object { if ([string]$_ -match '\s') { '"' + $_ + '"' } else { [string]$_ } }) -join ' '
    Write-Host ("    $ {0} {1}" -f (Split-Path -Leaf $script:ShellExe), $display)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = & $script:ShellExe @argsList 2>&1
    $code = $LASTEXITCODE
    $timer.Stop()
    if ($null -eq $code) { $code = 0 }
    return [pscustomobject]@{
        exit_code  = [int]$code
        output     = (($raw | Out-String))
        duration_s = [math]::Round($timer.Elapsed.TotalSeconds, 1)
    }
}

function New-ScenarioResultsDir {
    param([string]$Name)
    $dir = Join-Path $script:TempRoot ('results_' + $Name)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# ── environment / setup banner ─────────────────────────────────────────────
Write-Host ''
Write-Host 'GHOST TRACK // APSIS - baseline gate fail-closed self-test'
Write-Host ("repo:        {0}" -f $script:RepoRoot)
Write-Host ("runner:      {0}" -f $script:RunnerPath)
Write-Host ("shell:       {0}" -f $script:ShellExe)
Write-Host ("godot:       {0}" -f $(if ($script:GodotBinArg) { $script:GodotBinArg } else { '(runner auto-discovery)' }))
Write-Host ("import:      {0}" -f $(if ($script:SkipImport) { 'SKIPPED in runner calls (-NoImport; fast default)' } else { 'ENABLED (-NoImport:$false)' }))
Write-Host ("temp root:   {0}" -f $script:TempRoot)
Write-Host ("scenarios:   A, B, C{0}" -f $(if ($IncludeFullRun) { ', D (full strict run, 4-5 min)' } else { ' (D skipped: pass -IncludeFullRun to enable)' }))

$finalExit = 0
try {
    # ══════════════════════════════════════════════════════════════════════
    # Scenario A: declared baseline case blocked -> NOT RUN => strict exit 1
    # ══════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '=== Scenario A: declared baseline case blocked (NOT RUN) => strict fail-closed exit 1 ==='
    $scenarioTargetId = 'content.damage_profile_probe'
    $matrixA = Get-Content -LiteralPath $script:MatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $caseFound = $false
    foreach ($case in @($matrixA.cases)) {
        if ([string]$case.id -eq $scenarioTargetId) {
            $case | Add-Member -NotePropertyName blocked -NotePropertyValue $true -Force
            $case | Add-Member -NotePropertyName blocked_reason -NotePropertyValue 'baseline_gate_selftest: forced blocked to verify fail-closed unverified handling' -Force
            $caseFound = $true
        }
    }
    if (-not $caseFound) { throw ("selftest setup: case '{0}' not found in matrix" -f $scenarioTargetId) }
    $matrixAPath = Join-Path $script:TempRoot 'matrix_blocked_baseline_case.json'
    [System.IO.File]::WriteAllText($matrixAPath, (ConvertTo-Json -InputObject $matrixA -Depth 12), $script:Utf8)

    $baselineAll = Get-Content -LiteralPath $script:BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $baselineEntriesA = @($baselineAll.failures | Where-Object { [string]$_.id -eq $scenarioTargetId })
    if ($baselineEntriesA.Count -ne 1) { throw ("selftest setup: baseline entry '{0}' not found" -f $scenarioTargetId) }
    $baselineA = Get-Content -LiteralPath $script:BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $baselineA.failures = $baselineEntriesA
    $baselineAPath = Join-Path $script:TempRoot 'baseline_one_entry.json'
    [System.IO.File]::WriteAllText($baselineAPath, (ConvertTo-Json -InputObject $baselineA -Depth 10), $script:Utf8)

    $resA = Invoke-RunnerCli -RunnerArgs @('-Matrix', $matrixAPath, '-Baseline', $baselineAPath, '-Only', ('^' + [regex]::Escape($scenarioTargetId) + '$')) -ResultsDirPath (New-ScenarioResultsDir 'A')
    Write-Host ("    expected exit=1 actual exit={0} duration={1}s" -f $resA.exit_code, $resA.duration_s)
    Show-KeyLines $resA.output
    Check-True ($resA.exit_code -eq 1) 'A: strict run exits 1 when a declared baseline entry is NOT RUN' ("actual exit=" + $resA.exit_code)
    Check-Regex $resA.output 'unverified=[1-9][0-9]*' 'A: output reports unverified>0'
    Check-Contains $resA.output 'unverified=1' 'A: output reports exactly unverified=1 (single-entry baseline)'
    Check-Contains $resA.output 'NOT RUN' 'A: blocked baseline case is shown as NOT RUN'
    Check-Contains $resA.output 'complete=false' 'A: output reports complete=false'
    Check-NotContains $resA.output 'BASELINE MATCH' 'A: output never claims BASELINE MATCH'
    Check-NotContains $resA.output 'BASELINE PARTIAL' 'A: strict run is not labelled partial'

    # ══════════════════════════════════════════════════════════════════════
    # Scenario B: filtered strict run => unselected declared entries fail the gate
    # ══════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '=== Scenario B: strict run with 7/8 declared baseline entries filtered out => exit 1 ==='
    $resB = Invoke-RunnerCli -RunnerArgs @('-Baseline', $script:BaselinePath, '-Only', '^unit\.save_probe$') -ResultsDirPath (New-ScenarioResultsDir 'B')
    Write-Host ("    expected exit=1 actual exit={0} duration={1}s" -f $resB.exit_code, $resB.duration_s)
    Show-KeyLines $resB.output
    Check-True ($resB.exit_code -eq 1) 'B: strict filtered run exits 1 when declared baseline entries are unselected' ("actual exit=" + $resB.exit_code)
    Check-Contains $resB.output 'unselected=7' 'B: output reports unselected=7'
    Check-Contains $resB.output 'BASELINE CHECK FAILED' 'B: output reports BASELINE CHECK FAILED'
    Check-Contains $resB.output 'NOT SELECTED' 'B: unselected baseline entries are listed explicitly'
    Check-NotContains $resB.output 'BASELINE MATCH' 'B: output never claims BASELINE MATCH'
    Check-NotContains $resB.output 'BASELINE PARTIAL' 'B: strict run is not labelled partial'

    # ══════════════════════════════════════════════════════════════════════
    # Scenario C: filtered run + -AllowPartialBaseline (local debug escape hatch)
    # ══════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '=== Scenario C: filtered run + -AllowPartialBaseline => exit 0 but explicitly PARTIAL ==='
    $resultsC = New-ScenarioResultsDir 'C'
    $resC = Invoke-RunnerCli -RunnerArgs @('-Baseline', $script:BaselinePath, '-Only', '^unit\.save_probe$', '-AllowPartialBaseline') -ResultsDirPath $resultsC
    Write-Host ("    expected exit=0 actual exit={0} duration={1}s" -f $resC.exit_code, $resC.duration_s)
    Show-KeyLines $resC.output
    Check-True ($resC.exit_code -eq 0) 'C: -AllowPartialBaseline allows exit 0 for a clean selected subset' ("actual exit=" + $resC.exit_code)
    Check-Contains $resC.output 'BASELINE PARTIAL' 'C: output is explicitly labelled BASELINE PARTIAL'
    Check-Contains $resC.output 'NOT a complete baseline verification' 'C: output states it is NOT a complete verification'
    Check-NotContains $resC.output 'BASELINE MATCH' 'C: partial run never claims BASELINE MATCH'
    $summaryCPath = Get-LatestSummaryPath -ResultsDirPath $resultsC
    Check-True (-not [string]::IsNullOrWhiteSpace($summaryCPath)) 'C: summary.json was written for the partial run'
    if (-not [string]::IsNullOrWhiteSpace($summaryCPath)) {
        $summaryC = Get-Content -LiteralPath $summaryCPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Check-True (-not [bool]$summaryC.baseline.complete) 'C: summary baseline.complete=false' ("actual=" + $summaryC.baseline.complete)
        Check-True (-not [bool]$summaryC.baseline.verified) 'C: summary baseline.verified=false' ("actual=" + $summaryC.baseline.verified)
        Check-True ([bool]$summaryC.baseline.partial) 'C: summary baseline.partial=true' ("actual=" + $summaryC.baseline.partial)
        Check-True ([int]$summaryC.totals.baseline_unselected -gt 0) 'C: summary totals.baseline_unselected>0' ("actual=" + $summaryC.totals.baseline_unselected)
        Check-True ([int]$summaryC.totals.baseline_unverified -ge 0) 'C: summary totals.baseline_unverified present' ("actual=" + $summaryC.totals.baseline_unverified)
        Check-True (-not [bool]$summaryC.totals.baseline_complete) 'C: summary totals.baseline_complete=false' ("actual=" + $summaryC.totals.baseline_complete)
    }

    # ══════════════════════════════════════════════════════════════════════
    # Scenario D (optional): real full strict baseline run => complete verification
    # ══════════════════════════════════════════════════════════════════════
    if ($IncludeFullRun) {
        Write-Host ''
        Write-Host '=== Scenario D (opt-in): full strict baseline run => exit 0 with complete=true ==='
        $resultsD = New-ScenarioResultsDir 'D'
        $resD = Invoke-RunnerCli -RunnerArgs @('-Baseline', $script:BaselinePath) -ResultsDirPath $resultsD
        Write-Host ("    expected exit=0 actual exit={0} duration={1}s" -f $resD.exit_code, $resD.duration_s)
        Show-KeyLines $resD.output
        Check-True ($resD.exit_code -eq 0) 'D: full strict baseline run exits 0' ("actual exit=" + $resD.exit_code)
        Check-Contains $resD.output 'known_fail=8 new_fail=0 drift=0 unverified=0 unselected=0 complete=true' 'D: BASELINE CHECK reports complete verification'
        Check-Contains $resD.output 'all 8 baseline entries executed as expected FAIL with matching counts' 'D: explicit all-entries-verified result line'
        Check-NotContains $resD.output 'BASELINE PARTIAL' 'D: strict full run is not labelled partial'
        $summaryDPath = Get-LatestSummaryPath -ResultsDirPath $resultsD
        Check-True (-not [string]::IsNullOrWhiteSpace($summaryDPath)) 'D: summary.json was written for the full run'
        if (-not [string]::IsNullOrWhiteSpace($summaryDPath)) {
            $summaryD = Get-Content -LiteralPath $summaryDPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Check-True ([bool]$summaryD.baseline.complete) 'D: summary baseline.complete=true' ("actual=" + $summaryD.baseline.complete)
            Check-True ([bool]$summaryD.baseline.verified) 'D: summary baseline.verified=true' ("actual=" + $summaryD.baseline.verified)
            Check-True ([int]$summaryD.totals.baseline_unverified -eq 0) 'D: summary totals.baseline_unverified=0' ("actual=" + $summaryD.totals.baseline_unverified)
            Check-True ([int]$summaryD.totals.baseline_unselected -eq 0) 'D: summary totals.baseline_unselected=0' ("actual=" + $summaryD.totals.baseline_unselected)
            Check-True ([bool]$summaryD.totals.baseline_complete) 'D: summary totals.baseline_complete=true' ("actual=" + $summaryD.totals.baseline_complete)
        }
    }
}
catch {
    $script:Fail++
    $script:FailureDetails.Add(("FATAL: " + $_.Exception.Message)) | Out-Null
    Write-Host ("  [FAIL] selftest aborted: {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($script:TempRoot) -and (Test-Path -LiteralPath $script:TempRoot)) {
        try { Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# ── final result ───────────────────────────────────────────────────────────
Write-Host ''
if ($script:Fail -gt 0) {
    Write-Host 'Failed assertions:'
    foreach ($detail in @($script:FailureDetails)) { Write-Host ("  - {0}" -f $detail) -ForegroundColor Red }
}
$total = $script:Pass + $script:Fail
Write-Host ("BASELINE GATE SELFTEST RESULT: PASS={0} FAIL={1} (assertions={2})" -f $script:Pass, $script:Fail, $total)
if ($script:Fail -gt 0) { $finalExit = 1 }
exit $finalExit
