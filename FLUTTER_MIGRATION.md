# Flutter Migration (Definition-Only)

## Goal
Move the user-facing UI (Home, Player, Mini-player, Library, Downloads, Settings) from Jetpack Compose to Flutter, while keeping the existing Kotlin playback/data core (ExoPlayer + `MusicPlayer`, stream resolution, download/offline, account/login).

## Phase 1 (next implementation step)
1. Create a Flutter module (e.g. `foxy_flutter_ui/`) with screens:
   - Home
   - Full Player
   - Mini-player bar
2. Embed it into Android using a dedicated Flutter screen route.
3. Implement the bridge to Kotlin playback core.

## Phase 2
Move Library, Downloads, Settings to Flutter once Phase 1 is stable.

## Bridge design

### Transport
Use two Flutter <-> Kotlin channels:
1. MethodChannel for commands Flutter sends to Kotlin
2. EventChannel for playback state updates Kotlin pushes to Flutter

### Channel names
Defined in `app/src/main/java/com/foxymusic/FoxyFlutterChannels.kt`:
- MethodChannel: `foxy_music/methods`
- EventChannel: `foxy_music/events`

### Methods (Flutter -> Kotlin)
Minimum commands:
- `play`, `pause`, `togglePlayPause`
- `seekTo` (positionMs)
- `playQueue` (list of songs + startIndex)
- `next`, `previous`
- `toggleShuffle`, `cycleRepeatMode`
- `download`, `removeDownload`
- `sleepTimer`, `cancelSleepTimer`

### Events (Kotlin -> Flutter)
Minimum events:
- `playerState`: wraps `PlayerUiState` so Flutter can render:
  - current song title/artist/artwork
  - buffering/playing flags
  - position/duration
  - repeat/shuffle state
  - queue + queueIndex (for UI queue rendering)
- `sleepTimerState`
- `toast` and `error` for transient UI messaging

## Data mapping
Flutter should reuse a JSON-serializable representation of:
- `Song` (videoId, title, artist, artwork urls, localPath if downloaded)
- `PlayerUiState` (fields in `com.foxymusic.PlayerUiState`)

## First rollout strategy
Keep Compose routes temporarily:
- Flutter hosts Home + Player first.
- Compose remains for Library/Downloads/Settings until Flutter is stable.

