# install.ps1 — One-command setup for claude-pings notification plugin.
# Run: powershell.exe -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"
$pluginDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host ""
Write-Host "=== claude-pings installer ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Install BurntToast
Write-Host "[1/4] Checking BurntToast module..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name BurntToast) {
    Write-Host "  BurntToast already installed." -ForegroundColor Green
} else {
    Write-Host "  Installing BurntToast..."
    Install-Module BurntToast -Scope CurrentUser -Force
    Write-Host "  BurntToast installed." -ForegroundColor Green
}

# Step 2: Register claude-focus:// protocol
Write-Host "[2/4] Registering click-to-focus protocol..." -ForegroundColor Yellow
$focusScript = Join-Path $pluginDir "scripts\focus.ps1"
$protocolKey = "HKCU:\Software\Classes\claude-focus"
$commandKey = "$protocolKey\shell\open\command"
New-Item -Path $commandKey -Force | Out-Null
Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:Claude Focus Protocol"
Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""
$command = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$focusScript`""
Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $command
Write-Host "  Protocol registered." -ForegroundColor Green

# Step 3: Patch ~/.claude/settings.json with hooks
Write-Host "[3/4] Configuring Claude Code hooks..." -ForegroundColor Yellow
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$notifyScript = Join-Path $pluginDir "scripts\notify.ps1"
$updateScript = Join-Path $pluginDir "scripts\update-tips.ps1"
$notifyCmd = "powershell.exe -ExecutionPolicy Bypass -File `"$notifyScript`""
$updateCmd = "powershell.exe -ExecutionPolicy Bypass -File `"$updateScript`""

# Load existing settings or create new
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    New-Item -Path (Split-Path $settingsPath) -ItemType Directory -Force | Out-Null
    $settings = @{}
}

# Build hook entries
$notifyHook = @{
    matcher = ""
    hooks = @(
        @{ type = "command"; command = $notifyCmd; timeout = 30 }
    )
}
$updateHook = @{
    matcher = ""
    hooks = @(
        @{ type = "command"; command = $updateCmd; async = $true; timeout = 60 }
    )
}

# Merge hooks — preserve existing non-plugin hooks
if (-not $settings.hooks) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue @{} -Force
}
$settings.hooks | Add-Member -NotePropertyName Notification -NotePropertyValue @($notifyHook) -Force
$settings.hooks | Add-Member -NotePropertyName Stop -NotePropertyValue @($notifyHook) -Force
$settings.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @($updateHook) -Force

$settings | ConvertTo-Json -Depth 10 | Out-File $settingsPath -Encoding UTF8
Write-Host "  Hooks added to $settingsPath" -ForegroundColor Green

# Step 4: Test notification
Write-Host "[4/4] Sending test notification..." -ForegroundColor Yellow
Import-Module BurntToast
New-BurntToastNotification -Text "claude-pings", "Install successful! You will see notifications like this."
Write-Host "  Test notification sent." -ForegroundColor Green

Write-Host ""
Write-Host "=== Setup complete! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "You should see a test notification now." -ForegroundColor White
Write-Host "Start a new Claude Code session to activate the hooks." -ForegroundColor White
Write-Host ""
Write-Host "To enable auto-updating tips from Claude Code changelog:" -ForegroundColor Yellow
Write-Host "  Edit $pluginDir\data\config.json and set autoUpdateTips to true" -ForegroundColor White
Write-Host ""
