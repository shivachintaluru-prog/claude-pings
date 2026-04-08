# focus.ps1 — Brings the Claude Code terminal tab to the foreground.
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

    [DllImport("kernel32.dll")]
    public static extern bool FreeConsole();

    [DllImport("kernel32.dll")]
    public static extern bool AttachConsole(uint dwProcessId);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
}
"@

$focused = $false

# Strategy 1: AttachConsole to a process in the tab, then focus its console window.
# This tells Windows Terminal to switch to the correct tab.
$tabPidFile = Join-Path $env:TEMP "claude-notification-tabpid.txt"
if (Test-Path $tabPidFile) {
    $tabPid = Get-Content $tabPidFile -ErrorAction SilentlyContinue
    if ($tabPid) {
        try {
            [Win32Focus]::FreeConsole() | Out-Null
            if ([Win32Focus]::AttachConsole([uint32]$tabPid)) {
                $hwnd = [Win32Focus]::GetConsoleWindow()
                if ($hwnd -ne [IntPtr]::Zero -and [Win32Focus]::IsWindow($hwnd)) {
                    [Win32Focus]::ShowWindow($hwnd, [Win32Focus]::SW_SHOW)
                    $focused = [Win32Focus]::SetForegroundWindow($hwnd)
                }
                [Win32Focus]::FreeConsole() | Out-Null
            }
        } catch {}
    }
}

# Strategy 2: Fallback to parent terminal PID (brings WT window forward, may not switch tab)
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
