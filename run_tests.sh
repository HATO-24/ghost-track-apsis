#!/usr/bin/env sh
# GHOST TRACK // APSIS · thin cross-platform wrapper for run_tests.ps1.
#
# Requires PowerShell 7+ (`pwsh`) on PATH. Godot discovery is unchanged:
#   -GodotBin <path> -> $GODOT_BIN -> tools/godot/Godot*console.exe -> godot/godot4 on PATH.
#
# Examples:
#   ./run_tests.sh -List
#   ./run_tests.sh -Category profile
#   ./run_tests.sh -Ci
#   GODOT_BIN=/usr/local/bin/godot ./run_tests.sh -Ci
#
# On Windows use PowerShell directly instead:  pwsh -File .\run_tests.ps1 -List
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v pwsh >/dev/null 2>&1; then
    echo "run_tests.sh: PowerShell 7+ (pwsh) is required but was not found on PATH." >&2
    echo "Install PowerShell: https://learn.microsoft.com/powershell/scripting/install/installing-powershell" >&2
    exit 2
fi

exec pwsh -NoProfile -File "$SCRIPT_DIR/run_tests.ps1" "$@"
