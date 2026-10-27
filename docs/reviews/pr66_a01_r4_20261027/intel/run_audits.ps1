$ErrorActionPreference = 'Continue'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$taskEngine = 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$env:A01_R4_OWNER_OUT = Join-Path $PSScriptRoot 'owner_lifecycle_audit.json'
$env:A01_R4_SHARE_OUT = Join-Path $PSScriptRoot 'share_continue_audit.json'
$env:A01_R4_SHARE_SAVE_ROOT = Join-Path $PSScriptRoot 'file-save'
Push-Location $taskRoot
try {
    & $taskEngine --headless --path './game_v17' --script (Join-Path $PSScriptRoot 'owner_lifecycle_audit.gd') 1> (Join-Path $PSScriptRoot 'owner_lifecycle_audit.log') 2> (Join-Path $PSScriptRoot 'owner_lifecycle_audit.stderr.log')
    $taskOwnerExit = $LASTEXITCODE
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'owner_lifecycle_exit.txt') -Value $taskOwnerExit
    & $taskEngine --headless --path './game_v17' --script (Join-Path $PSScriptRoot 'share_continue_audit.gd') 1> (Join-Path $PSScriptRoot 'share_continue_audit.log') 2> (Join-Path $PSScriptRoot 'share_continue_audit.stderr.log')
    $taskShareExit = $LASTEXITCODE
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'share_continue_exit.txt') -Value $taskShareExit
    [ordered]@{owner_lifecycle_exit = $taskOwnerExit; share_continue_exit = $taskShareExit} | ConvertTo-Json
} finally {
    Pop-Location
}
