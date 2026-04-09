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

$logFile = Join-Path $env:TEMP "claude-notification-focus-debug.log"
$focused = $false

# Strategy 1: AttachConsole to the tab's root process, then focus its console window.
$tabPidFile = Join-Path $env:TEMP "claude-notification-tabpid.txt"
if (Test-Path $tabPidFile) {
    $tabPid = Get-Content $tabPidFile -ErrorAction SilentlyContinue
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tab PID: $tabPid" | Out-File -Append $logFile
    if ($tabPid) {
        try {
            $freeResult = [Win32Focus]::FreeConsole()
            "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FreeConsole: $freeResult" | Out-File -Append $logFile
            $attachResult = [Win32Focus]::AttachConsole([uint32]$tabPid)
            "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] AttachConsole($tabPid): $attachResult" | Out-File -Append $logFile
            if ($attachResult) {
                $hwnd = [Win32Focus]::GetConsoleWindow()
                "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Console HWND: $hwnd, IsWindow: $([Win32Focus]::IsWindow($hwnd))" | Out-File -Append $logFile
                if ($hwnd -ne [IntPtr]::Zero -and [Win32Focus]::IsWindow($hwnd)) {
                    $showResult = [Win32Focus]::ShowWindow($hwnd, [Win32Focus]::SW_SHOW)
                    $focusResult = [Win32Focus]::SetForegroundWindow($hwnd)
                    $focused = $focusResult
                    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ShowWindow: $showResult, SetForegroundWindow: $focusResult" | Out-File -Append $logFile
                }
                [Win32Focus]::FreeConsole() | Out-Null
            }
        } catch {
            "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Strategy 1 error: $_" | Out-File -Append $logFile
        }
    }
}

# Strategy 2: Fallback to parent terminal PID (brings WT window forward, may not switch tab)
if (-not $focused) {
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Falling back to terminal PID" | Out-File -Append $logFile
    $pidFile = Join-Path $env:TEMP "claude-notification-pid.txt"
    if (Test-Path $pidFile) {
        $terminalPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($terminalPid) {
            try {
                $process = Get-Process -Id ([int]$terminalPid) -ErrorAction SilentlyContinue
                if ($process -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
                    [Win32Focus]::ShowWindow($process.MainWindowHandle, [Win32Focus]::SW_RESTORE)
                    [Win32Focus]::SetForegroundWindow($process.MainWindowHandle)
                    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Focused terminal PID $terminalPid" | Out-File -Append $logFile
                }
            } catch {}
        }
    }
}

exit 0
