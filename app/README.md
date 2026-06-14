# FoxyMusic — Android app module

Native Kotlin layer for **FoxyMusic**: Media3 playback, Flutter bridge, downloads, recognition, and notifications.

The full project README (features, downloads, screenshots) is at **[../README.md](../README.md)**.

## Module entry points

| File | Purpose |
|------|---------|
| `MainActivity.kt` | Flutter engine host |
| `FoxyFlutterBridge.kt` | Method/Event channel handler |
| `MusicPlayer.kt` | ExoPlayer queue & transport |
| `FoxyMediaSessionService.kt` | Foreground player + notification |
| `YTMusicApi.kt` | Browse / search / home sections |

## Build

From repository root:

```powershell
.\gradlew.bat assembleRelease
```

APKs: `app/build/outputs/apk/release/`

Maintainer details → **[../FOXYMUSIC_INSTRUCTIONS.txt](../FOXYMUSIC_INSTRUCTIONS.txt)**
