# FoxyMusic

FoxyMusic is an **Android** music client built as a **hybrid app**: a **Kotlin** host application (Jetpack Compose where still used, Media3 playback, YouTube Music–oriented data layer) embeds a **Flutter** module that provides the main user interface (home, library, search, now playing, lyrics, queue, settings, account hub).

The repository root is both the **Gradle Android project** and the **Flutter module** (`pubspec.yaml`, `lib/`, `.android/`).

---

## Repository layout

| Area | Role |
|------|------|
| `app/` | Android application module: `build.gradle`, Kotlin sources under `app/src/main/java/com/foxymusic/` |
| `lib/` | Flutter/Dart UI — primary surface is `lib/main.dart` |
| `pubspec.yaml` | Flutter package manifest at repo root |
| `settings.gradle` | Includes `:app` and wires in Flutter via `.android/include_flutter.groovy` |
| `FOXYMUSIC_INSTRUCTIONS.txt` | Maintainer and agent guide: channels, builds, **changelog**, Gradle tips |
| `FLUTTER_MIGRATION.md` | Historical migration notes (Compose → Flutter strategy) |
| `foxy_flutter_ui/` | **Legacy** Flutter tree; new UI work belongs at repo root `lib/`, not here |

---

## Architecture (short)

- **Playback and streaming** live in Kotlin (ExoPlayer / Media3, queue, downloads, account helpers).
- **Flutter** renders screens and sends commands through a **MethodChannel**; Kotlin pushes state through an **EventChannel** (see `FoxyFlutterChannels.kt` / `FoxyFlutterBridge.kt`).
- **Appearance** (accent, surfaces, dynamic song colors) is coordinated so artwork-based accents can come from Kotlin without duplicating palette logic in Dart.

Exact channel names, method list, and `playerState` fields are documented in **`FOXYMUSIC_INSTRUCTIONS.txt`**.

---

## Building and running

From the repository root (`FoxyMusic`):

- **Debug APKs:** `.\gradlew.bat assembleDebug` → `app\build\outputs\apk\debug\` (per-ABI splits).
- **Release APKs:** `.\gradlew.bat assembleRelease` → `app\build\outputs\apk\release\`.
- **Play bundle:** `.\gradlew.bat bundleRelease` → `app\build\outputs\bundle\release\app-release.aab`.

Release builds currently use **debug signing** in `app/build.gradle` until a production keystore is configured.

Flutter tooling (format, analyze) may live outside your shell `PATH`; one documented toolchain is under Puro — see **`FOXYMUSIC_INSTRUCTIONS.txt`** for example paths and commands.

---

## Changelog

High-level, dated changes (bridge fixes, theme, downloads metadata, media notification, Flutter UI shell, release compile notes) are maintained in:

**`FOXYMUSIC_INSTRUCTIONS.txt`** → section **“Changelog (recent)”**.

That file is the canonical changelog for agents and maintainers; this README only points to it so the story stays in one place.

---

## Contributing / editing

- **Flutter UI:** `lib/main.dart` (and any new Dart files you add under `lib/`).
- **Native logic, player, channels:** `app/src/main/java/com/foxymusic/`.
- New **MethodChannel** APIs: add the name in `FoxyFlutterChannels.kt`, handle in `FoxyFlutterBridge.kt`, call from Dart via `_method.invokeMethod(...)`.

---

## License and upstream

FoxyMusic is a distinct product name in this tree; third-party libraries (AndroidX, Media3, Flutter, OkHttp, extractor dependencies, etc.) remain subject to their respective licenses. Use **“Open-source licenses”** in the in-app settings screen or your package manager’s license metadata where applicable.
