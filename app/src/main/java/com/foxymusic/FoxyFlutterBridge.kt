package com.foxymusic

import android.app.Activity
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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Collections
import java.util.LinkedHashMap
import java.util.concurrent.ConcurrentHashMap
import androidx.compose.ui.graphics.toArgb

class FoxyFlutterBridge(
    private val context: Context
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sinks = Collections.newSetFromMap(ConcurrentHashMap<EventChannel.EventSink, Boolean>())
    private var broadcastJob: Job? = null

    init {
        synchronized(FoxyFlutterBridge::class.java) {
            activeBridge = this
        }
    }

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
            val key = "${ui.queueIndex}|${ui.currentSong?.videoId.orEmpty()}|${FoxyDynamicTheme.offlineArtworkPath.value.orEmpty()}"
            synchronized(this) {
                if (key != lastKey) {
                    lastKey = key
                    epoch += 1L
                }
                return epoch
            }
        }
    }

    private fun flutterPlayerStateMap(ui: PlayerUiState): Map<String, Any?> {
        val settings = FoxySettings.state.value
        val songAccent = FoxyDynamicTheme.accent.value
        val likedIds = FoxyLibraryStore.state.value.likedSongs.map { it.videoId }.toSet()
        val liked = ui.currentSong?.let { likedIds.contains(it.videoId) } == true
        val currentSongMap: Map<String, Any?>? = ui.currentSong?.let { s ->
            val m = s.toFlutterMap().toMutableMap()
            val path = FoxyDynamicTheme.offlineArtworkPath.value
            if (!path.isNullOrBlank() && File(path).name == "${s.videoId}.jpg") {
                m["offlineArtworkPath"] = path
            }
            m.toMap()
        }
        return mapOf(
            "playerEpoch" to playerEpoch.bumpIfNeeded(ui),
            "isPlaying" to ui.isPlaying,
            "isBuffering" to ui.isBuffering,
            "positionMs" to ui.positionMs,
            "durationMs" to ui.durationMs,
            "queueIndex" to ui.queueIndex,
            "shuffleEnabled" to ui.shuffleEnabled,
            "repeatMode" to ui.repeatMode.name,
            "error" to ui.error,
            "queue" to ui.queue.map { q -> q.toFlutterMap() },
            "currentSong" to currentSongMap,
            "songIsLiked" to liked,
            "dynamicSongColors" to settings.dynamicSongColors,
            "songAccentArgb" to (
                if (settings.dynamicSongColors) songAccent?.toArgb() else null
            ),
            "paletteEpoch" to FoxyDynamicTheme.paletteEpoch.value,
        )
    }

    private fun emitLivePlayerStateEvent(
        ui: PlayerUiState = FoxyPlayerConnection.state.value,
    ) {
        if (sinks.isEmpty()) return
        emit(
            mapOf(
                "type" to FoxyFlutterChannels.Events.PLAYER_STATE,
                "state" to flutterPlayerStateMap(ui),
            ),
        )
    }

    /** Kotlin updates player asynchronously; push snapshots so Flutter mini-player appears. */
    private fun scheduleFlutterPlayerStatePush() {
        emitLivePlayerStateEvent()
        if (sinks.isEmpty()) return
        scope.launch {
            delay(50)
            emitLivePlayerStateEvent()
            delay(200)
            emitLivePlayerStateEvent()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            FoxyFlutterChannels.Methods.INIT -> {
                result.success(null)
            }
            FoxyFlutterChannels.Methods.MOVE_TASK_TO_BACK -> {
                val act = context as? Activity
                if (act != null) {
                    act.moveTaskToBack(true)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            FoxyFlutterChannels.Methods.GET_PLAYER_STATE -> {
                result.success(flutterPlayerStateMap(FoxyPlayerConnection.state.value))
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
                        "playerSeekMotion" to settings.playerSeekMotion,
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
                val playerProgressStyle = call.argument<Number>("playerProgressStyle")?.toInt()
                val playerSeekMotion = call.argument<Number>("playerSeekMotion")?.toInt()
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
                        autoBackupEnabled = autoBackupEnabled ?: current.autoBackupEnabled,
                        playerProgressStyle = playerProgressStyle?.coerceIn(0, 3)
                            ?: current.playerProgressStyle,
                        playerSeekMotion = playerSeekMotion?.coerceIn(0, 2)
                            ?: current.playerSeekMotion
                    )
                }
                result.success(null)
                emit(mapOf("type" to FoxyFlutterChannels.Events.APPEARANCE_CHANGED))
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
                scope.launch {
                    runCatching {
                        withContext(Dispatchers.IO) {
                            FoxyLibraryStore.refreshDownloadsFromDisk(context.applicationContext)
                        }
                    }
                    val library = FoxyLibraryStore.state.value
                    val ytSummaries = withContext(Dispatchers.IO) {
                        if (FoxyAccount.state.value.isSignedIn) {
                            runCatching { YTMusicAuthApi.fetchLibraryPlaylists(100) }.getOrElse { emptyList() }
                        } else {
                            emptyList()
                        }
                    }
                    val localPlaylistMaps = FoxyUserPlaylists.all().map { pl ->
                        mapOf(
                            "id" to pl.id,
                            "name" to pl.name,
                            "songs" to pl.songs.map { it.toFlutterMap() },
                            "source" to "local",
                        )
                    }
                    val ytPlaylistMaps = ytSummaries.map { s ->
                        mapOf(
                            "id" to s.id,
                            "name" to s.title,
                            "songs" to emptyList<Map<String, Any?>>(),
                            "source" to "youtube",
                            "songCount" to s.songCount,
                        )
                    }
                    result.success(
                        mapOf(
                            "downloads" to library.downloadedSongs.map { it.toFlutterMap() },
                            "liked" to library.likedSongs.map { it.toFlutterMap() },
                            "history" to library.historySongs.map { it.toFlutterMap() },
                            "saved" to library.savedSongs.map { it.toFlutterMap() },
                            "playlists" to library.savedSongs.map { it.toFlutterMap() },
                            "mostPlayed" to library.mostPlayedFromHistory().map { it.toFlutterMap() },
                            "recentlyAdded" to library.recentlyMerged().map { it.toFlutterMap() },
                            "userPlaylists" to localPlaylistMaps + ytPlaylistMaps,
                        ),
                    )
                }
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
                            val byTitle = LinkedHashMap<String, RecommendationSection>()
                            fun addAll(list: List<RecommendationSection>) {
                                for (s in list) {
                                    if (s.songs.isEmpty()) continue
                                    if (!byTitle.containsKey(s.title)) {
                                        byTitle[s.title] = RecommendationSection(
                                            s.title,
                                            s.songs.take(20),
                                        )
                                    }
                                }
                            }
                            addAll(runCatching { YTMusicApi.homeRecommendations() }.getOrElse { emptyList() })
                            addAll(runCatching { YTMusicApi.chartsSections() }.getOrElse { emptyList() })
                            if (byTitle.isEmpty()) {
                                addAll(
                                    listOf(
                                        RecommendationSection(
                                            "Quick picks",
                                            YTMusicApi.search("new music songs").take(24),
                                        ),
                                        RecommendationSection(
                                            "Trending now",
                                            YTMusicApi.search("top songs today").take(16),
                                        ),
                                        RecommendationSection(
                                            "New releases",
                                            YTMusicApi.search("new release music").take(16),
                                        ),
                                        RecommendationSection(
                                            "Focus station",
                                            YTMusicApi.getMoodMix("Focus").take(16),
                                        ),
                                    ).filter { it.songs.isNotEmpty() },
                                )
                            }
                            val sections = byTitle.values.take(14).map { sec ->
                                mapOf(
                                    "title" to sec.title,
                                    "songs" to sec.songs.map { it.toFlutterMap() },
                                )
                            }
                            mapOf("sections" to sections)
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
                    emitLivePlayerStateEvent()
                    result.success(null)
                    scheduleFlutterPlayerStatePush()
                }
            }
            FoxyFlutterChannels.Methods.TOGGLE_PLAY_PAUSE -> {
                FoxyPlayerConnection.togglePlayPause()
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.NEXT -> {
                FoxyPlayerConnection.playNext()
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.PREVIOUS -> {
                FoxyPlayerConnection.playPrevious()
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.PAUSE -> {
                FoxyPlayerConnection.pause()
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.PLAY_QUEUE -> {
                val list = call.argument<List<Map<String, Any?>>>("songs").orEmpty()
                val songs = list.mapNotNull { it.toSongOrNull() }
                val startIndex = (call.argument<Number>("startIndex")?.toInt() ?: 0).coerceAtLeast(0)
                val radioTail = call.argument<Boolean>("radioTail") == true
                if (songs.isEmpty()) {
                    result.error("bad_args", "songs is required", null)
                } else {
                    FoxyPlayerConnection.playQueue(
                        context,
                        songs,
                        startIndex.coerceAtMost(songs.lastIndex),
                        radioTail,
                    )
                    emitLivePlayerStateEvent()
                    result.success(null)
                    scheduleFlutterPlayerStatePush()
                }
            }
            FoxyFlutterChannels.Methods.SKIP_TO_QUEUE_INDEX -> {
                val index = (call.argument<Number>("index")?.toInt() ?: 0).coerceAtLeast(0)
                FoxyPlayerConnection.skipToQueueIndex(context, index)
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.REMOVE_FROM_QUEUE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.removeFromQueue(it) }
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.ENQUEUE_PLAY_NEXT -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.enqueuePlayNext(it) }
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.ADD_TO_QUEUE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.addToQueue(it) }
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.SEEK_TO -> {
                val pos = (call.argument<Number>("positionMs")?.toLong() ?: 0L).coerceAtLeast(0L)
                FoxyPlayerConnection.seekTo(pos)
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.TOGGLE_SHUFFLE -> {
                FoxyPlayerConnection.toggleShuffle()
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.CYCLE_REPEAT_MODE -> {
                FoxyPlayerConnection.cycleRepeatMode()
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.LIKE -> {
                val song = call.argument<Map<String, Any?>>("song")?.toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "song is required", null)
                } else {
                    FoxyLibraryStore.toggleLiked(song)
                    result.success(null)
                    emitLivePlayerStateEvent()
                    scheduleFlutterPlayerStatePush()
                }
            }
            FoxyFlutterChannels.Methods.UNLIKE -> {
                val song = call.argument<Map<String, Any?>>("song")?.toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "song is required", null)
                } else {
                    FoxyLibraryStore.toggleLiked(song)
                    result.success(null)
                    emitLivePlayerStateEvent()
                    scheduleFlutterPlayerStatePush()
                }
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
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.CANCEL_SLEEP_TIMER -> {
                FoxyPlayerConnection.cancelSleepTimer()
                result.success(null)
                scheduleFlutterPlayerStatePush()
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
            FoxyFlutterChannels.Methods.SET_PLAYBACK_SPEED -> {
                val speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.5f, 2f)
                val pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1f).coerceIn(0.5f, 2f)
                FoxyPlayerConnection.setPlaybackAdjustments(speed, pitch)
                result.success(null)
            }
            FoxyFlutterChannels.Methods.PLAYLIST_CREATE -> {
                val name = call.argument<String>("name").orEmpty()
                if (FoxyAccount.state.value.isSignedIn) {
                    scope.launch {
                        val remoteId = withContext(Dispatchers.IO) {
                            YTMusicAuthApi.createPlaylist(name)
                        }
                        if (remoteId == null) {
                            FoxyUserPlaylists.create(name)
                        }
                        result.success(null)
                        emitLibraryFeedChanged()
                    }
                } else {
                    FoxyUserPlaylists.create(name)
                    result.success(null)
                    emitLibraryFeedChanged()
                }
            }
            FoxyFlutterChannels.Methods.PLAYLIST_RENAME -> {
                val id = call.argument<String>("playlistId").orEmpty().trim()
                val name = call.argument<String>("name").orEmpty()
                if (id.isBlank()) {
                    result.error("bad_args", "playlistId required", null)
                } else if (isLocalUserPlaylistId(id)) {
                    FoxyUserPlaylists.rename(id, name)
                    result.success(null)
                    emitLibraryFeedChanged()
                } else {
                    scope.launch {
                        withContext(Dispatchers.IO) { YTMusicAuthApi.renamePlaylist(id, name) }
                        result.success(null)
                        emitLibraryFeedChanged()
                    }
                }
            }
            FoxyFlutterChannels.Methods.PLAYLIST_DELETE -> {
                val id = call.argument<String>("playlistId").orEmpty().trim()
                if (id.isBlank()) {
                    result.error("bad_args", "playlistId required", null)
                } else if (isLocalUserPlaylistId(id)) {
                    FoxyUserPlaylists.delete(id)
                    result.success(null)
                    emitLibraryFeedChanged()
                } else {
                    scope.launch {
                        withContext(Dispatchers.IO) { YTMusicAuthApi.deletePlaylist(id) }
                        result.success(null)
                        emitLibraryFeedChanged()
                    }
                }
            }
            FoxyFlutterChannels.Methods.PLAYLIST_ADD_SONG -> {
                val id = call.argument<String>("playlistId").orEmpty().trim()
                val song = call.argument<Map<String, Any?>>("song")?.toSongOrNull()
                if (id.isBlank() || song == null) {
                    result.error("bad_args", "playlistId and song required", null)
                } else if (isLocalUserPlaylistId(id)) {
                    FoxyUserPlaylists.addSong(id, song)
                    result.success(null)
                    emitLibraryFeedChanged()
                } else {
                    scope.launch {
                        withContext(Dispatchers.IO) { YTMusicAuthApi.addVideoToPlaylist(id, song.videoId) }
                        result.success(null)
                        emitLibraryFeedChanged()
                    }
                }
            }
            FoxyFlutterChannels.Methods.PLAYLIST_REMOVE_SONG -> {
                val id = call.argument<String>("playlistId").orEmpty().trim()
                val vid = call.argument<String>("videoId").orEmpty().trim()
                if (id.isBlank() || vid.isBlank()) {
                    result.error("bad_args", "playlistId and videoId required", null)
                } else if (!isLocalUserPlaylistId(id)) {
                    result.success(null)
                } else {
                    FoxyUserPlaylists.removeSong(id, vid)
                    result.success(null)
                    emitLibraryFeedChanged()
                }
            }
            FoxyFlutterChannels.Methods.PLAYLIST_FETCH_SONGS -> {
                val id = call.argument<String>("playlistId").orEmpty().trim()
                if (id.isBlank()) {
                    result.error("bad_args", "playlistId required", null)
                } else if (isLocalUserPlaylistId(id)) {
                    val pl = FoxyUserPlaylists.all().find { it.id == id }
                    result.success(pl?.songs?.map { it.toFlutterMap() }.orEmpty())
                } else {
                    scope.launch {
                        val songs = withContext(Dispatchers.IO) {
                            YTMusicAuthApi.browsePlaylistTracks(id)
                        }
                        result.success(songs.map { it.toFlutterMap() })
                    }
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
                val mode = call.argument<String>("mode")?.trim()?.lowercase().orEmpty()
                    .ifBlank { "webview" }
                when (mode) {
                    "ytmapp", "ytm_app", "app" -> {
                        val ytm = "com.google.android.apps.youtube.music"
                        val pm = context.packageManager
                        val baseUri = Uri.parse("https://music.youtube.com/")
                        val ytmOnly = Intent(Intent.ACTION_VIEW, baseUri)
                            .setPackage(ytm)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        val generic = Intent(Intent.ACTION_VIEW, baseUri)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        val launched = runCatching {
                            if (ytmOnly.resolveActivity(pm) != null) {
                                context.startActivity(ytmOnly)
                            } else {
                                context.startActivity(generic)
                            }
                            true
                        }.getOrElse { false }
                        result.success(launched)
                    }
                    "browser", "external" -> {
                        val uri = Uri.parse(
                            "https://accounts.google.com/ServiceLogin?service=youtube&continue=" +
                                Uri.encode("https://music.youtube.com/"),
                        )
                        val intent = Intent(Intent.ACTION_VIEW, uri)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            context.startActivity(intent)
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                    else -> {
                        val intent = Intent(context, YtmWebLoginActivity::class.java)
                        try {
                            context.startActivity(intent)
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                }
            }
            FoxyFlutterChannels.Methods.ACCOUNT_SIGN_OUT -> {
                FoxyAccount.signOut()
                emitAccountSessionUpdated()
                result.success(null)
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
            // Collect player state directly — do not map to Unit (that suppresses emissions).
            launch {
                FoxyPlayerConnection.state.collect { ui ->
                    emitLivePlayerStateEvent(ui)
                }
            }
            launch {
                merge(
                    FoxyDynamicTheme.accent.map { },
                    FoxyDynamicTheme.paletteEpoch.map { },
                    FoxyDynamicTheme.offlineArtworkPath.map { },
                    FoxySettings.state.map { },
                    FoxyLibraryStore.notifyEpoch.map { },
                ).collect {
                    emitLivePlayerStateEvent()
                }
            }
            launch {
                FoxyLibraryStore.notifyEpoch
                    .debounce(120)
                    .collect { _ ->
                        val progress = FoxyLibraryStore.state.value.downloadProgress
                        emit(
                            mapOf(
                                "type" to FoxyFlutterChannels.Events.LIBRARY_DOWNLOAD_PROGRESS,
                                "downloadProgress" to progress
                            )
                        )
                    }
            }
            launch {
                var lastDownloadedIds: List<String> = emptyList()
                FoxyLibraryStore.notifyEpoch.collect { _ ->
                    val ids =
                        FoxyLibraryStore.state.value.downloadedSongs.map { it.videoId }
                    if (ids != lastDownloadedIds) {
                        lastDownloadedIds = ids
                        emit(mapOf("type" to FoxyFlutterChannels.Events.LIBRARY_DOWNLOADS_CHANGED))
                    }
                }
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
        synchronized(FoxyFlutterBridge::class.java) {
            if (activeBridge == this) activeBridge = null
        }
        broadcastJob?.cancel()
        broadcastJob = null
        sinks.clear()
        scope.cancel()
    }

    private fun emitAccountSessionUpdated() {
        emit(mapOf("type" to FoxyFlutterChannels.Events.ACCOUNT_CHANGED))
        emitLibraryFeedChanged()
    }

    private fun emitLibraryFeedChanged() {
        emit(mapOf("type" to FoxyFlutterChannels.Events.LIBRARY_FEED_CHANGED))
    }

    companion object {
        @Volatile
        private var activeBridge: FoxyFlutterBridge? = null

        /**
         * Call after [FoxyAccount.updateSession] from non-bridge code (e.g. [YtmWebLoginActivity])
         * so Flutter reloads account and library.
         */
        fun notifyAccountSessionUpdated() {
            activeBridge?.emitAccountSessionUpdated()
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        val dead = mutableListOf<EventChannel.EventSink>()
        sinks.forEach { sink ->
            runCatching { sink.success(payload) }.onFailure { dead += sink }
        }
        sinks.removeAll(dead.toSet())
    }
}

private val localUserPlaylistIdRegex =
    Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

private fun isLocalUserPlaylistId(id: String): Boolean = localUserPlaylistIdRegex.matches(id)

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

private fun FoxyLibraryState.mostPlayedFromHistory(): List<Song> =
    historySongs.groupingBy { it.videoId }.eachCount()
        .entries.sortedByDescending { it.value }
        .mapNotNull { (vid, _) -> historySongs.findLast { it.videoId == vid } }

private fun FoxyLibraryState.recentlyMerged(): List<Song> {
    val out = ArrayList<Song>()
    val seen = HashSet<String>()
    for (s in likedSongs.asReversed()) {
        if (seen.add(s.videoId)) out.add(s)
    }
    for (s in downloadedSongs.asReversed()) {
        if (seen.add(s.videoId)) out.add(s)
    }
    for (s in historySongs) {
        if (seen.add(s.videoId)) out.add(s)
    }
    return out
}
