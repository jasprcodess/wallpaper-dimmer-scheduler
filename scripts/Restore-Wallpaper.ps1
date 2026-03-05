Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseDir = Join-Path $env:LOCALAPPDATA 'WallpaperDimmer'
$originalPath = Join-Path $baseDir 'original.png'
$dimmedPath = Join-Path $baseDir 'dimmed_40.png'

if (-not (Test-Path -LiteralPath $originalPath)) {
    throw "Backup wallpaper not found at: $originalPath"
}

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
        # Keep wallpaper restore working even if lock-screen API is unavailable.
    }
}

function Save-DimmedImage {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )

    Add-Type -AssemblyName System.Drawing

    $image = [System.Drawing.Image]::FromFile($SourcePath)
    $bitmap = $null
    $graphics = $null
    $attributes = $null

    try {
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

        $bitmap.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        if ($attributes) { $attributes.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($image) { $image.Dispose() }
    }
}

$SPI_SETDESKWALLPAPER = 20
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDCHANGE = 0x02
$ok = [Wallpaper.NativeMethods]::SystemParametersInfo(
    $SPI_SETDESKWALLPAPER,
    0,
    $originalPath,
    $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
)

if (-not $ok) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "Failed to restore wallpaper. Win32Error=$code"
}

# Keep lock screen permanently dimmed.
Save-DimmedImage -SourcePath $originalPath -DestinationPath $dimmedPath
Set-LockScreenImage -Path $dimmedPath
