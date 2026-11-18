# Installer script for Windows (PowerShell)
# Copies statusline.ps1 to ~/.gemini/ and updates settings.json statusLine command.
$ErrorActionPreference = "Stop"

$userProfile = [System.Environment]::GetFolderPath("UserProfile")
$geminiDir = Join-Path $userProfile ".gemini"
$destScript = Join-Path $geminiDir "statusline.ps1"
$configFile = Join-Path $geminiDir "statusline.json"
$backupFile = Join-Path $geminiDir "statusline.prev.json"
$settingsFile = Join-Path $geminiDir "antigravity-cli\settings.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Write-Host "Installing Unified AGY Statusline..." -ForegroundColor Cyan

if (-not (Test-Path $geminiDir)) {
    New-Item -ItemType Directory -Path $geminiDir -Force | Out-Null
    Write-Host "Created directory: $geminiDir"
}

$srcScript = Join-Path $PSScriptRoot "statusline.ps1"
if (-not (Test-Path $srcScript)) {
    $srcScript = Join-Path $PSScriptRoot "bin\statusline.ps1"
    if (-not (Test-Path $srcScript)) {
        $srcScript = "bin\statusline.ps1"
    }
}

Copy-Item -Path $srcScript -Destination $destScript -Force
Write-Host "Copied statusline.ps1 to: $destScript" -ForegroundColor Green

if (-not (Test-Path $configFile)) {
    $defaultConfig = @{
        show_quota = $true
        show_additional_stats = $true
        hide_zero_stats = $true
        show_state_indicator = $true
    }
    [System.IO.File]::WriteAllText($configFile, ($defaultConfig | ConvertTo-Json), $utf8NoBom)
    Write-Host "Created default configuration at: $configFile" -ForegroundColor Green
} else {
    Write-Host "Configuration file already exists at $configFile (skipping override)." -ForegroundColor Yellow
}

if ($destScript.Contains(" ")) {
    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$destScript'"
} else {
    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $destScript"
}

$jsonEscapedCmd = $cmd.Replace('\', '\\')
$manualSnippet = @"
  "statusLine": {
    "type": "command",
    "command": "$jsonEscapedCmd",
    "enabled": true
  }
"@

if (Test-Path $settingsFile) {
    try {
        $settingsJson = [System.IO.File]::ReadAllText($settingsFile, [System.Text.Encoding]::UTF8)
        $settings = ConvertFrom-Json $settingsJson

        $existingProp = $settings.PSObject.Properties["statusLine"]
        if ($null -eq $existingProp) {
            if (-not (Test-Path $backupFile)) {
                [System.IO.File]::WriteAllText($backupFile, '{"__absent__":true}', $utf8NoBom)
            }
        } else {
            $prevCmd = if ($existingProp.Value -and $existingProp.Value.command) { $existingProp.Value.command.ToString() } else { "" }
            if ($prevCmd -notlike "*statusline.ps1*") {
                $prevJson = $existingProp.Value | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($backupFile, $prevJson, $utf8NoBom)
                Write-Host "Backed up previous statusLine config to: $backupFile" -ForegroundColor Yellow
            }
        }

        $newStatusLine = [PSCustomObject]@{
            type = "command"
            command = $cmd
            enabled = $true
        }
        $settings | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $newStatusLine -Force

        $newJson = ConvertTo-Json $settings -Depth 10
        [System.IO.File]::WriteAllText($settingsFile, $newJson, $utf8NoBom)
        Write-Host "Successfully updated settings.json statusLine configuration!" -ForegroundColor Green
    } catch {
        Write-Warning "Could not update settings.json: $_"
        Write-Host "Please manually add this to your ${settingsFile}:" -ForegroundColor Yellow
        Write-Host $manualSnippet -ForegroundColor Cyan
    }
} else {
    Write-Warning "settings.json not found at ${settingsFile}. Please configure agy statusline manually."
    Write-Host "Please manually add this to your ${settingsFile}:" -ForegroundColor Yellow
    Write-Host $manualSnippet -ForegroundColor Cyan
}
