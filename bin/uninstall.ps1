# Uninstaller script for Windows (PowerShell)
# Restores previous statusLine configuration (if backed up) and removes installed script.
$ErrorActionPreference = "Stop"

$userProfile = [System.Environment]::GetFolderPath("UserProfile")
$geminiDir = Join-Path $userProfile ".gemini"
$destScript = Join-Path $geminiDir "statusline.ps1"
$configFile = Join-Path $geminiDir "statusline.json"
$backupFile = Join-Path $geminiDir "statusline.prev.json"
$settingsFile = Join-Path $geminiDir "antigravity-cli\settings.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Write-Host "Uninstalling Unified AGY Statusline..." -ForegroundColor Cyan

if (Test-Path $settingsFile) {
    try {
        $settingsJson = [System.IO.File]::ReadAllText($settingsFile, [System.Text.Encoding]::UTF8)
        $settings = ConvertFrom-Json $settingsJson

        if (Test-Path $backupFile) {
            $prevRaw = [System.IO.File]::ReadAllText($backupFile, [System.Text.Encoding]::UTF8)
            $prevObj = ConvertFrom-Json $prevRaw
            if ($prevObj.PSObject.Properties["__absent__"] -and $prevObj.__absent__) {
                $settings.PSObject.Properties.Remove("statusLine")
                Write-Host "Removed statusLine configuration (none existed prior to install)." -ForegroundColor Green
            } else {
                $settings | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $prevObj -Force
                Write-Host "Restored previous statusLine configuration from backup." -ForegroundColor Green
            }
            Remove-Item $backupFile -Force
        } elseif ($null -ne $settings.PSObject.Properties["statusLine"]) {
            $fallback = [PSCustomObject]@{
                type = ""
                command = ""
                enabled = $false
            }
            $settings | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $fallback -Force
            Write-Host "Disabled statusLine configuration in settings.json." -ForegroundColor Green
        }

        $newJson = ConvertTo-Json $settings -Depth 10
        [System.IO.File]::WriteAllText($settingsFile, $newJson, $utf8NoBom)
    } catch {
        Write-Warning "Could not update settings.json: $_"
    }
}

if (Test-Path $destScript) {
    Remove-Item $destScript -Force
    Write-Host "Removed script file: $destScript" -ForegroundColor Green
}

if (Test-Path $configFile) {
    Write-Host "Note: Configuration file left at $configFile to preserve your settings." -ForegroundColor Yellow
}

Write-Host "Uninstall complete!" -ForegroundColor Green
