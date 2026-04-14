# notify.ps1 — Sends a Windows toast notification when Claude Code needs attention.
# Called by Claude Code's Notification and Stop hooks.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $scriptDir
$dataDir = Join-Path $rootDir "data"

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

# Log hook invocations (kept for diagnosing duplicate notifications)
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] EVENT=$eventName" | Out-File -Append (Join-Path $env:TEMP "claude-notification-debug.log")

# Debounce Stop events — suppress if one was sent less than 5 seconds ago.
if ($eventName -eq "stop") {
    $lockFile = Join-Path $env:TEMP "claude-notification-stop.lock"
    if (Test-Path $lockFile) {
        try {
            $lastStop = [DateTime]::Parse((Get-Content $lockFile -ErrorAction SilentlyContinue))
            if (((Get-Date) - $lastStop).TotalSeconds -lt 5) { exit 0 }
        } catch {}
    }
    (Get-Date).ToString("o") | Out-File $lockFile -NoNewline -Encoding ascii
}

# Check BurntToast is available
if (-not (Get-Module -ListAvailable -Name BurntToast)) { exit 0 }
Import-Module BurntToast -ErrorAction SilentlyContinue

# Pick a context-aware message
$message = "Claude Code needs your attention"
$messagesFile = Join-Path $dataDir "messages.json"
if (Test-Path $messagesFile) {
    try {
        $messages = Get-Content $messagesFile -Raw -Encoding UTF8 | ConvertFrom-Json
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
        $tips = Get-Content $tipsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $meta = if (Test-Path $metaFile) { Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { @{ seenIndices = @() } }
        $seen = @($meta.seenIndices)
        if ($seen.Count -ge $tips.Count) { $seen = @() }
        $unseen = @(0..($tips.Count - 1) | Where-Object { $_ -notin $seen })
        if ($unseen.Count -gt 0) {
            $idx = $unseen | Get-Random
            $tipLine = $tips[$idx]
            $seen += $idx
            $meta.seenIndices = $seen
            $meta | ConvertTo-Json | Out-File $metaFile -Encoding utf8
        }
    } catch {}
}

# Build notification body
$body = $message
if ($tipLine) {
    $body = "$message`n`nTip: $tipLine"
}

# Find Windows Terminal tab index using a single bulk WMI query (fast)
$wtProc = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1

if ($wtProc) {
    # Single WMI query to get ALL process parent relationships
    $allProcs = @{}
    Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction SilentlyContinue | ForEach-Object {
        $allProcs[$_.ProcessId] = $_
    }

    # Walk up from $PID using in-memory map (instant)
    $tabRootPid = $null
    $currentPid = $PID
    $visited = @{}
    while ($currentPid -and -not $visited.ContainsKey($currentPid)) {
        $visited[$currentPid] = $true
        $proc = $allProcs[$currentPid]
        if (-not $proc) { break }
        if ($proc.ParentProcessId -eq $wtProc.Id) {
            $tabRootPid = $currentPid
            break
        }
        $currentPid = $proc.ParentProcessId
    }

    # Determine tab index from WT's children
    $tabIndex = 0
    if ($tabRootPid) {
        $wtChildren = $allProcs.Values | Where-Object {
            $_.ParentProcessId -eq $wtProc.Id -and $_.Name -ne "OpenConsole.exe"
        } | Sort-Object CreationDate
        for ($i = 0; $i -lt $wtChildren.Count; $i++) {
            if ($wtChildren[$i].ProcessId -eq $tabRootPid) {
                $tabIndex = $i
                break
            }
        }
    }

    # Update protocol handler
    $commandKey = "HKCU:\Software\Classes\claude-focus\shell\open\command"
    $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
    if ($wtPath) {
        $cmd = "`"$wtPath`" -w 0 ft -t $tabIndex"
        Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $cmd -ErrorAction SilentlyContinue
    }
}

# Send toast notification with Claude icon and protocol activation
$iconPath = Join-Path $rootDir "assets\claude-icon.ico"
try {
    $text1 = New-BTText -Content "Claude Code"
    $text2 = New-BTText -Content $body
    $toastParams = @{}
    if (Test-Path $iconPath) {
        $image = New-BTImage -Source $iconPath -AppLogoOverride
        $binding = New-BTBinding -Children $text1, $text2 -AppLogoOverride $image
    } else {
        $binding = New-BTBinding -Children $text1, $text2
    }
    $visual = New-BTVisual -BindingGeneric $binding
    $content = New-BTContent -Visual $visual -Launch "claude-focus://focus" -ActivationType Protocol
    Submit-BTNotification -Content $content
} catch {}

exit 0
