Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseDir = Join-Path $env:LOCALAPPDATA 'WallpaperDimmer'
New-Item -ItemType Directory -Path $baseDir -Force | Out-Null

function Ensure-WallpaperApi {
    if (-not ('Wallpaper.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace Wallpaper {
    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    }
}
"@
    }
}

function Set-Wallpaper {
    param([Parameter(Mandatory=$true)][string]$Path)

    Ensure-WallpaperApi
    $SPI_SETDESKWALLPAPER = 20
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDCHANGE = 0x02

    $ok = [Wallpaper.NativeMethods]::SystemParametersInfo(
        $SPI_SETDESKWALLPAPER,
        0,
        $Path,
        $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
    )

    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to set wallpaper. Win32Error=$code"
    }
}

function Set-LockScreenImage {
    param([Parameter(Mandatory=$true)][string]$Path)

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        [void][Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
        [void][Windows.System.UserProfile.LockScreen,Windows.System.UserProfile,ContentType=WindowsRuntime]

        $methods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' }
        $opMethod = $methods |
            Where-Object {
                $_.IsGenericMethod -and
                $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
            } |
            Select-Object -First 1
        $actionMethod = $methods |
            Where-Object {
                -not $_.IsGenericMethod -and
                $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.FullName -eq 'Windows.Foundation.IAsyncAction'
            } |
            Select-Object -First 1

        if (-not $opMethod -or -not $actionMethod) {
            return
        }

        $fileTask = $opMethod.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke(
            $null,
            @([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path))
        )
        $fileTask.Wait()
        $file = $fileTask.Result

        $setTask = $actionMethod.Invoke(
            $null,
            @([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($file))
        )
        $setTask.Wait()
    }
    catch {
        # Keep wallpaper behavior working even if lock-screen API is unavailable.
    }
}

function Get-CurrentWallpaperSource {
    $regPath = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
    if ($regPath -and (Test-Path -LiteralPath $regPath)) {
        return $regPath
    }

    $transcoded = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
    if (Test-Path -LiteralPath $transcoded) {
        return $transcoded
    }

    throw 'Could not find current wallpaper image source.'
}

Add-Type -AssemblyName System.Drawing
$originalPath = Join-Path $baseDir 'original.png'
$dimmedPath = Join-Path $baseDir 'dimmed_40.png'
$sourcePath = Get-CurrentWallpaperSource

# If wallpaper is already our dimmed file and a backup exists, keep state as-is.
if ((Test-Path -LiteralPath $dimmedPath) -and (Test-Path -LiteralPath $originalPath)) {
    try {
        $sourceResolved = (Resolve-Path -LiteralPath $sourcePath).Path
        $dimmedResolved = (Resolve-Path -LiteralPath $dimmedPath).Path
        if ([string]::Equals($sourceResolved, $dimmedResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-Wallpaper -Path $dimmedPath
            return
        }
    }
    catch {
        # Continue with normal dim flow if path resolution fails.
    }
}

$image = [System.Drawing.Image]::FromFile($sourcePath)
$bitmap = $null
$graphics = $null
$attributes = $null

try {
    $skipBackupSave = $false
    if (Test-Path -LiteralPath $originalPath) {
        try {
            $sourceResolved = (Resolve-Path -LiteralPath $sourcePath).Path
            $originalResolved = (Resolve-Path -LiteralPath $originalPath).Path
            $skipBackupSave = [string]::Equals(
                $sourceResolved,
                $originalResolved,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
        catch {
            $skipBackupSave = $false
        }
    }

    if (-not $skipBackupSave) {
        $image.Save($originalPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }

    $bitmap = New-Object System.Drawing.Bitmap($image.Width, $image.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes

    $matrix = New-Object System.Drawing.Imaging.ColorMatrix
    $matrix.Matrix00 = 0.4
    $matrix.Matrix11 = 0.4
    $matrix.Matrix22 = 0.4
    $matrix.Matrix33 = 1.0
    $matrix.Matrix44 = 1.0

    $attributes.SetColorMatrix($matrix)

    $rect = New-Object System.Drawing.Rectangle(0, 0, $image.Width, $image.Height)
    $graphics.DrawImage(
        $image,
        $rect,
        0,
        0,
        $image.Width,
        $image.Height,
        [System.Drawing.GraphicsUnit]::Pixel,
        $attributes
    )

    $bitmap.Save($dimmedPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    if ($attributes) { $attributes.Dispose() }
    if ($graphics) { $graphics.Dispose() }
    if ($bitmap) { $bitmap.Dispose() }
    if ($image) { $image.Dispose() }
}

Set-Wallpaper -Path $dimmedPath
Set-LockScreenImage -Path $dimmedPath
