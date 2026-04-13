# notify.ps1 — Sends a Windows toast notification when Claude Code needs attention.
# Called by Claude Code's Notification hook.

# Read hook JSON from stdin (well-behaved hook contract)
try {
    if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() | Out-Null }
} catch {}

# Check BurntToast is available
if (-not (Get-Module -ListAvailable -Name BurntToast)) { exit 0 }
Import-Module BurntToast -ErrorAction SilentlyContinue

# Find the Windows Terminal process and determine tab index
$wtProc = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1

if ($wtProc) {
    # Find which tab we're in by walking up the process tree
    $current = Get-Process -Id $PID -ErrorAction SilentlyContinue
    $chain = @()
    $visited = @{}
    while ($current) {
        if ($visited.ContainsKey($current.Id)) { break }
        $visited[$current.Id] = $true
        $chain += $current
        try {
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($current.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if (-not $parentId -or $parentId -eq $current.Id) { break }
            $current = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        } catch { break }
    }

    # Find the process just below WindowsTerminal (the tab's root process)
    $tabRootPid = $null
    for ($i = 0; $i -lt $chain.Count; $i++) {
        if ($chain[$i].Id -eq $wtProc.Id -and $i -gt 0) {
            $tabRootPid = $chain[$i - 1].Id
            break
        }
    }

    # Determine tab index by counting only shell processes (not OpenConsole) among WT's children
    $tabIndex = 0
    if ($tabRootPid) {
        $wtChildren = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($wtProc.Id)" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "OpenConsole.exe" } |
            Sort-Object CreationDate
        for ($i = 0; $i -lt $wtChildren.Count; $i++) {
            if ($wtChildren[$i].ProcessId -eq $tabRootPid) {
                $tabIndex = $i
                break
            }
        }
    }

    # Update the protocol handler to launch wt.exe directly with correct focus-tab syntax
    $commandKey = "HKCU:\Software\Classes\claude-focus\shell\open\command"
    $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
    if ($wtPath) {
        $cmd = "`"$wtPath`" -w 0 ft -t $tabIndex"
        Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $cmd -ErrorAction SilentlyContinue
    }
}

# Send toast notification with protocol activation
try {
    $text1 = New-BTText -Content "Claude Code"
    $text2 = New-BTText -Content "Claude Code needs your attention"
    $binding = New-BTBinding -Children $text1, $text2
    $visual = New-BTVisual -BindingGeneric $binding
    $content = New-BTContent -Visual $visual -Launch "claude-focus://focus" -ActivationType Protocol
    Submit-BTNotification -Content $content
} catch {}

exit 0
