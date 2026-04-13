# notify.ps1 — Sends a Windows toast notification when Claude Code needs attention.
# Called by Claude Code's Notification and Stop hooks.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$dataDir = Join-Path (Split-Path -Parent $scriptDir) "data"

# Read hook JSON from stdin to determine event type
$eventName = "notification"
try {
    if ([Console]::IsInputRedirected) {
        $json = [Console]::In.ReadToEnd()
        if ($json) {
            $hook = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($hook.hook_event_name) {
                $eventName = $hook.hook_event_name.ToLower()
            }
        }
    }
} catch {}

# Check BurntToast is available
if (-not (Get-Module -ListAvailable -Name BurntToast)) { exit 0 }
Import-Module BurntToast -ErrorAction SilentlyContinue

# Pick a context-aware message
$message = "Claude Code needs your attention"
$messagesFile = Join-Path $dataDir "messages.json"
if (Test-Path $messagesFile) {
    try {
        $messages = Get-Content $messagesFile -Raw | ConvertFrom-Json
        $key = if ($eventName -eq "stop") { "stop" } else { "notification" }
        $pool = $messages.$key
        if ($pool -and $pool.Count -gt 0) {
            $message = $pool | Get-Random
        }
    } catch {}
}

# Maybe add a tip (~20% chance)
$tipLine = $null
$tipsFile = Join-Path $dataDir "tips.json"
$metaFile = Join-Path $dataDir "tips-meta.json"
if ((Get-Random -Minimum 1 -Maximum 6) -eq 1 -and (Test-Path $tipsFile)) {
    try {
        $tips = Get-Content $tipsFile -Raw | ConvertFrom-Json
        $meta = if (Test-Path $metaFile) { Get-Content $metaFile -Raw | ConvertFrom-Json } else { @{ seenIndices = @() } }
        $seen = @($meta.seenIndices)

        # Reset if all tips have been seen
        if ($seen.Count -ge $tips.Count) { $seen = @() }

        # Pick a random unseen tip
        $unseen = @(0..($tips.Count - 1) | Where-Object { $_ -notin $seen })
        if ($unseen.Count -gt 0) {
            $idx = $unseen | Get-Random
            $tipLine = $tips[$idx]
            $seen += $idx

            # Update meta
            $meta.seenIndices = $seen
            $meta | ConvertTo-Json | Out-File $metaFile -Encoding utf8
        }
    } catch {}
}

# Build notification body
$body = $message
if ($tipLine) {
    $body = "$message`n`n$([char]0x1F4A1) $tipLine"
}

# Find Windows Terminal and update protocol handler for click-to-focus
$wtProc = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1

if ($wtProc) {
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

    $tabRootPid = $null
    for ($i = 0; $i -lt $chain.Count; $i++) {
        if ($chain[$i].Id -eq $wtProc.Id -and $i -gt 0) {
            $tabRootPid = $chain[$i - 1].Id
            break
        }
    }

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

    $commandKey = "HKCU:\Software\Classes\claude-focus\shell\open\command"
    $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
    if ($wtPath) {
        $cmd = "`"$wtPath`" -w 0 ft -t $tabIndex"
        Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $cmd -ErrorAction SilentlyContinue
    }
}

# Send toast notification
try {
    $text1 = New-BTText -Content "Claude Code"
    $text2 = New-BTText -Content $body
    $binding = New-BTBinding -Children $text1, $text2
    $visual = New-BTVisual -BindingGeneric $binding
    $content = New-BTContent -Visual $visual -Launch "claude-focus://focus" -ActivationType Protocol
    Submit-BTNotification -Content $content
} catch {}

exit 0
