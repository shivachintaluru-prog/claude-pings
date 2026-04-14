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

## Requirements

- Windows 10/11
- PowerShell 5.1+ (ships with Windows)
- Claude Code
