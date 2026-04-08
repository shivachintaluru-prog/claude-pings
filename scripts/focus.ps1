# focus.ps1 — Brings the Claude Code terminal window to the foreground.
# Called by Windows via the claude-focus:// protocol when a toast is clicked.

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Focus {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int SW_RESTORE = 9;
}
"@

$pidFile = Join-Path $env:TEMP "claude-notification-pid.txt"

if (-not (Test-Path $pidFile)) {
    exit 0
}

$terminalPid = Get-Content $pidFile -ErrorAction SilentlyContinue
if (-not $terminalPid) {
    exit 0
}

try {
    $process = Get-Process -Id ([int]$terminalPid) -ErrorAction SilentlyContinue
    if ($process -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Focus]::ShowWindow($process.MainWindowHandle, [Win32Focus]::SW_RESTORE)
        [Win32Focus]::SetForegroundWindow($process.MainWindowHandle)
    }
} catch {
    # Silently exit — process may have closed
}

exit 0
