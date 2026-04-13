# focus.ps1 — Fallback: brings the Windows Terminal window to the foreground.
# The primary mechanism is wt.exe launched directly via the protocol handler.
# This script is only used if the registry is not yet updated to point to wt.exe.

$pidFile = Join-Path $env:TEMP "claude-notification-pid.txt"
if (-not (Test-Path $pidFile)) { exit 0 }

$terminalPid = Get-Content $pidFile -ErrorAction SilentlyContinue
if (-not $terminalPid) { exit 0 }

try {
    $wshell = New-Object -ComObject WScript.Shell
    $wshell.AppActivate([int]$terminalPid)
} catch {}

exit 0
