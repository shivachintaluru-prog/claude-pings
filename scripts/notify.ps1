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

# Find a process in the terminal tab's console session.
# Walk up the process tree to find a shell or node process that lives in the tab.
# focus.ps1 will use AttachConsole(pid) to find and focus the correct tab.
function Find-TabProcessPid {
    $current = Get-Process -Id $PID -ErrorAction SilentlyContinue
    $visited = @{}
    $tabPid = $null
    $terminalPid = $null

    while ($current) {
        if ($visited.ContainsKey($current.Id)) { break }
        $visited[$current.Id] = $true

        $name = $current.ProcessName.ToLower()
        "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]   Walking: $($current.Id) $($current.ProcessName)" | Out-File -Append $logFile

        # Save the first shell/node process as the tab process
        if (-not $tabPid -and $name -in @("bash", "pwsh", "powershell", "cmd", "node")) {
            $tabPid = $current.Id
        }

        # Save the terminal window process
        if ($current.MainWindowHandle -ne [IntPtr]::Zero -and $name -in @("windowsterminal", "conemu64", "conemu")) {
            $terminalPid = $current.Id
        }

        try {
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($current.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if (-not $parentId -or $parentId -eq $current.Id) { break }
            $current = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        } catch { break }
    }

    return @{ TabPid = $tabPid; TerminalPid = $terminalPid }
}

$pids = Find-TabProcessPid
"[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tab PID: $($pids.TabPid), Terminal PID: $($pids.TerminalPid)" | Out-File -Append $logFile

# Save both PIDs for focus.ps1
if ($pids.TabPid) {
    $pids.TabPid | Out-File -FilePath (Join-Path $env:TEMP "claude-notification-tabpid.txt") -NoNewline -Encoding ascii
}
if ($pids.TerminalPid) {
    $pids.TerminalPid | Out-File -FilePath (Join-Path $env:TEMP "claude-notification-pid.txt") -NoNewline -Encoding ascii
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
