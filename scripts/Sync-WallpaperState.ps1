Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseDir = Join-Path $env:LOCALAPPDATA 'WallpaperDimmer'
$dimScript = Join-Path $baseDir 'Dim-Wallpaper.ps1'
$restoreScript = Join-Path $baseDir 'Restore-Wallpaper.ps1'
$originalPath = Join-Path $baseDir 'original.png'

if (-not (Test-Path -LiteralPath $dimScript)) {
    throw "Missing dim script: $dimScript"
}
if (-not (Test-Path -LiteralPath $restoreScript)) {
    throw "Missing restore script: $restoreScript"
}

$hour = (Get-Date).Hour
$shouldDim = ($hour -ge 23 -or $hour -lt 7)

if ($shouldDim) {
    & $dimScript
}
else {
    if (Test-Path -LiteralPath $originalPath) {
        & $restoreScript
    }
}
