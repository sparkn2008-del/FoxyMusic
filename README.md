# FoxyMusic

**FoxyMusic** is an Android music client with a **Kotlin** playback engine and a **Flutter** UI. Stream and organize your library with a YouTube Music–oriented experience: home feed, search, library, full-screen now playing, synced lyrics, queue, downloads, and settings.

**Current release:** `1.2.2` (versionCode 6) · [Releases](https://github.com/sparkn2008-del/FoxyMusic/releases)

Made with ❤️ by **Foxy Nish** ([@sparkn2008-del](https://github.com/sparkn2008-del))

---

## Features

| Area | Highlights |
|------|------------|
| **Playback** | Media3 / ExoPlayer queue, shuffle & repeat, crossfade, volume normalize, SponsorBlock |
| **UI** | Flutter shell — home, search, library, mini & full player, account hub |
| **Now playing** | Large artwork, Foxy-style seek bar, LRCLIB / YouTube lyrics, sleep timer, queue |
| **Library** | Liked songs, playlists, downloads, play history |
| **Look & feel** | AMOLED-friendly dark theme, dynamic accents from artwork, frosted-glass chrome |
| **Updates** | GitHub release check (daily auto-check + notifications), in-app “Check for updates” |

---

## Download

Pre-built APKs are published on **[GitHub Releases](https://github.com/sparkn2008-del/FoxyMusic/releases)**.

For most phones, install the **`arm64-v8a`** APK. Older 32-bit devices use **`armeabi-v7a`**.

---

## Build from source

Requirements: **JDK 17+**, **Android SDK** (API 34), **Flutter SDK** (for the embedded module).

From the repository root:

```powershell
.\gradlew.bat assembleDebug
```

```powershell
.\gradlew.bat assembleRelease
```

| Output | Path |
|--------|------|
| Debug APKs | `app\build\outputs\apk\debug\` |
| Release APKs | `app\build\outputs\apk\release\` |
| Play bundle | `app\build\outputs\bundle\release\app-release.aab` |

Release signing uses `key.properties` when present; otherwise the project may sign release builds with the debug key until you configure a keystore (see `app/build.gradle`).

---

## Project layout

| Path | Purpose |
|------|---------|
| `app/` | Android app module — player, bridge, downloads, updater (`com.foxymusic`) |
| `lib/` | Flutter UI — primary entry `lib/main.dart` |
| `pubspec.yaml` | Flutter package at repo root |
| `changelog.txt` | User-facing release notes |
| `FOXYMUSIC_INSTRUCTIONS.txt` | Maintainer guide (channels, builds, updater) |
| `docs/README.md` | Extended docs (architecture detail) |
| `foxy_flutter_ui/` | **Legacy** — do not add new UI here |

---

## Architecture

- **Kotlin** owns playback, streaming, persistence, GitHub update checks, and notifications.
- **Flutter** renders screens and talks to native code via:
  - `MethodChannel` — `foxy_music/methods`
  - `EventChannel` — `foxy_music/events`

Channel names, methods, and event payloads are listed in **`FOXYMUSIC_INSTRUCTIONS.txt`**.

---

## Changelog

See **[changelog.txt](changelog.txt)** for version history.

Recent **1.2.2** highlights: GitHub updater, update notifications, dynamic version label in settings.

---

## Contributing

1. **Flutter UI** → `lib/` (especially `lib/main.dart`)
2. **Native / player / bridge** → `app/src/main/java/com/foxymusic/`
3. New bridge APIs → `FoxyFlutterChannels.kt` + `FoxyFlutterBridge.kt` + Dart `_method.invokeMethod(...)`

Please do not commit `build/`, `*.html` reports, Gradle home caches, or signing keys (see `.gitignore`).

---

## License

FoxyMusic is a distinct project in this repository. Dependencies (AndroidX, Media3, Flutter, OkHttp, etc.) remain under their own licenses. In-app **Open-source licenses** are available from Settings.
