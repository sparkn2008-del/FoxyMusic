package com.foxymusic

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.net.Uri
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.graphics.toArgb

class FoxyFlutterBridge(
    private val context: Context
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sinks = Collections.newSetFromMap(ConcurrentHashMap<EventChannel.EventSink, Boolean>())
    private var broadcastJob: Job? = null

    /**
     * Increments whenever the active queue index or current track id changes so Flutter can
     * reliably rebuild the mini player even if nested maps were ever aliased across events.
     */
    private val playerEpoch = object {
        @Volatile
        var epoch: Long = 0L

        @Volatile
        var lastKey: String = ""

        fun bumpIfNeeded(ui: PlayerUiState): Long {
            val key = "${ui.queueIndex}|${ui.currentSong?.videoId.orEmpty()}"
            synchronized(this) {
                if (key != lastKey) {
                    lastKey = key
                    epoch += 1L
                }
                return epoch
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            FoxyFlutterChannels.Methods.INIT -> {
                result.success(null)
            }
            FoxyFlutterChannels.Methods.GET_APPEARANCE -> {
                val settings = FoxySettings.state.value
                val palette = settings.palette(FoxyDynamicTheme.accent.value)
                result.success(
                    mapOf(
                        "themeMode" to settings.themeMode,
                        "themePalette" to settings.themePalette,
                        "dynamicSongColors" to settings.dynamicSongColors,
                        "blurEffects" to settings.blurEffects,
                        "compactPlayer" to settings.compactPlayer,
                        "gestureControls" to settings.gestureControls,
                        "playerProgressStyle" to settings.playerProgressStyle,
                        "persistentQueue" to settings.persistentQueue,
                        "saveHistory" to settings.saveHistory,
                        "sponsorBlockEnabled" to settings.sponsorBlockEnabled,
                        "crossfadeMs" to settings.crossfadeMs,
                        "lyricsPreferLrclib" to settings.lyricsPreferLrclib,
                        "streamQualityTier" to settings.streamQualityTier,
                        "contentLanguageTag" to settings.contentLanguageTag,
                        "appLanguageTag" to settings.appLanguageTag,
                        "proxyEnabled" to settings.proxyEnabled,
                        "proxyEndpoint" to settings.proxyEndpoint,
                        "normalizeVolume" to settings.normalizeVolume,
                        "skipSilence" to settings.skipSilence,
                        "autoBackupEnabled" to settings.autoBackupEnabled,
                        "accentArgb" to palette.accent.toArgb(),
                        "backgroundArgb" to palette.background.toArgb(),
                        "surfaceArgb" to palette.surface.toArgb(),
                        "surfaceHighArgb" to palette.surfaceHigh.toArgb(),
                        "mutedArgb" to palette.muted.toArgb()
                    )
                )
            }
            FoxyFlutterChannels.Methods.SET_APPEARANCE -> {
                val themePalette = call.argument<Number>("themePalette")?.toInt()
                val themeMode = call.argument<Number>("themeMode")?.toInt()
                val dynamicSongColors = call.argument<Boolean>("dynamicSongColors")
                val accentArgb = call.argument<Number>("accentArgb")?.toInt()
                val blurEffects = call.argument<Boolean>("blurEffects")
                val compactPlayer = call.argument<Boolean>("compactPlayer")
                val gestureControls = call.argument<Boolean>("gestureControls")
                val persistentQueue = call.argument<Boolean>("persistentQueue")
                val saveHistory = call.argument<Boolean>("saveHistory")
                val sponsorBlockEnabled = call.argument<Boolean>("sponsorBlockEnabled")
                val crossfadeMs = call.argument<Number>("crossfadeMs")?.toInt()
                val lyricsPreferLrclib = call.argument<Boolean>("lyricsPreferLrclib")
                val streamQualityTier = call.argument<Number>("streamQualityTier")?.toInt()
                val contentLanguageTag = call.argument<String>("contentLanguageTag")
                val appLanguageTag = call.argument<String>("appLanguageTag")
                val proxyEnabled = call.argument<Boolean>("proxyEnabled")
                val proxyEndpoint = call.argument<String>("proxyEndpoint")
                val normalizeVolume = call.argument<Boolean>("normalizeVolume")
                val skipSilence = call.argument<Boolean>("skipSilence")
                val autoBackupEnabled = call.argument<Boolean>("autoBackupEnabled")
                FoxySettings.update { current ->
                    current.copy(
                        themePalette = themePalette?.coerceIn(0, FoxyThemePresets.lastIndex) ?: current.themePalette,
                        themeMode = themeMode?.coerceIn(0, 2) ?: current.themeMode,
                        dynamicSongColors = dynamicSongColors ?: current.dynamicSongColors,
                        accentArgb = accentArgb ?: current.accentArgb,
                        blurEffects = blurEffects ?: current.blurEffects,
                        compactPlayer = compactPlayer ?: current.compactPlayer,
                        gestureControls = gestureControls ?: current.gestureControls,
                        persistentQueue = persistentQueue ?: current.persistentQueue,
                        saveHistory = saveHistory ?: current.saveHistory,
                        sponsorBlockEnabled = sponsorBlockEnabled ?: current.sponsorBlockEnabled,
                        crossfadeMs = crossfadeMs?.let { v ->
                            when (v) {
                                0, 3000, 5000, 8000, 12000 -> v
                                else -> current.crossfadeMs
                            }
                        } ?: current.crossfadeMs,
                        lyricsPreferLrclib = lyricsPreferLrclib ?: current.lyricsPreferLrclib,
                        streamQualityTier = streamQualityTier?.coerceIn(0, 2) ?: current.streamQualityTier,
                        contentLanguageTag = contentLanguageTag?.trim()?.takeIf { it.isNotEmpty() }
                            ?: current.contentLanguageTag,
                        appLanguageTag = appLanguageTag?.let { it.trim() } ?: current.appLanguageTag,
                        proxyEnabled = proxyEnabled ?: current.proxyEnabled,
                        proxyEndpoint = proxyEndpoint?.trim() ?: current.proxyEndpoint,
                        normalizeVolume = normalizeVolume ?: current.normalizeVolume,
                        skipSilence = skipSilence ?: current.skipSilence,
                        autoBackupEnabled = autoBackupEnabled ?: current.autoBackupEnabled
                    )
                }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.ACCOUNT_INFO -> {
                val account = FoxyAccount.state.value
                val library = FoxyLibraryStore.state.value
                result.success(
                    mapOf(
                        "isSignedIn" to account.isSignedIn,
                        "displayName" to account.displayName,
                        "name" to account.name,
                        "email" to account.email,
                        "avatarUrl" to account.avatarUrl,
                        "likedCount" to library.likedSongs.size,
                        "playlistCount" to library.savedSongs.size,
                        "historyCount" to library.historySongs.size,
                        "downloadCount" to library.downloadedSongs.size
                    )
                )
            }
            FoxyFlutterChannels.Methods.LIBRARY_FEED -> {
                val library = FoxyLibraryStore.state.value
                result.success(
                    mapOf(
                        "downloads" to library.downloadedSongs.map { it.toFlutterMap() },
                        "liked" to library.likedSongs.map { it.toFlutterMap() },
                        "history" to library.historySongs.map { it.toFlutterMap() },
                        "saved" to library.savedSongs.map { it.toFlutterMap() },
                        "playlists" to library.savedSongs.map { it.toFlutterMap() }
                    )
                )
            }
            FoxyFlutterChannels.Methods.SEARCH -> {
                val query = call.argument<String>("query").orEmpty().trim()
                val limit = (call.argument<Number>("limit")?.toInt() ?: 40).coerceIn(1, 60)
                if (query.isBlank()) {
                    result.success(mapOf("songs" to emptyList<Map<String, Any?>>()))
                } else {
                    scope.launch {
                        val payload = runCatching {
                            withContext(Dispatchers.IO) {
                                mapOf("songs" to YTMusicApi.search(query).take(limit).map { it.toFlutterMap() })
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure { result.error("search_failed", it.message ?: "Search failed", null) }
                    }
                }
            }
            FoxyFlutterChannels.Methods.HOME_FEED -> {
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            val quick = YTMusicApi.search("new music songs").take(24)
                            val charts = YTMusicApi.search("top songs today").take(16)
                            val releases = YTMusicApi.search("new release music").take(16)
                            val focus = YTMusicApi.getMoodMix("Focus").take(16)
                            mapOf(
                                "sections" to listOf(
                                    mapOf("title" to "Quick picks", "songs" to quick.map { it.toFlutterMap() }),
                                    mapOf("title" to "Trending now", "songs" to charts.map { it.toFlutterMap() }),
                                    mapOf("title" to "New releases", "songs" to releases.map { it.toFlutterMap() }),
                                    mapOf("title" to "Focus station", "songs" to focus.map { it.toFlutterMap() })
                                )
                            )
                        }
                    }
                    payload.onSuccess(result::success)
                        .onFailure { result.error("home_failed", it.message ?: "Home feed failed", null) }
                }
            }
            FoxyFlutterChannels.Methods.MOOD_MIX -> {
                val mood = call.argument<String>("mood").orEmpty().ifBlank { "Focus" }
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            mapOf(
                                "title" to "$mood radio",
                                "songs" to YTMusicApi.getMoodMix(mood).take(24).map { it.toFlutterMap() }
                            )
                        }
                    }
                    payload.onSuccess(result::success)
                        .onFailure { result.error("mood_failed", it.message ?: "Mood feed failed", null) }
                }
            }
            FoxyFlutterChannels.Methods.PLAY -> {
                val songMap = call.argument<Map<String, Any?>>("song")
                val song = songMap?.toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "song is required", null)
                } else {
                    FoxyPlayerConnection.play(context, song)
                    result.success(null)
                }
            }
            FoxyFlutterChannels.Methods.TOGGLE_PLAY_PAUSE -> {
                FoxyPlayerConnection.togglePlayPause()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.NEXT -> {
                FoxyPlayerConnection.playNext()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.PREVIOUS -> {
                FoxyPlayerConnection.playPrevious()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.PAUSE -> {
                FoxyPlayerConnection.pause()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.PLAY_QUEUE -> {
                val list = call.argument<List<Map<String, Any?>>>("songs").orEmpty()
                val songs = list.mapNotNull { it.toSongOrNull() }
                val startIndex = (call.argument<Number>("startIndex")?.toInt() ?: 0).coerceAtLeast(0)
                if (songs.isEmpty()) {
                    result.error("bad_args", "songs is required", null)
                } else {
                    FoxyPlayerConnection.playQueue(context, songs, startIndex.coerceAtMost(songs.lastIndex))
                    result.success(null)
                }
            }
            FoxyFlutterChannels.Methods.SKIP_TO_QUEUE_INDEX -> {
                val index = (call.argument<Number>("index")?.toInt() ?: 0).coerceAtLeast(0)
                FoxyPlayerConnection.skipToQueueIndex(context, index)
                result.success(null)
            }
            FoxyFlutterChannels.Methods.REMOVE_FROM_QUEUE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.removeFromQueue(it) }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.ENQUEUE_PLAY_NEXT -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.enqueuePlayNext(it) }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.ADD_TO_QUEUE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.addToQueue(it) }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.SEEK_TO -> {
                val pos = (call.argument<Number>("positionMs")?.toLong() ?: 0L).coerceAtLeast(0L)
                FoxyPlayerConnection.seekTo(pos)
                result.success(null)
            }
            FoxyFlutterChannels.Methods.TOGGLE_SHUFFLE -> {
                FoxyPlayerConnection.toggleShuffle()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.CYCLE_REPEAT_MODE -> {
                FoxyPlayerConnection.cycleRepeatMode()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.LIKE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyLibraryStore.toggleLiked(it) }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.UNLIKE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyLibraryStore.toggleLiked(it) }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.DOWNLOAD -> {
                val song = call.argument<Map<String, Any?>>("song")?.toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "song is required", null)
                } else {
                    FoxyDownloadManager.downloadSong(context, song)
                    result.success(null)
                }
            }
            FoxyFlutterChannels.Methods.REMOVE_DOWNLOAD -> {
                val song = call.argument<Map<String, Any?>>("song")?.toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "song is required", null)
                } else {
                    FoxyDownloadManager.removeDownload(context, song)
                    result.success(null)
                }
            }
            FoxyFlutterChannels.Methods.SLEEP_TIMER -> {
                val minutes = (call.argument<Number>("minutes")?.toInt() ?: 0).coerceAtLeast(0)
                if (minutes == 0) FoxyPlayerConnection.sleepAfterCurrentSong()
                else FoxyPlayerConnection.scheduleSleepTimer(minutes)
                result.success(null)
            }
            FoxyFlutterChannels.Methods.CANCEL_SLEEP_TIMER -> {
                FoxyPlayerConnection.cancelSleepTimer()
                result.success(null)
            }
            FoxyFlutterChannels.Methods.LYRICS -> {
                val song = call.argument<Map<String, Any?>>("song")?.toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "song is required", null)
                } else {
                    scope.launch {
                        val payload = runCatching {
                            withContext(Dispatchers.IO) {
                                LyricsRepository.fetchSyncedLines(song).map {
                                    mapOf("timeMs" to it.timeMs, "text" to it.text)
                                }
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure { result.error("lyrics_failed", it.message ?: "Lyrics failed", null) }
                    }
                }
            }
            FoxyFlutterChannels.Methods.SET_PLAYER_PROGRESS_STYLE -> {
                val style = (call.argument<Number>("style")?.toInt() ?: 2).coerceIn(0, 3)
                FoxySettings.update { it.copy(playerProgressStyle = style) }
                result.success(null)
            }
            FoxyFlutterChannels.Methods.STORAGE_STATS -> {
                result.success(FoxyStorageStats.snapshot(context))
            }
            FoxyFlutterChannels.Methods.CHECK_GITHUB_RELEASE -> {
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) { FoxyGithubUpdate.checkLatest() }
                    }.getOrElse {
                        mapOf(
                            "ok" to false,
                            "error" to (it.message ?: "check_failed"),
                            "tagName" to "",
                            "htmlUrl" to "",
                            "downloadUrl" to ""
                        )
                    }
                    result.success(payload)
                }
            }
            FoxyFlutterChannels.Methods.OPEN_SYSTEM_EQUALIZER -> {
                val intent = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
                    putExtra(AudioEffect.EXTRA_AUDIO_SESSION, 0)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                val ok = runCatching { context.startActivity(intent) }.isSuccess
                result.success(ok)
            }
            FoxyFlutterChannels.Methods.OPEN_WEB_LOGIN -> {
                val uri = Uri.parse(
                    "https://accounts.google.com/ServiceLogin?service=youtube&continue=" +
                        Uri.encode("https://music.youtube.com/")
                )
                val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(intent)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                }
            }
            FoxyFlutterChannels.Methods.OPEN_EXTERNAL_URL -> {
                val raw = call.argument<String>("url").orEmpty().trim()
                val uri = runCatching { Uri.parse(raw) }.getOrNull()
                val scheme = uri?.scheme?.lowercase().orEmpty()
                if (uri == null || raw.isBlank() || (scheme != "https" && scheme != "http")) {
                    result.error("bad_args", "url must be http(s)", null)
                } else {
                    val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(intent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sink = events ?: return
        sinks.add(sink)
        startBroadcastIfNeeded()
    }

    /**
     * One broadcast pipeline for all Dart listeners. Never clear every sink on a single
     * subscription cancel — that used to break the mini player when the now-playing sheet
     * unsubscribed from the same EventChannel.
     */
    private fun startBroadcastIfNeeded() {
        if (broadcastJob?.isActive == true) return
        broadcastJob = scope.launch {
            launch {
                combine(
                    FoxyPlayerConnection.state,
                    FoxyDynamicTheme.accent,
                    FoxySettings.state,
                    snapshotFlow { FoxyLibraryStore.state.value }
                ) { ui, songAccent, settings, library ->
                    val liked = ui.currentSong?.let { s ->
                        library.likedSongs.any { it.videoId == s.videoId }
                    } == true
                    mapOf(
                        "type" to FoxyFlutterChannels.Events.PLAYER_STATE,
                        "state" to mapOf(
                            "playerEpoch" to playerEpoch.bumpIfNeeded(ui),
                            "isPlaying" to ui.isPlaying,
                            "isBuffering" to ui.isBuffering,
                            "positionMs" to ui.positionMs,
                            "durationMs" to ui.durationMs,
                            "queueIndex" to ui.queueIndex,
                            "shuffleEnabled" to ui.shuffleEnabled,
                            "repeatMode" to ui.repeatMode.name,
                            "error" to ui.error,
                            "queue" to ui.queue.map { q ->
                                q.toFlutterMap()
                            },
                            "currentSong" to ui.currentSong?.toFlutterMap(),
                            "songIsLiked" to liked,
                            "dynamicSongColors" to settings.dynamicSongColors,
                            "songAccentArgb" to (
                                if (settings.dynamicSongColors) songAccent?.toArgb() else null
                                ),
                        )
                    )
                }.collect { payload -> emit(payload) }
            }
            launch {
                FoxyPlayerConnection.sleepTimerState.collect { timer ->
                    emit(
                        mapOf(
                            "type" to FoxyFlutterChannels.Events.SLEEP_TIMER,
                            "state" to mapOf(
                                "mode" to timer.mode.name,
                                "fireAtEpochMs" to timer.fireAtEpochMs
                            )
                        )
                    )
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        // Stale sinks are removed when [emit] fails after the Dart side cancels.
    }

    fun dispose() {
        broadcastJob?.cancel()
        broadcastJob = null
        sinks.clear()
        scope.cancel()
    }

    private fun emit(payload: Map<String, Any?>) {
        val dead = mutableListOf<EventChannel.EventSink>()
        sinks.forEach { sink ->
            runCatching { sink.success(payload) }.onFailure { dead += sink }
        }
        sinks.removeAll(dead.toSet())
    }
}

private fun Map<String, Any?>.toSongOrNull(): Song? {
    val videoId = this["videoId"]?.toString()?.trim().orEmpty()
    if (videoId.isBlank()) return null
    return Song(
        videoId = videoId,
        title = this["title"]?.toString().orEmpty().ifBlank { "Unknown title" },
        artist = this["artist"]?.toString().orEmpty().ifBlank { "Unknown artist" },
        thumbnail = this["thumbnail"]?.toString().orEmpty(),
        duration = this["duration"]?.toString(),
        album = this["album"]?.toString(),
        localPath = this["localPath"]?.toString(),
        isDownloaded = (this["isDownloaded"] as? Boolean) == true,
        artworkUrl = this["artworkUrl"]?.toString()
    )
}

private fun Song.toFlutterMap(): Map<String, Any?> =
    mapOf(
        "videoId" to videoId,
        "title" to title,
        "artist" to artist,
        "thumbnail" to thumbnail,
        "artworkUrl" to artworkUrl,
        "duration" to duration,
        "album" to album,
        "localPath" to localPath,
        "isDownloaded" to isDownloaded
    )
