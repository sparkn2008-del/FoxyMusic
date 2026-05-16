# FoxyMusic — documentation

The main project README for GitHub is **[../README.md](../README.md)** (features, downloads, build commands).

This file adds extra detail for contributors and agents.

---

## Hybrid architecture

FoxyMusic is an **Android** hybrid:

- **Kotlin** — Media3 playback, queue, downloads, account helpers, `FoxyGithubUpdate`, notifications
- **Flutter** — Home, search, library, now playing, lyrics, queue sheet, settings (`lib/main.dart`)

The repo root is both the **Gradle Android project** and the **Flutter module** (`pubspec.yaml`, `lib/`, `.android/`).

---

## Bridge

| Channel | Name |
|---------|------|
| Methods | `foxy_music/methods` |
| Events | `foxy_music/events` |

Implementation: `FoxyFlutterChannels.kt`, `FoxyFlutterBridge.kt`.

Notable methods: `getPlayerState`, `getAppearance`, `setAppearance`, `checkGitHubRelease`, `getAppVersion`, `openExternalUrl`.

Notable events: `playerState`, `appearanceChanged`, `updateAvailable`, `libraryFeedChanged`.

Full list → **`FOXYMUSIC_INSTRUCTIONS.txt`**.

---

## Updater

- Compares installed `versionName` to GitHub `releases/latest` ([sparkn2008-del/FoxyMusic](https://github.com/sparkn2008-del/FoxyMusic))
- Settings: `autoCheckUpdates`, `updateNotifications`, manual check
- Kotlin: `FoxyGithubUpdate.kt`, `FoxyUpdatePrefs.kt`, `FoxyUpdateNotifier.kt`

---

## Build

```powershell
.\gradlew.bat assembleRelease
```

APKs: `app\build\outputs\apk\release\` (per-ABI splits).

---

## Other docs

| File | Contents |
|------|----------|
| [changelog.txt](../changelog.txt) | Release notes |
| [FOXYMUSIC_INSTRUCTIONS.txt](../FOXYMUSIC_INSTRUCTIONS.txt) | Maintainer / agent guide |
| [FLUTTER_MIGRATION.md](../FLUTTER_MIGRATION.md) | Compose → Flutter migration notes |

---

## Legacy

Do not add new features under `foxy_flutter_ui/` — use repo root `lib/` instead.
