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
