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

# Find the tab's root process by walking up to WindowsTerminal,
# then picking the process just below it (the tab's shell).
function Find-TabProcessPid {
    $current = Get-Process -Id $PID -ErrorAction SilentlyContinue
    $visited = @{}
    $chain = @()

    # Build the full ancestor chain
    while ($current) {
        if ($visited.ContainsKey($current.Id)) { break }
        $visited[$current.Id] = $true
        $chain += $current
        "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]   Walking: $($current.Id) $($current.ProcessName)" | Out-File -Append $logFile
        try {
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($current.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if (-not $parentId -or $parentId -eq $current.Id) { break }
            $current = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        } catch { break }
    }

    # Find WindowsTerminal in the chain, then pick the process just before it (the tab's root)
    $terminalPid = $null
    $tabPid = $null
    for ($i = 0; $i -lt $chain.Count; $i++) {
        $name = $chain[$i].ProcessName.ToLower()
        if ($name -in @("windowsterminal", "conemu64", "conemu")) {
            $terminalPid = $chain[$i].Id
            # The process just before WindowsTerminal in the chain is the tab's root
            if ($i -gt 0) {
                $tabPid = $chain[$i - 1].Id
            }
            break
        }
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
