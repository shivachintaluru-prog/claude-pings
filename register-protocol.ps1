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
