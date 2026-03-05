Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseDir = Join-Path $env:LOCALAPPDATA 'WallpaperDimmer'
$originalPath = Join-Path $baseDir 'original.png'

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

Set-LockScreenImage -Path $originalPath
