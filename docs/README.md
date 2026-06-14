# FoxyMusic — documentation

The main project README for GitHub is **[../README.md](../README.md)** — features, download badges, FAQ, and build commands in a Metrolist-style layout.

This file adds contributor-focused detail.

---

## Hybrid architecture

FoxyMusic is an **Android** hybrid:

| Layer | Technology | Responsibility |
|-------|------------|----------------|
| UI | Flutter (`lib/`) | Home, search, library, player, settings |
| Core | Kotlin | Media3, queue, downloads, bridge, updater |
| API | Kotlin | YouTube Music browse/search/stream |

The repo root is both the **Gradle Android project** and the **Flutter module** (`pubspec.yaml`, `lib/`, `.android/`).

---

## Bridge

| Channel | Name |
|---------|------|
| Methods | `foxy_music/methods` |
| Events | `foxy_music/events` |

Implementation: `FoxyFlutterChannels.kt`, `FoxyFlutterBridge.kt`.

Notable methods: `getPlayerState`, `getAppearance`, `setAppearance`, `playQueue`, `checkGitHubRelease`, `getAppVersion`, `openExternalUrl`, recognition APIs.

Notable events: `playerState`, `appearanceChanged`, `updateAvailable`, `libraryFeedChanged`, `recognitionResult`.

**Full contract** → **[FOXYMUSIC_INSTRUCTIONS.txt](../FOXYMUSIC_INSTRUCTIONS.txt)**

---

## Key Dart files

| File | Role |
|------|------|
| `lib/main.dart` | Primary UI shell |
| `lib/now_playing_footer.dart` | Alternate player footer |
| `lib/now_playing_surfaces.dart` | Full lyrics list |
| `lib/foxy_startup_splash.dart` | Animated splash |

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

## Related docs

| File | Contents |
|------|----------|
| [changelog.txt](../changelog.txt) | Release notes |
| [FOXYMUSIC_INSTRUCTIONS.txt](../FOXYMUSIC_INSTRUCTIONS.txt) | Maintainer / agent guide |
| [FLUTTER_MIGRATION.md](../FLUTTER_MIGRATION.md) | Compose → Flutter migration notes |

---

## Legacy

Do not add new features under `foxy_flutter_ui/` — use repo root `lib/` instead.
