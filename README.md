# claude-pings

Windows toast notifications for Claude Code — with personality, humor, and feature discovery tips.

When Claude finishes working or needs your input, you get a toast notification. Clicking it brings the right terminal tab to the foreground.

## Install

```powershell
git clone https://github.com/shivachintaluru-prog/claude-pings.git
cd claude-pings
powershell.exe -ExecutionPolicy Bypass -File install.ps1
```

That's it. Start a new Claude Code session and notifications will appear automatically.

## What You Get

- Context-aware messages that tell you why Claude needs you (output ready vs. permission needed)
- 150 rotating messages with original humor across 9 themes
- Feature discovery tips on ~20% of notifications
- Click-to-focus brings the correct terminal tab to the foreground

## Optional: Auto-Update Tips

Tips ship with 30 curated Claude Code feature tips. To auto-refresh from the changelog monthly:

Edit `data/config.json` and set:
```json
{ "autoUpdateTips": true }
```

## Uninstall

Remove the hooks from `~/.claude/settings.json` (delete the `Notification`, `Stop`, and `SessionStart` entries) and optionally remove the protocol:

```powershell
Remove-Item -Path "HKCU:\Software\Classes\claude-focus" -Recurse -Force
```

## Troubleshooting

**No notification appears:**
- Verify BurntToast is installed: `Get-Module -ListAvailable -Name BurntToast`
- Check Windows notification settings — ensure notifications are enabled for PowerShell
- Test manually: `echo '{}' | powershell.exe -ExecutionPolicy Bypass -File scripts/notify.ps1`

**Clicking the notification does nothing:**
- Re-run `powershell.exe -ExecutionPolicy Bypass -File install.ps1` (re-registers the protocol)

**Too many notifications:**
- The plugin debounces within 15 seconds per session. If you still see duplicates, check `~/.claude/settings.json` for duplicate hook entries.

## Known Limitations

**Tab switching is best-effort.** Clicking a notification brings Windows Terminal to the foreground, but switching to the exact tab that triggered it may not always work. This is due to two Windows Terminal limitations:
- No public API exists to map process IDs to UI tab order — reordered or reopened tabs may get the wrong index
- `wt.exe focus-tab` has an [open bug](https://github.com/microsoft/terminal/issues/19324) where it intermittently fails when WT is already in the foreground

**Notifications are silent during screen recording/Focus Assist.** Windows suppresses toast popups when Do Not Disturb or Focus Assist is active. Notifications still appear in the notification center.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (ships with Windows)
- Claude Code
