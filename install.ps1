param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WallpaperDimmer')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = Join-Path $scriptRoot 'scripts'
$requiredScripts = @(
    'Dim-Wallpaper.ps1',
    'Restore-Wallpaper.ps1',
    'Sync-WallpaperState.ps1'
)

foreach ($name in $requiredScripts) {
    $fullPath = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Missing required script: $fullPath"
    }
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
foreach ($name in $requiredScripts) {
    Copy-Item -LiteralPath (Join-Path $sourceDir $name) -Destination (Join-Path $InstallDir $name) -Force
}

$syncScript = Join-Path $InstallDir 'Sync-WallpaperState.ps1'
$taskRun = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$syncScript`""
$taskNames = @(
    'WallpaperDimmer-Sync-2300',
    'WallpaperDimmer-Sync-0700',
    'WallpaperDimmer-Sync-30min',
    'WallpaperDimmer-Dim-2300',
    'WallpaperDimmer-Restore-0700'
)

foreach ($taskName in $taskNames) {
    cmd /c "schtasks /Delete /TN `"$taskName`" /F >nul 2>&1" | Out-Null
}

schtasks /Create /TN 'WallpaperDimmer-Sync-2300' /SC DAILY /ST 23:00 /TR $taskRun /F | Out-Null
schtasks /Create /TN 'WallpaperDimmer-Sync-0700' /SC DAILY /ST 07:00 /TR $taskRun /F | Out-Null
schtasks /Create /TN 'WallpaperDimmer-Sync-30min' /SC MINUTE /MO 30 /TR $taskRun /F | Out-Null

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Set-ScheduledTask -TaskName 'WallpaperDimmer-Sync-2300' -Settings $settings | Out-Null
Set-ScheduledTask -TaskName 'WallpaperDimmer-Sync-0700' -Settings $settings | Out-Null
Set-ScheduledTask -TaskName 'WallpaperDimmer-Sync-30min' -Settings $settings | Out-Null

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
$startupCmd = Join-Path $startupDir 'WallpaperDimmer-Sync.cmd'
$startupContent = "@echo off`r`npowershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$syncScript`"`r`n"
Set-Content -Path $startupCmd -Value $startupContent -Encoding ASCII

& $syncScript

Write-Output "Installed scripts to: $InstallDir"
Write-Output 'Registered tasks: WallpaperDimmer-Sync-2300, WallpaperDimmer-Sync-0700, WallpaperDimmer-Sync-30min'
Write-Output "Startup entry: $startupCmd"
Write-Output 'Sync executed once now.'
