# notify.ps1 — Sends a Windows toast notification when Claude Code needs attention.
# Called by Claude Code's Notification hook.

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

# Find the parent terminal process.
# Walk up the process tree from this script's process to find the terminal window.
function Find-TerminalProcess {
    $current = Get-Process -Id $PID -ErrorAction SilentlyContinue
    $visited = @{}

    while ($current) {
        if ($visited.ContainsKey($current.Id)) { break }
        $visited[$current.Id] = $true

        # Check if this process has a visible window
        if ($current.MainWindowHandle -ne [IntPtr]::Zero) {
            return $current
        }

        # Walk up to parent
        try {
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($current.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if (-not $parentId -or $parentId -eq $current.Id) { break }
            $current = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        } catch {
            break
        }
    }

    # Fallback: look for Windows Terminal or common terminal hosts
    $terminalNames = @("WindowsTerminal", "cmd", "powershell", "pwsh", "ConEmu64", "ConEmuC64")
    foreach ($name in $terminalNames) {
        $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        if ($proc) { return $proc }
    }

    return $null
}

$terminal = Find-TerminalProcess

# Save terminal PID for focus.ps1
if ($terminal) {
    $terminal.Id | Out-File -FilePath (Join-Path $env:TEMP "claude-notification-pid.txt") -NoNewline -Encoding ascii
}

# Send toast notification with protocol activation
$toastParams = @{
    Text = "Claude Code", "Claude Code needs your attention"
    AppLogo = $null
    ActivationType = "Protocol"
    ActivationArgument = "claude-focus://focus"
}

try {
    New-BurntToastNotification @toastParams
} catch {
    # Silently fail — don't block the hook
}

exit 0
