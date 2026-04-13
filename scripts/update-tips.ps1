# update-tips.ps1 — Fetches new Claude Code tips from the changelog.
# Runs on session start via hook. Only active if autoUpdateTips is enabled in config.json.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$dataDir = Join-Path (Split-Path -Parent $scriptDir) "data"
$configFile = Join-Path $dataDir "config.json"
$metaFile = Join-Path $dataDir "tips-meta.json"
$tipsFile = Join-Path $dataDir "tips.json"

# Check if auto-update is enabled
if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        if (-not $config.autoUpdateTips) { exit 0 }
    } catch { exit 0 }
} else {
    exit 0
}

# Check if 30+ days since last update
if (Test-Path $metaFile) {
    try {
        $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
        $lastUpdated = [DateTime]::Parse($meta.lastUpdated)
        $daysSince = ((Get-Date) - $lastUpdated).TotalDays
        if ($daysSince -lt 30) { exit 0 }
    } catch {}
}

# Fetch Claude Code changelog
try {
    $response = Invoke-WebRequest -Uri "https://docs.anthropic.com/en/docs/claude-code/changelog" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    $content = $response.Content

    # Load existing tips for dedup
    $existingTips = @()
    if (Test-Path $tipsFile) {
        $existingTips = Get-Content $tipsFile -Raw | ConvertFrom-Json
    }
    $existingSet = @{}
    foreach ($t in $existingTips) { $existingSet[$t.ToLower().Trim()] = $true }

    # Extract feature mentions from changelog (lines with key phrases)
    $newTips = @()
    $lines = $content -split "`n"
    foreach ($line in $lines) {
        $clean = $line -replace '<[^>]+>', '' -replace '&[^;]+;', '' | ForEach-Object { $_.Trim() }
        if ($clean.Length -gt 20 -and $clean.Length -lt 120) {
            if ($clean -match '(new|added|support|now|can now|introduce|feature|improve)' -and
                $clean -match '(claude|code|command|tool|hook|mcp|model|session|prompt)') {
                $tip = $clean -replace '^\W+', ''
                if (-not $existingSet.ContainsKey($tip.ToLower().Trim())) {
                    $newTips += $tip
                    $existingSet[$tip.ToLower().Trim()] = $true
                }
            }
        }
    }

    # Append new tips (limit to 10 per update)
    if ($newTips.Count -gt 0) {
        $toAdd = $newTips | Select-Object -First 10
        $allTips = @($existingTips) + @($toAdd)
        $allTips | ConvertTo-Json | Out-File $tipsFile -Encoding utf8
    }

    # Update timestamp
    $meta = if (Test-Path $metaFile) {
        Get-Content $metaFile -Raw | ConvertFrom-Json
    } else {
        @{ lastUpdated = ""; seenIndices = @() }
    }
    $meta.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $meta | ConvertTo-Json | Out-File $metaFile -Encoding utf8

} catch {
    # Silent failure — don't disrupt the session
}

exit 0
