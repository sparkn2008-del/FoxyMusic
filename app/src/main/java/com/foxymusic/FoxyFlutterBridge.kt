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
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Collections
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import androidx.compose.ui.graphics.toArgb

class FoxyFlutterBridge(
    private val context: Context
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sinks = Collections.newSetFromMap(ConcurrentHashMap<EventChannel.EventSink, Boolean>())
    private var broadcastJob: Job? = null
    @Volatile
    private var lastFullEmitKey: String = ""
    @Volatile
    private var lastLightEmitAtMs: Long = 0L

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

    private fun flutterPlayerStateMap(
        ui: PlayerUiState,
        includeQueue: Boolean,
    ): Map<String, Any?> {
        val settings = FoxySettings.state.value
        val songAccent = FoxyDynamicTheme.accent.value
        val likedIds = FoxyLibraryStore.state.value.likedSongs.map { it.videoId }.toSet()
        val liked = ui.currentSong?.let { likedIds.contains(it.videoId) } == true
        val currentSongMap: Map<String, Any?>? = ui.currentSong?.let { s ->
            val m = s.toFlutterMap(context).toMutableMap()
            if (m["offlineArtworkPath"] == null && s.isDownloaded) {
                FoxyDynamicTheme.offlineArtworkPath.value
                    ?.takeIf { p -> File(p).isFile && File(p).length() > 0L }
                    ?.let { p -> m["offlineArtworkPath"] = p }
            }
            m.toMap()
        }
        val payload = linkedMapOf<String, Any?>(
            "playerEpoch" to playerEpoch.bumpIfNeeded(ui),
            "isPlaying" to ui.isPlaying,
            "isBuffering" to ui.isBuffering,
            "positionMs" to ui.positionMs,
            "durationMs" to ui.durationMs,
            "queueIndex" to ui.queueIndex,
            "shuffleEnabled" to ui.shuffleEnabled,
            "repeatMode" to ui.repeatMode.name,
            "error" to ui.error,
            "currentSong" to currentSongMap,
            "songIsLiked" to liked,
            "dynamicSongColors" to settings.dynamicSongColors,
            "songAccentArgb" to (
                if (settings.dynamicSongColors) songAccent?.toArgb() else null
            ),
            "paletteEpoch" to FoxyDynamicTheme.paletteEpoch.value,
            "canPlayPrevious" to MusicPlayer.canPlayPrevious(),
            "canPlayNext" to MusicPlayer.mediaNotificationHasNext(),
            "crossfadeMs" to settings.crossfadeMs,
            "lyricsPreferLrclib" to settings.lyricsPreferLrclib,
            "lyricsRomanize" to settings.lyricsRomanize,
            "normalizeVolume" to settings.normalizeVolume,
            "streamQualityTier" to settings.streamQualityTier,
            "streamBitrate" to ui.streamBitrate,
            "streamCodec" to ui.streamCodec,
            "streamMimeType" to ui.streamMimeType,
            "streamSampleRate" to ui.streamSampleRate,
            "streamItag" to ui.streamItag,
            "streamSource" to ui.streamSource,
        )
        if (includeQueue) {
            payload["queue"] = ui.queue.map { q -> q.toFlutterMap(context) }
        }
        return payload
    }

    private fun emitLivePlayerStateEvent(
        ui: PlayerUiState = FoxyPlayerConnection.state.value,
        includeQueue: Boolean = true,
    ) {
        if (sinks.isEmpty()) return
        emit(
            mapOf(
                "type" to FoxyFlutterChannels.Events.PLAYER_STATE,
                "state" to flutterPlayerStateMap(ui, includeQueue),
            ),
        )
    }

    /** One immediate + one delayed full snapshot after async play/queue changes. */
    private fun scheduleFlutterPlayerStatePush() {
        emitLivePlayerStateEvent(includeQueue = true)
        if (sinks.isEmpty()) return
        scope.launch {
            delay(80)
            emitLivePlayerStateEvent(includeQueue = true)
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
                result.success(
                    flutterPlayerStateMap(FoxyPlayerConnection.state.value, includeQueue = true),
                )
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
                        "persistentQueue" to settings.persistentQueue,
                        "continuePlaybackWhenDismissed" to settings.continuePlaybackWhenDismissed,
                        "saveHistory" to settings.saveHistory,
                        "sponsorBlockEnabled" to settings.sponsorBlockEnabled,
                        "crossfadeMs" to settings.crossfadeMs,
                        "lyricsPreferLrclib" to settings.lyricsPreferLrclib,
                        "lyricsRomanize" to settings.lyricsRomanize,
                        "streamQualityTier" to settings.streamQualityTier,
                        "downloadQualityTier" to settings.downloadQualityTier,
                        "contentLanguageTag" to settings.contentLanguageTag,
                        "appLanguageTag" to settings.appLanguageTag,
                        "proxyEnabled" to settings.proxyEnabled,
                        "proxyEndpoint" to settings.proxyEndpoint,
                        "normalizeVolume" to settings.normalizeVolume,
                        "skipSilence" to settings.skipSilence,
                        "autoBackupEnabled" to settings.autoBackupEnabled,
                        "autoCheckUpdates" to settings.autoCheckUpdates,
                        "updateNotifications" to settings.updateNotifications,
                        "accentArgb" to palette.accent.toArgb(),
                        "backgroundArgb" to palette.background.toArgb(),
                        "surfaceArgb" to palette.surface.toArgb(),
                        "surfaceHighArgb" to palette.surfaceHigh.toArgb(),
                        "mutedArgb" to palette.muted.toArgb(),
                        "homeBackgroundPath" to FoxyHomeBackground.getPath(context).orEmpty(),
                    )
                )
            }
            FoxyFlutterChannels.Methods.PICK_HOME_BACKGROUND -> {
                val act = context as? MainActivity
                if (act == null) {
                    result.error("no_activity", "Cannot open image picker", null)
                } else {
                    act.pickHomeBackground(result)
                }
            }
            FoxyFlutterChannels.Methods.CLEAR_HOME_BACKGROUND -> {
                val act = context as? MainActivity
                if (act == null) {
                    FoxyHomeBackground.clear(context)
                    emitAppearanceChanged()
                    result.success(mapOf("ok" to true))
                } else {
                    act.clearHomeBackground(result)
                }
            }
            FoxyFlutterChannels.Methods.RESTART_APP -> {
                val act = context as? MainActivity
                if (act == null) {
                    result.error("no_activity", "Cannot restart app", null)
                } else {
                    act.restartApp()
                    result.success(null)
                }
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
                val lyricsRomanize = call.argument<Boolean>("lyricsRomanize")
                val streamQualityTier = call.argument<Number>("streamQualityTier")?.toInt()
                val downloadQualityTier = call.argument<Number>("downloadQualityTier")?.toInt()
                val contentLanguageTag = call.argument<String>("contentLanguageTag")
                val appLanguageTag = call.argument<String>("appLanguageTag")
                val proxyEnabled = call.argument<Boolean>("proxyEnabled")
                val proxyEndpoint = call.argument<String>("proxyEndpoint")
                val normalizeVolume = call.argument<Boolean>("normalizeVolume")
                val skipSilence = call.argument<Boolean>("skipSilence")
                val autoBackupEnabled = call.argument<Boolean>("autoBackupEnabled")
                val autoCheckUpdates = call.argument<Boolean>("autoCheckUpdates")
                val updateNotifications = call.argument<Boolean>("updateNotifications")
                val continuePlaybackWhenDismissed =
                    call.argument<Boolean>("continuePlaybackWhenDismissed")
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
                        lyricsRomanize = lyricsRomanize ?: current.lyricsRomanize,
                        streamQualityTier = streamQualityTier?.coerceIn(0, 3) ?: current.streamQualityTier,
                        downloadQualityTier = downloadQualityTier?.coerceIn(0, 3)
                            ?: current.downloadQualityTier,
                        contentLanguageTag = contentLanguageTag?.trim()?.takeIf { it.isNotEmpty() }
                            ?: current.contentLanguageTag,
                        appLanguageTag = appLanguageTag?.let { it.trim() } ?: current.appLanguageTag,
                        proxyEnabled = proxyEnabled ?: current.proxyEnabled,
                        proxyEndpoint = proxyEndpoint?.trim() ?: current.proxyEndpoint,
                        normalizeVolume = normalizeVolume ?: current.normalizeVolume,
                        skipSilence = skipSilence ?: current.skipSilence,
                        autoBackupEnabled = autoBackupEnabled ?: current.autoBackupEnabled,
                        autoCheckUpdates = autoCheckUpdates ?: current.autoCheckUpdates,
                        updateNotifications = updateNotifications ?: current.updateNotifications,
                        continuePlaybackWhenDismissed = continuePlaybackWhenDismissed
                            ?: current.continuePlaybackWhenDismissed,
                    )
                }
                result.success(null)
                if (crossfadeMs != null || normalizeVolume != null || skipSilence != null) {
                    FoxyPlayerConnection.refreshPlaybackAudioSettings()
                }
                FoxyBackup.requestAutoBackup(context.applicationContext)
                emit(mapOf("type" to FoxyFlutterChannels.Events.APPEARANCE_CHANGED))
                scheduleFlutterPlayerStatePush()
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
            FoxyFlutterChannels.Methods.SONG_MENU_CONTEXT -> {
                val library = FoxyLibraryStore.state.value
                val settings = FoxySettings.state.value
                val playlists = FoxyUserPlaylists.all().map { pl ->
                    mapOf(
                        "id" to pl.id,
                        "name" to pl.name,
                        "songs" to emptyList<Map<String, Any?>>(),
                        "source" to "local",
                    )
                }
                result.success(
                    mapOf(
                        "likedIds" to library.likedSongs.map { it.videoId },
                        "downloadedIds" to library.downloadedSongs.map { it.videoId },
                        "userPlaylists" to playlists,
                        "lyricsPreferLrclib" to settings.lyricsPreferLrclib,
                        "lyricsRomanize" to settings.lyricsRomanize,
                        "crossfadeMs" to settings.crossfadeMs,
                        "normalizeVolume" to settings.normalizeVolume,
                    ),
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
                    val explore = withContext(Dispatchers.IO) {
                        runCatching {
                            YTMusicApi.search("trending songs today").take(24)
                        }.getOrElse { emptyList() }
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
                            "explore" to explore.map { it.toFlutterMap() },
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
                                mapOf(
                                    "songs" to YTMusicApi.search(query)
                                        .take(limit)
                                        .map { it.toFlutterMap() },
                                )
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure { result.error("search_failed", it.message ?: "Search failed", null) }
                    }
                }
            }
            FoxyFlutterChannels.Methods.SEARCH_ALL -> {
                val query = call.argument<String>("query").orEmpty().trim()
                val limit = (call.argument<Number>("limit")?.toInt() ?: 28).coerceIn(8, 40)
                if (query.isBlank()) {
                    result.success(
                        mapOf(
                            "songs" to emptyList<Map<String, Any?>>(),
                            "videos" to emptyList<Map<String, Any?>>(),
                            "albums" to emptyList<Map<String, Any?>>(),
                            "artists" to emptyList<Map<String, Any?>>(),
                        ),
                    )
                } else {
                    scope.launch {
                        val payload = runCatching {
                            withContext(Dispatchers.IO) {
                                YTMusicApi.searchAll(query, limit).mapValues { (key, list) ->
                                        val filtered = list.filter { it.videoId.isNotBlank() }
                                    filtered.map { it.toFlutterMap() }
                                }
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure {
                                result.error("search_failed", it.message ?: "Search failed", null)
                            }
                    }
                }
            }
            FoxyFlutterChannels.Methods.HOME_FEED -> {
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            val byTitle = LinkedHashMap<String, RecommendationSection>()
                            val seenVideoIds = LinkedHashSet<String>()
                            fun addAll(list: List<RecommendationSection>) {
                                for (s in list) {
                                    val songs = s.songs
                                        .filter { it.videoId.isNotBlank() }
                                        .distinctBy { it.videoId }
                                        .filter { seenVideoIds.add(it.videoId) }
                                        .take(20)
                                    if (songs.isEmpty()) continue
                                    if (!byTitle.containsKey(s.title)) {
                                        byTitle[s.title] = RecommendationSection(
                                            s.title,
                                            songs,
                                        )
                                    }
                                }
                            }
                            val discoveryJobs = listOf(
                                async {
                                    runCatching { YTMusicApi.homeRecommendations() }
                                        .getOrElse { emptyList() }
                                },
                                async {
                                    runCatching { YTMusicApi.chartsSections() }
                                        .getOrElse { emptyList() }
                                },
                                async {
                                    listOf(
                                        RecommendationSection(
                                            "Foxy charts",
                                            YTMusicApi.search("top songs today global").take(18),
                                        ),
                                        RecommendationSection(
                                            "India pulse",
                                            YTMusicApi.search("india trending songs hindi punjabi bollywood").take(18),
                                        ),
                                    )
                                },
                                async {
                                    listOf(
                                        RecommendationSection(
                                            "Fresh releases",
                                            YTMusicApi.search("new release songs this week").take(18),
                                        ),
                                        RecommendationSection(
                                            "Hidden gems",
                                            YTMusicApi.search("underrated indie pop electronic songs").take(18),
                                        ),
                                    )
                                },
                                async {
                                    listOf(
                                        RecommendationSection(
                                            "Music videos",
                                            YTMusicApi.videos("trending music videos").take(16),
                                        ),
                                        RecommendationSection(
                                            "Covers and remixes",
                                            YTMusicApi.search("popular covers remixes songs").take(18),
                                        ),
                                    )
                                },
                                async {
                                    listOf(
                                        RecommendationSection(
                                            "Late night drive",
                                            YTMusicApi.search("late night drive songs synthwave pop").take(18),
                                        ),
                                        RecommendationSection(
                                            "Focus flow",
                                            YTMusicApi.search("focus flow music electronic lofi").take(18),
                                        ),
                                    )
                                },
                            )
                            discoveryJobs.awaitAll().forEach(::addAll)
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
                                    ).filter { it.songs.isNotEmpty() },
                                )
                            }
                            fun layoutFor(title: String): String {
                                val t = title.lowercase(Locale.US)
                                return when {
                                    t.contains("video") -> "video"
                                    t.contains("chart") || t.contains("pulse") ||
                                        t.contains("trending") -> "chart"
                                    t.contains("artist") || t.contains("similar") -> "artist"
                                    t.contains("release") || t.contains("discover") ||
                                        t.contains("cover") || t.contains("remix") ||
                                        t.contains("daily") || t.contains("fresh") ||
                                        t.contains("gem") || t.contains("drive") ||
                                        t.contains("focus") -> "grid"
                                    else -> "cards"
                                }
                            }
                            val sections = byTitle.values.take(18).map { sec ->
                                mapOf(
                                    "title" to sec.title,
                                    "layout" to layoutFor(sec.title),
                                    "songs" to sec.songs.map { it.toFlutterMap() },
                                )
                            }.ifEmpty {
                                YTMusicApi.fallbackRecommendationSections().map { sec ->
                                    mapOf(
                                        "title" to sec.title,
                                        "layout" to "cards",
                                        "songs" to sec.songs.map { it.toFlutterMap() },
                                    )
                                }
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
                // Match [MusicPlayer.playNextFromMediaSession]: wrap to front when repeat-all.
                val loopAll = FoxyPlayerConnection.state.value.repeatMode == RepeatMode.All
                FoxyPlayerConnection.playNext(loop = loopAll)
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
                val offlineQueueOnly = call.argument<Boolean>("offlineQueueOnly") == true
                if (songs.isEmpty()) {
                    result.error("bad_args", "songs is required", null)
                } else {
                    FoxyPlayerConnection.playQueue(
                        context,
                        songs,
                        startIndex.coerceAtMost(songs.lastIndex),
                        radioTail,
                        offlineQueueOnly,
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
            FoxyFlutterChannels.Methods.MOVE_QUEUE_ITEM -> {
                val from = (call.argument<Number>("fromIndex")?.toInt() ?: -1)
                val to = (call.argument<Number>("toIndex")?.toInt() ?: -1)
                FoxyPlayerConnection.moveQueueItem(from, to)
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
                                fetchLyricsForUi(context, song)
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure { result.error("lyrics_failed", it.message ?: "Lyrics failed", null) }
                    }
                }
            }
            FoxyFlutterChannels.Methods.STORAGE_STATS -> {
                result.success(FoxyStorageStats.snapshot(context))
            }
            FoxyFlutterChannels.Methods.CLEAR_STREAM_CACHE -> {
                scope.launch {
                    val payload = withContext(Dispatchers.IO) {
                        val cleared = FoxyCache.clear(context.applicationContext)
                        FoxyStorageStats.snapshot(context) + mapOf("clearedBytes" to cleared)
                    }
                    result.success(payload)
                }
            }
            FoxyFlutterChannels.Methods.CREATE_BACKUP -> {
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            FoxyBackup.create(context.applicationContext)
                        }
                    }
                    payload.onSuccess(result::success)
                        .onFailure { result.error("backup_failed", it.message ?: "Backup failed", null) }
                }
            }
            FoxyFlutterChannels.Methods.RESTORE_LATEST_BACKUP -> {
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            FoxyBackup.restoreLatest(context.applicationContext)
                        }
                    }
                    payload.onSuccess {
                        result.success(it)
                        emitLibraryFeedChanged()
                        emit(mapOf("type" to FoxyFlutterChannels.Events.APPEARANCE_CHANGED))
                        scheduleFlutterPlayerStatePush()
                    }.onFailure {
                        result.error("restore_failed", it.message ?: "Restore failed", null)
                    }
                }
            }
            FoxyFlutterChannels.Methods.BACKUP_STATUS -> {
                scope.launch {
                    val payload = withContext(Dispatchers.IO) {
                        FoxyBackup.status(context.applicationContext)
                    }
                    result.success(payload)
                }
            }
            FoxyFlutterChannels.Methods.GET_APP_VERSION -> {
                val (name, code) = FoxyGithubUpdate.installedVersion(context)
                result.success(
                    mapOf(
                        "versionName" to name,
                        "versionCode" to code,
                    ),
                )
            }
            FoxyFlutterChannels.Methods.CHECK_GITHUB_RELEASE -> {
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            val check = FoxyGithubUpdate.checkForUpdate(context)
                            FoxyUpdatePrefs.setLastCheckMs(context, System.currentTimeMillis())
                            check.toFlutterMap()
                        }
                    }.getOrElse {
                        mapOf(
                            "ok" to false,
                            "updateAvailable" to false,
                            "error" to (it.message ?: "check_failed"),
                            "tagName" to "",
                            "htmlUrl" to "",
                            "downloadUrl" to "",
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
                    FoxyBackup.requestAutoBackup(context.applicationContext)
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
                    FoxyBackup.requestAutoBackup(context.applicationContext)
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
                    FoxyBackup.requestAutoBackup(context.applicationContext)
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
                    FoxyBackup.requestAutoBackup(context.applicationContext)
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
                    FoxyBackup.requestAutoBackup(context.applicationContext)
                    emitLibraryFeedChanged()
                }
            }
            FoxyFlutterChannels.Methods.PLAYLIST_MOVE_SONG -> {
                val id = call.argument<String>("playlistId").orEmpty().trim()
                val from = call.argument<Number>("fromIndex")?.toInt() ?: -1
                val to = call.argument<Number>("toIndex")?.toInt() ?: -1
                if (id.isBlank()) {
                    result.error("bad_args", "playlistId required", null)
                } else if (isLocalUserPlaylistId(id)) {
                    FoxyUserPlaylists.moveSong(id, from, to)
                    result.success(null)
                    FoxyBackup.requestAutoBackup(context.applicationContext)
                    emitLibraryFeedChanged()
                } else {
                    result.success(null)
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
        maybeScheduleAutoUpdateCheck()
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
                FoxyPlayerConnection.state.collect { ui ->
                    val fullKey = buildString {
                        append(ui.queueIndex)
                        append('|')
                        append(ui.currentSong?.videoId.orEmpty())
                        append('|')
                        append(ui.queue.size)
                        append('|')
                        append(ui.shuffleEnabled)
                        append('|')
                        append(ui.repeatMode.name)
                        append('|')
                        append(ui.isPlaying)
                        append('|')
                        append(ui.isBuffering)
                        append('|')
                        append(ui.error.orEmpty())
                    }
                    if (fullKey != lastFullEmitKey) {
                        lastFullEmitKey = fullKey
                        lastLightEmitAtMs = 0L
                        emitLivePlayerStateEvent(ui, includeQueue = true)
                        return@collect
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastLightEmitAtMs < 450L) return@collect
                    lastLightEmitAtMs = now
                    emitLivePlayerStateEvent(ui, includeQueue = false)
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
                    emitLivePlayerStateEvent(includeQueue = false)
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

    fun emitAppearanceChanged() {
        emit(mapOf("type" to FoxyFlutterChannels.Events.APPEARANCE_CHANGED))
    }

    fun emitLibraryDownloadsChangedEvent() {
        emit(
            mapOf(
                "type" to FoxyFlutterChannels.Events.LIBRARY_DOWNLOADS_CHANGED,
                "downloadProgress" to FoxyLibraryStore.state.value.downloadProgress,
            ),
        )
        emitLibraryFeedChanged()
    }

    companion object {
        @Volatile
        private var activeBridge: FoxyFlutterBridge? = null

        fun applicationContext(): Context? =
            activeBridge?.context?.applicationContext

        /**
         * Call after [FoxyAccount.updateSession] from non-bridge code (e.g. [YtmWebLoginActivity])
         * so Flutter reloads account and library.
         */
        fun notifyAccountSessionUpdated() {
            activeBridge?.emitAccountSessionUpdated()
        }

        fun emitLibraryDownloadsChanged(@Suppress("UNUSED_PARAMETER") context: Context) {
            activeBridge?.emitLibraryDownloadsChangedEvent()
        }
    }

    private fun maybeScheduleAutoUpdateCheck() {
        if (!FoxySettings.state.value.autoCheckUpdates) return
        val app = context.applicationContext
        val now = System.currentTimeMillis()
        if (now - FoxyUpdatePrefs.lastCheckMs(app) < FoxyUpdatePrefs.AUTO_CHECK_INTERVAL_MS) {
            return
        }
        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    val check = FoxyGithubUpdate.checkForUpdate(app)
                    FoxyUpdatePrefs.setLastCheckMs(app, System.currentTimeMillis())
                    deliverUpdateCheckResult(app, check, notifyUser = true)
                }
            }
        }
    }

    private fun deliverUpdateCheckResult(
        ctx: Context,
        check: UpdateCheckResult,
        notifyUser: Boolean,
    ) {
        if (!check.ok || !check.updateAvailable) return
        val settings = FoxySettings.state.value
        if (notifyUser && settings.updateNotifications) {
            val tag = check.latestTag
            if (tag.isNotBlank() && tag != FoxyUpdatePrefs.lastNotifiedTag(ctx)) {
                FoxyUpdateNotifier.show(ctx, tag, check.htmlUrl, check.releaseNotes)
                FoxyUpdatePrefs.setLastNotifiedTag(ctx, tag)
            }
        }
        emit(
            mapOf(
                "type" to FoxyFlutterChannels.Events.UPDATE_AVAILABLE,
                "update" to check.toFlutterMap(),
            ),
        )
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

private fun Song.toFlutterMap(ctx: Context? = FoxyFlutterBridge.applicationContext()): Map<String, Any?> {
    val offlineArt = ctx?.let { FoxyOfflineBundle.offlineArtworkPath(it, videoId) }
        ?.takeIf { p -> File(p).isFile && File(p).length() > 0L }
    val hqArt = highQualityArtworkUrl()
    val networkThumb = hqArt.ifBlank { thumbnail }.ifBlank { artworkUrl.orEmpty() }
    return mapOf(
        "videoId" to videoId,
        "title" to title,
        "artist" to artist,
        "thumbnail" to (offlineArt ?: networkThumb),
        "artworkUrl" to (offlineArt ?: networkThumb),
        "duration" to duration,
        "album" to album,
        "localPath" to localPath,
        "isDownloaded" to isDownloaded,
        "offlineArtworkPath" to offlineArt,
    )
}

/**
 * Respects [FoxySettings.lyricsPreferLrclib] (SimpMusic-style source order).
 * Does not return stale offline cache ahead of a live LRCLIB/YouTube fetch.
 */
private suspend fun fetchLyricsForUi(context: Context, song: Song): List<Map<String, Any>> {
    val romanize = FoxySettings.state.value.lyricsRomanize
    fun mapLines(lines: List<LyricLine>) = lines.map {
        mapOf(
            "timeMs" to it.timeMs,
            "text" to LyricsRomanizer.romanizeLine(it.text, romanize),
        )
    }
    val live = LyricsRepository.fetchSyncedLines(song)
    if (live.isNotEmpty()) return mapLines(live)
    if (song.isDownloaded) {
        val cached = FoxyOfflineBundle.readCachedLyrics(context, song.videoId) ?: return emptyList()
        return cached.map { line ->
            mapOf<String, Any>(
                "timeMs" to ((line["timeMs"] as? Number)?.toLong() ?: 0L),
                "text" to LyricsRomanizer.romanizeLine(
                    line["text"]?.toString().orEmpty(),
                    romanize,
                ),
            )
        }
    }
    return emptyList()
}

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
