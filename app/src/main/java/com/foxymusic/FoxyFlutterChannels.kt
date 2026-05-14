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
        const val ACCOUNT_INFO = "accountInfo"
        const val MOOD_MIX = "moodMix"
        const val PLAY = "play"
        const val PAUSE = "pause"
        const val TOGGLE_PLAY_PAUSE = "togglePlayPause"
        const val SEEK_TO = "seekTo"
        const val PLAY_QUEUE = "playQueue"
        const val NEXT = "next"
        const val PREVIOUS = "previous"
        const val TOGGLE_SHUFFLE = "toggleShuffle"
        const val CYCLE_REPEAT_MODE = "cycleRepeatMode"
        const val LIKE = "like"
        const val UNLIKE = "unlike"
        const val DOWNLOAD = "download"
        const val REMOVE_DOWNLOAD = "removeDownload"
        const val SLEEP_TIMER = "sleepTimer"
        const val CANCEL_SLEEP_TIMER = "cancelSleepTimer"
        const val GET_APPEARANCE = "getAppearance"
        const val SET_APPEARANCE = "setAppearance"
        const val LIBRARY_FEED = "libraryFeed"
        const val LYRICS = "lyrics"
        const val SKIP_TO_QUEUE_INDEX = "skipToQueueIndex"
        const val REMOVE_FROM_QUEUE = "removeFromQueue"
        const val ENQUEUE_PLAY_NEXT = "enqueuePlayNext"
        const val ADD_TO_QUEUE = "addToQueue"
        const val SET_PLAYER_PROGRESS_STYLE = "setPlayerProgressStyle"
        const val STORAGE_STATS = "storageStats"
        const val CHECK_GITHUB_RELEASE = "checkGitHubRelease"
        const val OPEN_SYSTEM_EQUALIZER = "openSystemEqualizer"
        const val OPEN_WEB_LOGIN = "openWebLogin"
        const val OPEN_EXTERNAL_URL = "openExternalUrl"
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
        const val SLEEP_TIMER = "sleepTimerState"
        const val TOAST = "toast"
        const val ERROR = "error"
    }
}

