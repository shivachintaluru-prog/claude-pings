# focus.ps1 — Brings the Claude Code terminal window/tab to the foreground.
# Called by Windows via the claude-focus:// protocol when a toast is clicked.

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Focus {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
}
"@

$focused = $false

# Strategy 1: Use the saved console window handle (per-tab in Windows Terminal)
$hwndFile = Join-Path $env:TEMP "claude-notification-hwnd.txt"
if (Test-Path $hwndFile) {
    $hwndValue = Get-Content $hwndFile -ErrorAction SilentlyContinue
    if ($hwndValue) {
        try {
            $hwnd = [IntPtr]::new([long]$hwndValue)
            if ([Win32Focus]::IsWindow($hwnd)) {
                [Win32Focus]::ShowWindow($hwnd, [Win32Focus]::SW_SHOW)
                $focused = [Win32Focus]::SetForegroundWindow($hwnd)
            }
        } catch {}
    }
}

# Strategy 2: Fallback to parent terminal PID
if (-not $focused) {
    $pidFile = Join-Path $env:TEMP "claude-notification-pid.txt"
    if (Test-Path $pidFile) {
        $terminalPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($terminalPid) {
            try {
                $process = Get-Process -Id ([int]$terminalPid) -ErrorAction SilentlyContinue
                if ($process -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
                    [Win32Focus]::ShowWindow($process.MainWindowHandle, [Win32Focus]::SW_RESTORE)
                    [Win32Focus]::SetForegroundWindow($process.MainWindowHandle)
                }
            } catch {}
        }
    }
}

exit 0
