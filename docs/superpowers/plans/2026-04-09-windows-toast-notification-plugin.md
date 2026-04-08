# Windows Toast Notification Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that sends a Windows toast notification whenever Claude is waiting for user input, with click-to-focus on the terminal.

**Architecture:** A Claude Code plugin with a `Notification` hook that runs a PowerShell script. The script uses BurntToast to send a toast with protocol activation. A registered `claude-focus://` protocol handler focuses the terminal window when the toast is clicked.

**Tech Stack:** PowerShell 5.1+, BurntToast module, Win32 P/Invoke (user32.dll), Windows Registry (HKCU)

**Spec:** `docs/superpowers/specs/2026-04-09-windows-toast-notification-plugin-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/focus.ps1` | Create | Win32 interop — reads PID from temp file, focuses the terminal window |
| `scripts/notify.ps1` | Create | Hook handler — captures terminal PID, sends BurntToast toast with protocol activation |
| `register-protocol.ps1` | Create | One-time setup — registers `claude-focus://` protocol in HKCU registry |
| `plugin.json` | Create | Plugin manifest — declares the Notification hook |
| `README.md` | Create | Setup instructions and troubleshooting |

---

### Task 1: Create `scripts/focus.ps1` — Win32 focus helper

**Files:**
- Create: `scripts/focus.ps1`

This script is launched by Windows when the user clicks the toast notification. It reads the terminal PID from a temp file and brings that window to the foreground.

- [ ] **Step 1: Create `scripts/focus.ps1`**

```powershell
# focus.ps1 — Brings the Claude Code terminal window to the foreground.
# Called by Windows via the claude-focus:// protocol when a toast is clicked.

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Focus {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int SW_RESTORE = 9;
}
"@

$pidFile = Join-Path $env:TEMP "claude-notification-pid.txt"

if (-not (Test-Path $pidFile)) {
    exit 0
}

$terminalPid = Get-Content $pidFile -ErrorAction SilentlyContinue
if (-not $terminalPid) {
    exit 0
}

try {
    $process = Get-Process -Id ([int]$terminalPid) -ErrorAction SilentlyContinue
    if ($process -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Focus]::ShowWindow($process.MainWindowHandle, [Win32Focus]::SW_RESTORE)
        [Win32Focus]::SetForegroundWindow($process.MainWindowHandle)
    }
} catch {
    # Silently exit — process may have closed
}

exit 0
```

- [ ] **Step 2: Manually test `focus.ps1`**

Open a second terminal. In the first terminal, find its PID:

```powershell
# In the terminal you want to focus, get the terminal PID:
# For Windows Terminal:
(Get-Process -Name WindowsTerminal | Select-Object -First 1).Id | Out-File "$env:TEMP\claude-notification-pid.txt"
# OR for cmd/pwsh:
$PID | Out-File "$env:TEMP\claude-notification-pid.txt"
```

Switch to the second terminal and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File scripts/focus.ps1
```

Expected: The first terminal comes to the foreground.

- [ ] **Step 3: Commit**

```bash
git add scripts/focus.ps1
git commit -m "feat: add focus.ps1 — Win32 window focus helper"
```

---

### Task 2: Create `scripts/notify.ps1` — Toast notification sender

**Files:**
- Create: `scripts/notify.ps1`

This script is the hook handler. It captures the parent terminal PID, writes it to a temp file, and sends a toast notification via BurntToast with protocol activation.

- [ ] **Step 1: Create `scripts/notify.ps1`**

```powershell
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
```

- [ ] **Step 2: Manually test `notify.ps1`**

Ensure BurntToast is installed:

```powershell
Install-Module BurntToast -Scope CurrentUser -Force
```

Run the script directly:

```powershell
echo '{"hook_event_name":"Notification"}' | powershell.exe -ExecutionPolicy Bypass -File scripts/notify.ps1
```

Expected: A Windows toast notification appears with title "Claude Code" and body "Claude Code needs your attention". Check that `$env:TEMP\claude-notification-pid.txt` was created and contains a PID.

- [ ] **Step 3: Commit**

```bash
git add scripts/notify.ps1
git commit -m "feat: add notify.ps1 — BurntToast notification sender"
```

---

### Task 3: Create `register-protocol.ps1` — One-time protocol registration

**Files:**
- Create: `register-protocol.ps1`

This script registers the `claude-focus://` custom protocol in the current user's registry. It only needs to be run once per machine. No admin rights needed (HKCU).

- [ ] **Step 1: Create `register-protocol.ps1`**

```powershell
# register-protocol.ps1 — Registers the claude-focus:// protocol handler.
# Run once per machine. No admin rights needed (writes to HKCU).

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$focusScript = Join-Path $scriptDir "scripts\focus.ps1"

if (-not (Test-Path $focusScript)) {
    Write-Error "Could not find focus.ps1 at: $focusScript"
    Write-Error "Run this script from the plugin root directory."
    exit 1
}

$protocolKey = "HKCU:\Software\Classes\claude-focus"
$commandKey = "$protocolKey\shell\open\command"

# Create registry keys
New-Item -Path $commandKey -Force | Out-Null

# Set protocol values
Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:Claude Focus Protocol"
Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""

# Set command — launches focus.ps1 hidden
$command = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$focusScript`""
Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $command

Write-Host "claude-focus:// protocol registered successfully." -ForegroundColor Green
Write-Host "Protocol handler points to: $focusScript"
Write-Host ""
Write-Host "To verify, run:" -ForegroundColor Yellow
Write-Host "  Get-ItemProperty 'HKCU:\Software\Classes\claude-focus\shell\open\command'"
```

- [ ] **Step 2: Run the registration script**

```powershell
powershell.exe -ExecutionPolicy Bypass -File register-protocol.ps1
```

Expected output:
```
claude-focus:// protocol registered successfully.
Protocol handler points to: C:\Users\...\scripts\focus.ps1
```

- [ ] **Step 3: Verify the registry entry**

```powershell
Get-ItemProperty "HKCU:\Software\Classes\claude-focus\shell\open\command"
```

Expected: The `(Default)` value should contain the full path to `focus.ps1`.

- [ ] **Step 4: End-to-end test — toast click focuses window**

1. Open two terminals
2. In terminal A, write its PID to the temp file:
   ```powershell
   (Get-Process -Name WindowsTerminal | Select-Object -First 1).Id | Out-File "$env:TEMP\claude-notification-pid.txt" -NoNewline -Encoding ascii
   ```
3. In terminal B, send a toast:
   ```powershell
   echo '{"hook_event_name":"Notification"}' | powershell.exe -ExecutionPolicy Bypass -File scripts/notify.ps1
   ```
4. Click the toast notification

Expected: Terminal A comes to the foreground.

- [ ] **Step 5: Commit**

```bash
git add register-protocol.ps1
git commit -m "feat: add register-protocol.ps1 — one-time claude-focus:// setup"
```

---

### Task 4: Create `plugin.json` — Plugin manifest

**Files:**
- Create: `plugin.json`

- [ ] **Step 1: Create `plugin.json`**

```json
{
  "name": "claude-notification",
  "description": "Windows toast notifications when Claude Code needs your attention",
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"%PLUGIN_DIR%/scripts/notify.ps1\""
          }
        ]
      }
    ]
  }
}
```

> **Note:** The `%PLUGIN_DIR%` placeholder may not be supported by Claude Code. During testing (Task 5), verify whether the hook resolves the path correctly. If not, the command must use an absolute path, and `register-protocol.ps1` should also patch `plugin.json` with the correct path. Alternatively, use a relative path if hooks run from the plugin directory.

- [ ] **Step 2: Commit**

```bash
git add plugin.json
git commit -m "feat: add plugin.json — plugin manifest with Notification hook"
```

---

### Task 5: Integration test — register plugin and verify end-to-end

**Files:**
- No new files — testing the assembled plugin

- [ ] **Step 1: Verify the hook command path resolves correctly**

Register the plugin in Claude Code. Then check how hooks are resolved:

```bash
claude /hooks
```

Look at the `Notification` hook entry. Verify the command path to `notify.ps1` is correct and absolute. If `%PLUGIN_DIR%` was not expanded, update `plugin.json` to use the absolute path to `scripts/notify.ps1` instead.

- [ ] **Step 2: Trigger a notification via Claude Code**

Start a Claude Code session and issue a command that requires tool permission (e.g., ask Claude to run a bash command). When Claude pauses for permission, a toast should appear.

Expected: Toast notification with "Claude Code" / "Claude Code needs your attention".

- [ ] **Step 3: Test click-to-focus**

While the toast is visible, switch to a different application. Click the toast.

Expected: The terminal running Claude Code comes to the foreground.

- [ ] **Step 4: Test silent failure when BurntToast is missing**

Temporarily unload BurntToast:

```powershell
Remove-Module BurntToast -Force -ErrorAction SilentlyContinue
```

Trigger another notification event. Verify Claude Code is not blocked — the hook should exit silently.

Re-import after testing:

```powershell
Import-Module BurntToast
```

- [ ] **Step 5: Commit any path fixes from step 1**

If `plugin.json` needed changes:

```bash
git add plugin.json
git commit -m "fix: use absolute path in plugin.json hook command"
```

---

### Task 6: Create `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

```markdown
# Claude Code Notification Plugin

Windows toast notifications when Claude Code needs your attention. Clicking the notification brings the terminal to the foreground.

## Prerequisites

- Windows 10/11
- PowerShell 5.1+ (ships with Windows)

## Setup

### 1. Install BurntToast

```powershell
Install-Module BurntToast -Scope CurrentUser -Force
```

### 2. Register the click-to-focus protocol

Run once from the plugin directory:

```powershell
powershell.exe -ExecutionPolicy Bypass -File register-protocol.ps1
```

### 3. Register the plugin in Claude Code

Add this plugin to your Claude Code configuration.

## How It Works

When Claude Code finishes working and is waiting for your input, a Windows toast notification appears. Clicking it brings the Claude Code terminal window to the foreground.

## Troubleshooting

**No notification appears:**
- Verify BurntToast is installed: `Get-Module -ListAvailable -Name BurntToast`
- Check Windows notification settings — ensure notifications are enabled for PowerShell
- Run `notify.ps1` manually: `echo '{}' | powershell.exe -ExecutionPolicy Bypass -File scripts/notify.ps1`

**Clicking the notification does nothing:**
- Verify the protocol is registered: `Get-ItemProperty "HKCU:\Software\Classes\claude-focus\shell\open\command"`
- Re-run `register-protocol.ps1` if the plugin was moved to a different directory

**Notifications are blocked by execution policy:**
- The plugin uses `-ExecutionPolicy Bypass` for its scripts. If your organization enforces stricter policies, talk to your IT admin.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with setup and troubleshooting instructions"
```

---

### Task 7: Final cleanup and verification

- [ ] **Step 1: Verify all files are committed**

```bash
git status
git log --oneline
```

Expected: Clean working tree with 6 commits (one per task).

- [ ] **Step 2: Full end-to-end test**

1. Start a fresh Claude Code session
2. Give Claude a task that requires tool approval
3. Tab away from the terminal
4. Wait for the toast notification
5. Click it
6. Verify the terminal comes to the foreground

- [ ] **Step 3: Test on a clean machine (optional)**

If a teammate is available, have them:
1. Clone the repo
2. Follow the README setup steps
3. Verify notifications work

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Win32 focus helper | `scripts/focus.ps1` |
| 2 | Toast notification sender | `scripts/notify.ps1` |
| 3 | Protocol registration script | `register-protocol.ps1` |
| 4 | Plugin manifest | `plugin.json` |
| 5 | Integration testing | (no new files) |
| 6 | Documentation | `README.md` |
| 7 | Final cleanup and verification | (no new files) |
