param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WallpaperDimmer'),
    [switch]$RemoveFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskNames = @(
    'WallpaperDimmer-Sync-2300',
    'WallpaperDimmer-Sync-0700',
    'WallpaperDimmer-Sync-30min',
    'WallpaperDimmer-Dim-2300',
    'WallpaperDimmer-Restore-0700'
)

foreach ($name in $taskNames) {
    cmd /c "schtasks /Delete /TN `"$name`" /F >nul 2>&1" | Out-Null
}

$startupCmd = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\WallpaperDimmer-Sync.cmd'
if (Test-Path -LiteralPath $startupCmd) {
    Remove-Item -LiteralPath $startupCmd -Force
}

if ($RemoveFiles -and (Test-Path -LiteralPath $InstallDir)) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Output "Removed files: $InstallDir"
}

Write-Output 'Uninstalled scheduled tasks.'
