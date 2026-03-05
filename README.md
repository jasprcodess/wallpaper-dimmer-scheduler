# Wallpaper Dimmer Scheduler (Windows)

Dims your wallpaper and lock screen to 40% brightness from 11:00 PM to 7:00 AM.

## What it installs

- Scripts copied to `%LOCALAPPDATA%\WallpaperDimmer`
  - `Dim-Wallpaper.ps1`
  - `Restore-Wallpaper.ps1`
  - `Sync-WallpaperState.ps1`
- One scheduled task:
  - `WallpaperDimmer-Sync-2300` (daily 11:00 PM)
  - `WallpaperDimmer-Sync-0700` (daily 7:00 AM)
  - `WallpaperDimmer-Sync-30min` (every 30 minutes)
- One Startup entry:
  - `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WallpaperDimmer-Sync.cmd`

The sync script decides whether to dim or restore based on current local time.

## Install

Run in PowerShell from this repo folder:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
```

## Uninstall

Remove scheduled tasks only:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Remove scheduled tasks and installed files:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveFiles
```

## Notes

- The dim script saves your current wallpaper as `original.png` before creating `dimmed_40.png`.
- Lock screen update uses Windows Runtime APIs and is best-effort. Wallpaper changes continue even if lock screen APIs are unavailable due policy/system restrictions.
- If you change wallpaper during daytime, the next nightly dim cycle picks up the latest wallpaper and regenerates dimmed output.
