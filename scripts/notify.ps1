# notify.ps1 — Sends a Windows toast notification when Claude Code needs attention.
# Called by Claude Code's Notification hook.

$logFile = Join-Path $env:TEMP "claude-notification-debug.log"
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] notify.ps1 started" | Out-File -Append $logFile

# Read hook JSON from stdin (well-behaved hook contract)
$hookInput = $null
try {
    if (-not [Console]::IsInputRedirected) {
        $hookInput = $null
    } else {
        $hookInput = [Console]::In.ReadToEnd()
    }
} catch {
    $hookInput = $null
}

# Check BurntToast is available
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    exit 0
}

Import-Module BurntToast -ErrorAction SilentlyContinue
if (-not (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue)) {
    exit 0
}

# Get the console window handle for this specific tab.
# In Windows Terminal, each tab has its own console — GetConsoleWindow() returns that tab's handle.
Add-Type -Name ConsoleAPI -Namespace Win32 -MemberDefinition @"
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@

$consoleHwnd = [Win32.ConsoleAPI]::GetConsoleWindow()
"[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Console HWND: $consoleHwnd" | Out-File -Append $logFile

# Save console window handle for focus.ps1
$hwndFile = Join-Path $env:TEMP "claude-notification-hwnd.txt"
$consoleHwnd.ToInt64().ToString() | Out-File -FilePath $hwndFile -NoNewline -Encoding ascii

# Also save parent terminal PID as fallback
function Find-TerminalProcess {
    $current = Get-Process -Id $PID -ErrorAction SilentlyContinue
    $visited = @{}
    while ($current) {
        if ($visited.ContainsKey($current.Id)) { break }
        $visited[$current.Id] = $true
        if ($current.MainWindowHandle -ne [IntPtr]::Zero) { return $current }
        try {
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($current.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if (-not $parentId -or $parentId -eq $current.Id) { break }
            $current = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        } catch { break }
    }
    $terminalNames = @("WindowsTerminal", "cmd", "powershell", "pwsh")
    foreach ($name in $terminalNames) {
        $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        if ($proc) { return $proc }
    }
    return $null
}
$terminal = Find-TerminalProcess
if ($terminal) {
    $terminal.Id | Out-File -FilePath (Join-Path $env:TEMP "claude-notification-pid.txt") -NoNewline -Encoding ascii
}

# Send toast notification with protocol activation on click
try {
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Sending toast..." | Out-File -Append $logFile

    $text1 = New-BTText -Content "Claude Code"
    $text2 = New-BTText -Content "Claude Code needs your attention"
    $binding = New-BTBinding -Children $text1, $text2
    $visual = New-BTVisual -BindingGeneric $binding
    $content = New-BTContent -Visual $visual -Launch "claude-focus://focus" -ActivationType Protocol
    Submit-BTNotification -Content $content

    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Toast sent successfully" | Out-File -Append $logFile
} catch {
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Toast failed: $_" | Out-File -Append $logFile
}

exit 0
