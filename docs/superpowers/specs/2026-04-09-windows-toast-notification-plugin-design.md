# Windows Toast Notification Plugin — Design Spec

## Problem

When Claude Code finishes working and is waiting for user input, there is no system-level notification. Users who tab away to other apps don't know Claude is ready until they switch back and check. This wastes time.

## Solution

A Claude Code plugin that sends a Windows native toast notification whenever Claude is waiting for user input. Clicking the toast brings the Claude Code terminal window to the foreground.

## Requirements

- **Trigger:** Fires on every `Notification` hook event (Claude waiting for input or permission)
- **Notification content:** Fixed text — title "Claude Code", body "Claude Code needs your attention"
- **Click action:** Clicking the toast brings the Claude Code terminal window to the foreground
- **Visual only:** No custom sound (uses Windows default toast behavior)
- **Platform:** Windows only (for now)
- **Distribution:** Claude Code plugin — team members install the plugin and it works automatically

## Architecture

### Plugin Structure

```
claude-notification-plugin/
├── plugin.json              # Plugin manifest — registers Notification hook
├── README.md                # Setup instructions
├── register-protocol.ps1    # One-time setup — registers claude-focus:// protocol
└── scripts/
    ├── notify.ps1           # Sends toast via BurntToast with protocol activation
    └── focus.ps1            # Clicked toast handler — focuses the terminal window
```

### Component Details

#### `plugin.json`

Plugin manifest that declares:
- Plugin name and description
- A single `Notification` event hook with no matcher (fires on all notification events)
- Hook command: `powershell.exe -ExecutionPolicy Bypass -File "<plugin_dir>/scripts/notify.ps1"`

#### `scripts/notify.ps1`

Responsibilities:
1. Read hook JSON from stdin (well-behaved hook contract)
2. Identify the parent terminal process (Windows Terminal, cmd, or pwsh) and capture its PID or window title
3. Send a toast notification via BurntToast:
   - Title: "Claude Code"
   - Body: "Claude Code needs your attention"
   - Protocol activation: registers `focus.ps1` as the click handler, passing the terminal PID/title as an argument
4. Exit 0 (non-blocking, allow Claude to continue waiting)

#### `scripts/focus.ps1`

Responsibilities:
1. Receive the terminal PID or window title as argument
2. Find the terminal window handle via `Get-Process` or `MainWindowHandle`
3. Call Win32 `SetForegroundWindow` via P/Invoke (Add-Type with C# interop) to bring the window to the foreground
4. Exit

#### `README.md`

Contents:
- One-line description of what the plugin does
- Prerequisites: PowerShell 5.1+ (ships with Windows), BurntToast module
- Setup steps:
  1. `Install-Module BurntToast -Scope CurrentUser -Force`
  2. Run the provided `register-protocol.ps1` script (one-time, registers `claude-focus://` protocol in HKCU)
  3. Register the plugin in Claude Code
- Troubleshooting: common issues (execution policy, BurntToast not found, protocol not registered)

### Hook Configuration

```json
{
  "name": "claude-notification",
  "description": "Windows toast notifications when Claude needs your attention",
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"scripts/notify.ps1\""
          }
        ]
      }
    ]
  }
}
```

### Click-to-Focus Flow

BurntToast's `-ActivatedAction` only works while the PowerShell process is alive. Since the hook process exits after sending the toast, we use a **custom protocol handler** instead.

**One-time setup** (documented in README, can be scripted):
Register a custom `claude-focus://` protocol in the Windows registry at `HKCU\Software\Classes\claude-focus`:

```
HKCU\Software\Classes\claude-focus
  (Default) = "URL:Claude Focus Protocol"
  "URL Protocol" = ""
  shell\open\command
    (Default) = powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "<plugin_dir>\scripts\focus.ps1"
```

**Runtime flow:**
1. `notify.ps1` captures the parent terminal PID, writes it to `$env:TEMP\claude-notification-pid.txt`
2. `notify.ps1` sends the toast with BurntToast using `-ActivationType Protocol -ActivationArgument "claude-focus://focus"`
3. Hook process exits
4. User clicks toast → Windows launches `focus.ps1` via the registered protocol
5. `focus.ps1` reads the PID from the temp file, finds the window handle, calls `SetForegroundWindow`
6. Terminal window comes to foreground

### Win32 Interop for Focus

`focus.ps1` uses Add-Type to define a small C# class:

```csharp
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
```

Then calls `ShowWindow` (to restore if minimized) followed by `SetForegroundWindow` with the terminal's `MainWindowHandle`.

## Dependencies

| Dependency | Version | Install |
|-----------|---------|---------|
| PowerShell | 5.1+ | Ships with Windows |
| BurntToast | Latest | `Install-Module BurntToast -Scope CurrentUser -Force` |

## Edge Cases

- **BurntToast not installed:** `notify.ps1` checks for the module and exits silently (exit 0) if not found. No error, no blocked hook.
- **Terminal process not found:** `focus.ps1` exits silently if it can't find the window handle.
- **Multiple Claude Code sessions:** Each session's hook fires independently. The toast click focuses whichever terminal PID was captured by that specific notification.
- **Notification spam:** If Claude fires multiple `Notification` events in quick succession, multiple toasts may appear. Windows natively stacks/replaces toasts from the same app, so this is acceptable behavior.

## Out of Scope

- macOS / Linux support (future work)
- Custom notification text or sound
- Toggle on/off skill
- Notification rate limiting
