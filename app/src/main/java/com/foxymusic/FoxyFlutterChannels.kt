package com.foxymusic

/**
 * Contract for the (future) Flutter UI module.
 *
 * Flutter will call Kotlin playback commands via a MethodChannel, and Kotlin will
 * push playback state updates via an EventChannel.
 *
 * This file is intentionally a "definition-only" contract so we don't have to
 * wire Flutter yet to make progress.
 */
object FoxyFlutterChannels {
    const val METHOD_CHANNEL = "foxy_music/methods"
    const val EVENT_CHANNEL = "foxy_music/events"

    object Methods {
        const val INIT = "init"
        const val HOME_FEED = "homeFeed"
        const val SEARCH = "search"
        const val SEARCH_ALL = "searchAll"
        const val SEARCH_HISTORY = "searchHistory"
        const val ADD_SEARCH_HISTORY = "addSearchHistory"
        const val REMOVE_SEARCH_HISTORY = "removeSearchHistory"
        const val CLEAR_SEARCH_HISTORY = "clearSearchHistory"
        const val ACCOUNT_INFO = "accountInfo"
        const val MOOD_MIX = "moodMix"
        const val PLAY = "play"
        const val PAUSE = "pause"
        const val TOGGLE_PLAY_PAUSE = "togglePlayPause"
        const val SEEK_TO = "seekTo"
        const val SET_VOLUME = "setVolume"
        const val PLAY_QUEUE = "playQueue"
        const val NEXT = "next"
        const val PREVIOUS = "previous"
        const val TOGGLE_SHUFFLE = "toggleShuffle"
        const val CYCLE_REPEAT_MODE = "cycleRepeatMode"
        const val LIKE = "like"
        const val UNLIKE = "unlike"
        const val DOWNLOAD = "download"
        const val REMOVE_DOWNLOAD = "removeDownload"
        const val IMPORT_LOCAL_AUDIO = "importLocalAudio"
        const val IMPORT_LOCAL_FOLDER = "importLocalFolder"
        const val SLEEP_TIMER = "sleepTimer"
        const val CANCEL_SLEEP_TIMER = "cancelSleepTimer"
        const val GET_APPEARANCE = "getAppearance"
        const val SET_APPEARANCE = "setAppearance"
        const val LIBRARY_FEED = "libraryFeed"
        /** Fast liked/download ids + settings for song overflow menu (no network). */
        const val SONG_MENU_CONTEXT = "songMenuContext"
        const val PLAYLIST_CREATE = "playlistCreate"
        const val PLAYLIST_RENAME = "playlistRename"
        const val PLAYLIST_DELETE = "playlistDelete"
        const val PLAYLIST_ADD_SONG = "playlistAddSong"
        const val PLAYLIST_REMOVE_SONG = "playlistRemoveSong"
        const val PLAYLIST_MOVE_SONG = "playlistMoveSong"
        /** Returns `List<Map>` of songs: local reads JSON; YouTube Music loads via authenticated browse. */
        const val PLAYLIST_FETCH_SONGS = "playlistFetchSongs"
        const val SET_PLAYBACK_SPEED = "setPlaybackSpeed"
        const val LYRICS = "lyrics"
        const val SKIP_TO_QUEUE_INDEX = "skipToQueueIndex"
        const val REMOVE_FROM_QUEUE = "removeFromQueue"
        const val MOVE_QUEUE_ITEM = "moveQueueItem"
        const val ENQUEUE_PLAY_NEXT = "enqueuePlayNext"
        const val ADD_TO_QUEUE = "addToQueue"
        const val STORAGE_STATS = "storageStats"
        const val CLEAR_STREAM_CACHE = "clearStreamCache"
        const val CREATE_BACKUP = "createBackup"
        const val RESTORE_LATEST_BACKUP = "restoreLatestBackup"
        const val BACKUP_STATUS = "backupStatus"
        const val CHECK_GITHUB_RELEASE = "checkGitHubRelease"
        const val GET_APP_VERSION = "getAppVersion"
        const val OPEN_SYSTEM_EQUALIZER = "openSystemEqualizer"
        const val OPEN_WEB_LOGIN = "openWebLogin"
        const val ACCOUNT_SET_COOKIE = "accountSetCookie"
        const val ACCOUNT_SIGN_OUT = "accountSignOut"
        const val OPEN_EXTERNAL_URL = "openExternalUrl"
        const val GET_VIDEO_CLIP_STREAM = "getVideoClipStream"
        const val START_RECOGNITION = "startRecognition"
        const val STOP_RECOGNITION = "stopRecognition"
        const val GET_RECOGNITION_STATE = "getRecognitionState"
        const val GET_RECOGNITION_HISTORY = "getRecognitionHistory"
        const val CLEAR_RECOGNITION_HISTORY = "clearRecognitionHistory"
        const val RESOLVE_RECOGNIZED_TRACK = "resolveRecognizedTrack"
        const val RESOLVE_MOTION_ARTWORK = "resolveMotionArtwork"
        const val RESOLVE_SPOTIFY_TRACK = "resolveSpotifyTrack"
        const val RESOLVE_ARTIST_PROFILE = "resolveArtistProfile"
        /** Minimize app instead of finishing when Flutter handles the Android back gesture at root. */
        const val MOVE_TASK_TO_BACK = "moveTaskToBack"
        /** One-shot snapshot of the same map as [Events.PLAYER_STATE] `state` (for Flutter UI seeding). */
        const val GET_PLAYER_STATE = "getPlayerState"
        const val PICK_HOME_BACKGROUND = "pickHomeBackground"
        const val CLEAR_HOME_BACKGROUND = "clearHomeBackground"
        const val GET_REMOTE_CONFIG_CACHE = "getRemoteConfigCache"
        const val SET_REMOTE_CONFIG_CACHE = "setRemoteConfigCache"
        const val CLEAR_REMOTE_CONFIG_CACHE = "clearRemoteConfigCache"
        /** Relaunch the app so Flutter reloads home wallpaper and theme state. */
        const val RESTART_APP = "restartApp"
    }

    /**
     * Kotlin -> Flutter event payload.
     *
     * Recommended envelope:
     * {
     *   "type": "playerState",
     *   "state": { PlayerUiState fields }
     * }
     */
    object Events {
        const val PLAYER_STATE = "playerState"
        const val PLAYER_PROGRESS = "playerProgress"
        /** Emitted after [Methods.SET_APPEARANCE] so Flutter can reload [Methods.GET_APPEARANCE]. */
        const val APPEARANCE_CHANGED = "appearanceChanged"
        const val SLEEP_TIMER = "sleepTimerState"
        const val LIBRARY_DOWNLOAD_PROGRESS = "libraryDownloadProgress"
        const val LIBRARY_DOWNLOADS_CHANGED = "libraryDownloadsChanged"
        /** User playlists or curated library slices changed — Flutter should reload [Methods.LIBRARY_FEED]. */
        const val LIBRARY_FEED_CHANGED = "libraryFeedChanged"
        /** YouTube Music web session saved or cleared — Flutter should reload [Methods.ACCOUNT_INFO]. */
        const val ACCOUNT_CHANGED = "accountChanged"
        const val TOAST = "toast"
        const val ERROR = "error"
        /** Newer APK published on GitHub — Flutter shows optional in-app prompt. */
        const val UPDATE_AVAILABLE = "updateAvailable"
        const val RECOGNITION_STATE = "recognitionState"
    }
}

