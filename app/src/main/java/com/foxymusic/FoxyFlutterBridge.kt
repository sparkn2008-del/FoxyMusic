package com.foxymusic

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
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
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Collections
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import androidx.compose.ui.graphics.toArgb
import org.json.JSONArray

@OptIn(FlowPreview::class)
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

    private fun searchHistoryPrefs(): FoxySearchHistoryPrefs =
        FoxySearchHistoryPrefs(context)

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
        val nativePlaying = MusicPlayer.isPlaying()
        val livePosition = MusicPlayer.currentPosition()
        val liveDuration = MusicPlayer.duration()
        val effectivePlaying = ui.isPlaying || nativePlaying
        val positionMs = if (nativePlaying || livePosition > 0L) {
            maxOf(ui.positionMs, livePosition)
        } else {
            ui.positionMs
        }
        val durationMs = when {
            liveDuration > 0L -> liveDuration
            ui.durationMs > 0L -> ui.durationMs
            else -> 0L
        }
        val effectiveBuffering = ui.isBuffering && !effectivePlaying
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
            "isPlaying" to effectivePlaying,
            "isBuffering" to effectiveBuffering,
            "positionMs" to positionMs,
            "durationMs" to durationMs,
            "queueIndex" to ui.queueIndex,
            "shuffleEnabled" to ui.shuffleEnabled,
            "repeatMode" to ui.repeatMode.name,
            "error" to ui.error,
            "volume" to ui.volume,
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
            "playerProgressStyle" to settings.playerProgressStyle,
            "playerSeekMotion" to settings.playerSeekMotion,
            "playerBackgroundStyle" to settings.playerBackgroundStyle,
            "playerStyle" to settings.playerStyle,
            "playerButtonsStyle" to settings.playerButtonsStyle,
            "playerArtworkShape" to settings.playerArtworkShape,
            "hidePlayerArtwork" to settings.hidePlayerArtwork,
            "cropArtworkSquare" to settings.cropArtworkSquare,
            "thumbnailCornerRadius" to settings.thumbnailCornerRadius,
            "lyricsAnimationStyle" to settings.lyricsAnimationStyle,
            "lyricsPreferLrclib" to settings.lyricsPreferLrclib,
            "lyricsRomanize" to settings.lyricsRomanize,
            "normalizeVolume" to settings.normalizeVolume,
            "hapticFeedback" to settings.hapticFeedback,
            "streamQualityTier" to settings.streamQualityTier,
            "streamSourcePriority" to settings.streamSourcePriority,
            "streamBitrate" to ui.streamBitrate,
            "streamCodec" to ui.streamCodec,
            "streamMimeType" to ui.streamMimeType,
            "streamSampleRate" to ui.streamSampleRate,
            "streamItag" to ui.streamItag,
            "streamSource" to ui.streamSource,
            "streamQualityLabel" to ui.streamQualityLabel,
        )
        if (includeQueue) {
            payload["queue"] = ui.queue.map { q -> q.toFlutterMap(context) }
        }
        return payload
    }
    /** Strong emit with buffering priority. */
    private fun emitLivePlayerStateEvent(
        ui: PlayerUiState = FoxyPlayerConnection.state.value,
        includeQueue: Boolean = false
    ) {
        if (sinks.isEmpty()) return

        val forceFull = (ui.isBuffering && !ui.isPlaying) || !ui.isPlaying
        emit(
            mapOf(
                "type" to FoxyFlutterChannels.Events.PLAYER_STATE,
                "state" to flutterPlayerStateMap(ui, includeQueue || forceFull)
            )
        )
    }

    /** Aggressive live updates (especially during buffering) */
    private fun scheduleFlutterPlayerStatePush(includeQueue: Boolean = false) {
        emitLivePlayerStateEvent(includeQueue = includeQueue)

        if (sinks.isEmpty()) return

        scope.launch {
            val delayMs = if (FoxyPlayerConnection.state.value.isBuffering) 80L else 150L
            delay(delayMs)
            if (sinks.isNotEmpty()) {
                emitLivePlayerStateEvent(includeQueue = includeQueue)
            }
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
            FoxyFlutterChannels.Methods.GET_RECOGNITION_STATE -> {
                result.success(FoxyRecognition.state.value.toMap())
            }
            FoxyFlutterChannels.Methods.GET_RECOGNITION_HISTORY -> {
                result.success(FoxyRecognitionHistory.all().map { it.toMap() })
            }
            FoxyFlutterChannels.Methods.CLEAR_RECOGNITION_HISTORY -> {
                FoxyRecognitionHistory.clear()
                result.success(mapOf("ok" to true))
            }
            FoxyFlutterChannels.Methods.RESOLVE_RECOGNIZED_TRACK -> {
                val title = call.argument<String>("title").orEmpty().trim()
                val artist = call.argument<String>("artist").orEmpty().trim()
                val youtubeVideoId = call.argument<String>("youtubeVideoId").orEmpty().trim()
                val spotifyUrl = call.argument<String>("spotifyUrl").orEmpty().trim()
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            val query = listOf(title, artist)
                                .filter { it.isNotBlank() }
                                .joinToString(" ")
                            val results = YTMusicApi.search(query).take(20)
                            val exact = results.firstOrNull { it.videoId == youtubeVideoId }
                            val ranked = results
                                .map {
                                    it to recognitionMatchScore(
                                        it,
                                        title = title,
                                        artist = artist,
                                        youtubeVideoId = youtubeVideoId,
                                    )
                                }
                                .sortedByDescending { it.second }
                            val best = ranked.firstOrNull()
                            val spotifyResolved =
                                if (spotifyUrl.isNotBlank()) {
                                    FoxySpotifyResolver.resolve(
                                        spotifyUrl = spotifyUrl,
                                        title = title,
                                        artist = artist,
                                        durationMs = null,
                                    )
                                } else {
                                    null
                                }
                            val strongBest = best?.takeIf { it.second >= 420 }?.first
                            val chosen = exact ?: strongBest ?: spotifyResolved?.song ?: best?.first
                            chosen?.let { song ->
                                val matchLabel = when {
                                    exact != null && song.videoId == exact.videoId ->
                                        "Exact match"
                                    (best?.second ?: 0) >= 620 ->
                                        "Strong match"
                                    spotifyResolved?.song?.videoId == song.videoId ->
                                        spotifyResolved.label
                                    else ->
                                        "Best match"
                                }
                                mapOf(
                                    "song" to song.toFlutterMap(),
                                    "matchLabel" to matchLabel,
                                )
                            }
                        }
                    }
                    payload.onSuccess(result::success)
                        .onFailure {
                            result.error(
                                "recognition_resolve_failed",
                                it.message ?: "Could not resolve recognized track",
                                null,
                            )
                        }
                }
            }
            FoxyFlutterChannels.Methods.RESOLVE_MOTION_ARTWORK -> {
                val song = (call.argument<Map<String, Any?>>("song") ?: emptyMap()).toSongOrNull()
                if (song == null) {
                    result.error("bad_args", "Missing song", null)
                } else {
                    scope.launch {
                        runCatching {
                            FoxyMotionArtworkResolver.resolve(song)?.toMap()
                        }.onSuccess(result::success)
                            .onFailure {
                                result.error(
                                    "motion_artwork_failed",
                                    it.message ?: "Could not resolve motion artwork",
                                    null,
                                )
                            }
                    }
                }
            }
            FoxyFlutterChannels.Methods.RESOLVE_SPOTIFY_TRACK -> {
                val spotifyUrl = call.argument<String>("spotifyUrl")
                val title = call.argument<String>("title")
                val artist = call.argument<String>("artist")
                val durationMs = (call.argument<Number>("durationMs"))?.toLong()
                scope.launch {
                    runCatching {
                        FoxySpotifyResolver.resolve(
                            spotifyUrl = spotifyUrl,
                            title = title,
                            artist = artist,
                            durationMs = durationMs,
                        )?.toMap()
                    }.onSuccess(result::success)
                        .onFailure {
                            result.error(
                                "spotify_resolve_failed",
                                it.message ?: "Could not resolve Spotify track",
                                null,
                            )
                        }
                }
            }
            FoxyFlutterChannels.Methods.START_RECOGNITION -> {
                val act = context as? MainActivity
                if (act == null) {
                    if (!FoxyRecognition.hasRecordPermission(context)) {
                        result.error(
                            "permission_denied",
                            "Microphone permission is required for music recognition",
                            null,
                        )
                    } else {
                        startRecognition()
                        result.success(mapOf("ok" to true))
                    }
                } else {
                    act.startRecognition(result)
                }
            }
            FoxyFlutterChannels.Methods.STOP_RECOGNITION -> {
                scope.launch {
                    FoxyRecognition.stop()
                    result.success(mapOf("ok" to true))
                }
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
                        "iconScale" to settings.iconScale,
                        "bottomNavScale" to settings.bottomNavScale,
                        "gridColumns" to settings.gridColumns,
                        "showBottomLabels" to settings.showBottomLabels,
                        "disableAnimations" to settings.disableAnimations,
                        "hapticFeedback" to settings.hapticFeedback,
                        "persistentQueue" to settings.persistentQueue,
                        "continuePlaybackWhenDismissed" to settings.continuePlaybackWhenDismissed,
                        "saveHistory" to settings.saveHistory,
                        "sponsorBlockEnabled" to settings.sponsorBlockEnabled,
                        "crossfadeMs" to settings.crossfadeMs,
                        "playerProgressStyle" to settings.playerProgressStyle,
                        "playerSeekMotion" to settings.playerSeekMotion,
                        "playerBackgroundStyle" to settings.playerBackgroundStyle,
                        "playerStyle" to settings.playerStyle,
                        "playerButtonsStyle" to settings.playerButtonsStyle,
                        "miniPlayerStyle" to settings.miniPlayerStyle,
                        "bottomNavigationStyle" to settings.bottomNavigationStyle,
                        "playerArtworkShape" to settings.playerArtworkShape,
                        "hidePlayerArtwork" to settings.hidePlayerArtwork,
                        "cropArtworkSquare" to settings.cropArtworkSquare,
                        "thumbnailCornerRadius" to settings.thumbnailCornerRadius,
                        "lyricsAnimationStyle" to settings.lyricsAnimationStyle,
                        "lyricsPreferLrclib" to settings.lyricsPreferLrclib,
                        "lyricsRomanize" to settings.lyricsRomanize,
                        "streamQualityTier" to settings.streamQualityTier,
                        "downloadQualityTier" to settings.downloadQualityTier,
                        "wifiQualityTier" to settings.wifiQualityTier,
                        "mobileQualityTier" to settings.mobileQualityTier,
                        "streamSourcePriority" to settings.streamSourcePriority,
                        "artworkPriority" to settings.artworkPriority,
                        "recognitionSource" to settings.recognitionSource,
                        "recognitionHistoryLimit" to settings.recognitionHistoryLimit,
                        "homeBackgroundEnabled" to settings.homeBackgroundEnabled,
                        "defaultOpenTab" to settings.defaultOpenTab,
                        "quickPicksDisplayMode" to settings.quickPicksDisplayMode,
                        "showLikedInLibrary" to settings.showLikedInLibrary,
                        "showDownloadsInLibrary" to settings.showDownloadsInLibrary,
                        "showHistoryInLibrary" to settings.showHistoryInLibrary,
                        "showMostPlayedInLibrary" to settings.showMostPlayedInLibrary,
                        "showPlaylistsInLibrary" to settings.showPlaylistsInLibrary,
                        "showLocalInLibrary" to settings.showLocalInLibrary,
                        "showRecognizedInLibrary" to settings.showRecognizedInLibrary,
                        "contentLanguageTag" to settings.contentLanguageTag,
                        "appLanguageTag" to settings.appLanguageTag,
                        "proxyEnabled" to settings.proxyEnabled,
                        "proxyEndpoint" to settings.proxyEndpoint,
                        "normalizeVolume" to settings.normalizeVolume,
                        "skipSilence" to settings.skipSilence,
                        "autoSkipNextOnError" to settings.autoSkipNextOnError,
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
                val iconScale = call.argument<Number>("iconScale")?.toInt()
                val bottomNavScale = call.argument<Number>("bottomNavScale")?.toInt()
                val gridColumns = call.argument<Number>("gridColumns")?.toInt()
                val showBottomLabels = call.argument<Boolean>("showBottomLabels")
                val disableAnimations = call.argument<Boolean>("disableAnimations")
                val hapticFeedback = call.argument<Boolean>("hapticFeedback")
                val persistentQueue = call.argument<Boolean>("persistentQueue")
                val saveHistory = call.argument<Boolean>("saveHistory")
                val sponsorBlockEnabled = call.argument<Boolean>("sponsorBlockEnabled")
                val crossfadeMs = call.argument<Number>("crossfadeMs")?.toInt()
                val playerProgressStyle = call.argument<Number>("playerProgressStyle")?.toInt()
                val playerBackgroundStyle = call.argument<Number>("playerBackgroundStyle")?.toInt()
                val playerStyle = call.argument<Number>("playerStyle")?.toInt()
                val playerButtonsStyle = call.argument<Number>("playerButtonsStyle")?.toInt()
                val miniPlayerStyle = call.argument<Number>("miniPlayerStyle")?.toInt()
                val bottomNavigationStyle =
                    call.argument<Number>("bottomNavigationStyle")?.toInt()
                val playerArtworkShape = call.argument<Number>("playerArtworkShape")?.toInt()
                val hidePlayerArtwork = call.argument<Boolean>("hidePlayerArtwork")
                val cropArtworkSquare = call.argument<Boolean>("cropArtworkSquare")
                val thumbnailCornerRadius = call.argument<Number>("thumbnailCornerRadius")?.toInt()
                val lyricsAnimationStyle = call.argument<Number>("lyricsAnimationStyle")?.toInt()
                val lyricsPreferLrclib = call.argument<Boolean>("lyricsPreferLrclib")
                val lyricsRomanize = call.argument<Boolean>("lyricsRomanize")
                val streamQualityTier = call.argument<Number>("streamQualityTier")?.toInt()
                val downloadQualityTier = call.argument<Number>("downloadQualityTier")?.toInt()
                val wifiQualityTier = call.argument<Number>("wifiQualityTier")?.toInt()
                val mobileQualityTier = call.argument<Number>("mobileQualityTier")?.toInt()
                val streamSourcePriority = call.argument<Number>("streamSourcePriority")?.toInt()
                val artworkPriority = call.argument<Number>("artworkPriority")?.toInt()
                val recognitionSource = call.argument<Number>("recognitionSource")?.toInt()
                val recognitionHistoryLimit = call.argument<Number>("recognitionHistoryLimit")?.toInt()
                val homeBackgroundEnabled = call.argument<Boolean>("homeBackgroundEnabled")
                val defaultOpenTab = call.argument<Number>("defaultOpenTab")?.toInt()
                val quickPicksDisplayMode = call.argument<Number>("quickPicksDisplayMode")?.toInt()
                val showLikedInLibrary = call.argument<Boolean>("showLikedInLibrary")
                val showDownloadsInLibrary = call.argument<Boolean>("showDownloadsInLibrary")
                val showHistoryInLibrary = call.argument<Boolean>("showHistoryInLibrary")
                val showMostPlayedInLibrary = call.argument<Boolean>("showMostPlayedInLibrary")
                val showPlaylistsInLibrary = call.argument<Boolean>("showPlaylistsInLibrary")
                val showLocalInLibrary = call.argument<Boolean>("showLocalInLibrary")
                val showRecognizedInLibrary = call.argument<Boolean>("showRecognizedInLibrary")
                val contentLanguageTag = call.argument<String>("contentLanguageTag")
                val appLanguageTag = call.argument<String>("appLanguageTag")
                val proxyEnabled = call.argument<Boolean>("proxyEnabled")
                val proxyEndpoint = call.argument<String>("proxyEndpoint")
                val normalizeVolume = call.argument<Boolean>("normalizeVolume")
                val skipSilence = call.argument<Boolean>("skipSilence")
                val autoSkipNextOnError = call.argument<Boolean>("autoSkipNextOnError")
                val autoBackupEnabled = call.argument<Boolean>("autoBackupEnabled")
                val autoCheckUpdates = call.argument<Boolean>("autoCheckUpdates")
                val updateNotifications = call.argument<Boolean>("updateNotifications")
                val continuePlaybackWhenDismissed =
                    call.argument<Boolean>("continuePlaybackWhenDismissed")
                val shouldEmitAppearanceChanged =
                    themePalette != null ||
                        themeMode != null ||
                        dynamicSongColors != null ||
                        accentArgb != null ||
                        blurEffects != null ||
                        compactPlayer != null ||
                        gestureControls != null ||
                        iconScale != null ||
                        bottomNavScale != null ||
                        gridColumns != null ||
                        showBottomLabels != null ||
                        disableAnimations != null ||
                        playerProgressStyle != null ||
                        playerBackgroundStyle != null ||
                        playerStyle != null ||
                        playerButtonsStyle != null ||
                        miniPlayerStyle != null ||
                        bottomNavigationStyle != null ||
                        playerArtworkShape != null ||
                        hidePlayerArtwork != null ||
                        cropArtworkSquare != null ||
                        thumbnailCornerRadius != null ||
                        lyricsAnimationStyle != null ||
                        artworkPriority != null ||
                        homeBackgroundEnabled != null ||
                        defaultOpenTab != null ||
                        quickPicksDisplayMode != null
                FoxySettings.update { current ->
                    current.copy(
                        themePalette = themePalette?.coerceIn(0, FoxyThemePresets.lastIndex) ?: current.themePalette,
                        themeMode = themeMode?.coerceIn(0, 2) ?: current.themeMode,
                        dynamicSongColors = dynamicSongColors ?: current.dynamicSongColors,
                        accentArgb = accentArgb ?: current.accentArgb,
                        blurEffects = blurEffects ?: current.blurEffects,
                        compactPlayer = compactPlayer ?: current.compactPlayer,
                        gestureControls = gestureControls ?: current.gestureControls,
                        iconScale = iconScale?.coerceIn(0, 2) ?: current.iconScale,
                        bottomNavScale = bottomNavScale?.coerceIn(0, 2) ?: current.bottomNavScale,
                        gridColumns = gridColumns?.coerceIn(2, 4) ?: current.gridColumns,
                        showBottomLabels = showBottomLabels ?: current.showBottomLabels,
                        disableAnimations = disableAnimations ?: current.disableAnimations,
                        hapticFeedback = hapticFeedback ?: current.hapticFeedback,
                        persistentQueue = persistentQueue ?: current.persistentQueue,
                        saveHistory = saveHistory ?: current.saveHistory,
                        sponsorBlockEnabled = sponsorBlockEnabled ?: current.sponsorBlockEnabled,
                        crossfadeMs = crossfadeMs?.let { v ->
                            when (v) {
                                0, 3000, 5000, 8000, 12000 -> v
                                else -> current.crossfadeMs
                            }
                        } ?: current.crossfadeMs,
                        playerProgressStyle = playerProgressStyle?.let { if (it == 1) 1 else 0 }
                            ?: current.playerProgressStyle,
                        playerSeekMotion = 0,
                        playerBackgroundStyle = playerBackgroundStyle?.coerceIn(0, 3)
                            ?: current.playerBackgroundStyle,
                        playerStyle = playerStyle?.coerceIn(0, 2)
                            ?: current.playerStyle,
                        playerButtonsStyle = playerButtonsStyle?.coerceIn(0, 2)
                            ?: current.playerButtonsStyle,
                        miniPlayerStyle = miniPlayerStyle?.coerceIn(0, 2)
                            ?: current.miniPlayerStyle,
                        bottomNavigationStyle = bottomNavigationStyle?.coerceIn(0, 2)
                            ?: current.bottomNavigationStyle,
                        playerArtworkShape = playerArtworkShape?.coerceIn(0, 2)
                            ?: current.playerArtworkShape,
                        hidePlayerArtwork = hidePlayerArtwork ?: current.hidePlayerArtwork,
                        cropArtworkSquare = cropArtworkSquare ?: current.cropArtworkSquare,
                        thumbnailCornerRadius = thumbnailCornerRadius?.coerceIn(0, 40)
                            ?: current.thumbnailCornerRadius,
                        lyricsAnimationStyle = lyricsAnimationStyle?.coerceIn(0, 5)
                            ?: current.lyricsAnimationStyle,
                        lyricsPreferLrclib = lyricsPreferLrclib ?: current.lyricsPreferLrclib,
                        lyricsRomanize = lyricsRomanize ?: current.lyricsRomanize,
                        streamQualityTier = streamQualityTier?.coerceIn(0, 4) ?: current.streamQualityTier,
                        downloadQualityTier = downloadQualityTier?.coerceIn(0, 4)
                            ?: current.downloadQualityTier,
                        wifiQualityTier = wifiQualityTier?.coerceIn(-1, 4)
                            ?: current.wifiQualityTier,
                        mobileQualityTier = mobileQualityTier?.coerceIn(-1, 4)
                            ?: current.mobileQualityTier,
                        streamSourcePriority = streamSourcePriority?.coerceIn(0, 2)
                            ?: current.streamSourcePriority,
                        artworkPriority = artworkPriority?.coerceIn(0, 3)
                            ?: current.artworkPriority,
                        recognitionSource = recognitionSource?.coerceIn(0, 1)
                            ?: current.recognitionSource,
                        recognitionHistoryLimit = recognitionHistoryLimit?.coerceIn(10, 100)
                            ?: current.recognitionHistoryLimit,
                        homeBackgroundEnabled = homeBackgroundEnabled
                            ?: current.homeBackgroundEnabled,
                        defaultOpenTab = defaultOpenTab?.let { if (it == 1 || it == 3) it else 0 }
                            ?: current.defaultOpenTab,
                        quickPicksDisplayMode = quickPicksDisplayMode?.coerceIn(0, 1)
                            ?: current.quickPicksDisplayMode,
                        showLikedInLibrary = showLikedInLibrary ?: current.showLikedInLibrary,
                        showDownloadsInLibrary = showDownloadsInLibrary
                            ?: current.showDownloadsInLibrary,
                        showHistoryInLibrary = showHistoryInLibrary
                            ?: current.showHistoryInLibrary,
                        showMostPlayedInLibrary = showMostPlayedInLibrary
                            ?: current.showMostPlayedInLibrary,
                        showPlaylistsInLibrary = showPlaylistsInLibrary
                            ?: current.showPlaylistsInLibrary,
                        showLocalInLibrary = showLocalInLibrary ?: current.showLocalInLibrary,
                        showRecognizedInLibrary = showRecognizedInLibrary
                            ?: current.showRecognizedInLibrary,
                        contentLanguageTag = contentLanguageTag?.trim()?.takeIf { it.isNotEmpty() }
                            ?: current.contentLanguageTag,
                        appLanguageTag = appLanguageTag?.let { it.trim() } ?: current.appLanguageTag,
                        proxyEnabled = proxyEnabled ?: current.proxyEnabled,
                        proxyEndpoint = proxyEndpoint?.trim() ?: current.proxyEndpoint,
                        normalizeVolume = normalizeVolume ?: current.normalizeVolume,
                        skipSilence = skipSilence ?: current.skipSilence,
                        autoSkipNextOnError = autoSkipNextOnError
                            ?: current.autoSkipNextOnError,
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
                if (shouldEmitAppearanceChanged) {
                    emit(mapOf("type" to FoxyFlutterChannels.Events.APPEARANCE_CHANGED))
                }
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.ACCOUNT_INFO -> {
                val account = FoxyAccount.state.value
                val library = FoxyLibraryStore.state.value
                val localPlaylistCount = FoxyUserPlaylists.all().size
                result.success(
                    mapOf(
                        "isSignedIn" to account.isSignedIn,
                        "displayName" to account.displayName,
                        "name" to account.name,
                        "email" to account.email,
                        "avatarUrl" to account.avatarUrl,
                        "likedCount" to library.likedSongs.size,
                        "playlistCount" to localPlaylistCount,
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
                            FoxyLibraryStore.maybeRefreshDownloadsFromDisk(context.applicationContext)
                        }
                    }
                    val library = FoxyLibraryStore.state.value
                    val recognitionHistory = FoxyRecognitionHistory.all()
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
                    val playlistSongs = FoxyUserPlaylists.all()
                        .flatMap { it.songs }
                        .distinctBy { it.videoId }
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
                            "local" to library.localSongs.map { it.toFlutterMap() },
                            "liked" to library.likedSongs.map { it.toFlutterMap() },
                            "history" to library.historySongs.map { it.toFlutterMap() },
                            "saved" to library.savedSongs.map { it.toFlutterMap() },
                            "playlists" to playlistSongs.map { it.toFlutterMap() },
                            "mostPlayed" to library.mostPlayedFromHistory().map { it.toFlutterMap() },
                            "recentlyAdded" to library.recentlyMerged().map { it.toFlutterMap() },
                            "explore" to explore.map { it.toFlutterMap() },
                            "recognitionHistory" to recognitionHistory.map { it.toMap() },
                            "recognitionCount" to recognitionHistory.size,
                            "playlistCount" to (localPlaylistMaps.size + ytPlaylistMaps.size),
                            "userPlaylists" to localPlaylistMaps + ytPlaylistMaps,
                        ),
                    )
                }
            }
            FoxyFlutterChannels.Methods.IMPORT_LOCAL_AUDIO -> {
                val act = context as? MainActivity
                if (act == null) {
                    result.error("no_activity", "Cannot open audio picker", null)
                } else {
                    act.importLocalAudio(result)
                }
            }
            FoxyFlutterChannels.Methods.IMPORT_LOCAL_FOLDER -> {
                val act = context as? MainActivity
                if (act == null) {
                    result.error("no_activity", "Cannot open folder picker", null)
                } else {
                    act.importLocalFolder(result)
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
            FoxyFlutterChannels.Methods.SEARCH_HISTORY -> {
                result.success(searchHistoryPrefs().allQueries())
            }
            FoxyFlutterChannels.Methods.ADD_SEARCH_HISTORY -> {
                val query = call.argument<String>("query").orEmpty()
                result.success(searchHistoryPrefs().addQuery(query))
            }
            FoxyFlutterChannels.Methods.REMOVE_SEARCH_HISTORY -> {
                val query = call.argument<String>("query").orEmpty()
                result.success(searchHistoryPrefs().removeQuery(query))
            }
            FoxyFlutterChannels.Methods.CLEAR_SEARCH_HISTORY -> {
                searchHistoryPrefs().clear()
                result.success(emptyList<String>())
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
                                val categorized = YTMusicApi.searchAll(query, limit)
                                val artistRows = YTMusicApi.searchArtistProfiles(query, limit)
                                    .map { artist ->
                                        Song(
                                            videoId = artist.browseId.ifBlank { artist.name },
                                            title = artist.name,
                                            artist = artist.subscribers ?: "Artist",
                                            thumbnail = artist.thumbnail,
                                            artworkUrl = artist.thumbnail,
                                        )
                                    }
                                    .filter { it.videoId.isNotBlank() && it.title.isNotBlank() }
                                    .distinctBy { it.videoId }
                                    .take(limit)
                                mapOf(
                                    "songs" to categorized["songs"].orEmpty()
                                        .filter { it.videoId.isNotBlank() }
                                        .map { it.toFlutterMap() },
                                    "videos" to categorized["videos"].orEmpty()
                                        .filter { it.videoId.isNotBlank() }
                                        .map { it.toFlutterMap() },
                                    "albums" to categorized["albums"].orEmpty()
                                        .filter { it.videoId.isNotBlank() }
                                        .map { it.toFlutterMap() },
                                    "artists" to artistRows.map { it.toFlutterMap() },
                                )
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure {
                                result.error("search_failed", it.message ?: "Search failed", null)
                        }
                    }
                }
            }
            FoxyFlutterChannels.Methods.RESOLVE_ARTIST_PROFILE -> {
                val artist = call.argument<String>("artist").orEmpty().trim()
                val limit = (call.argument<Number>("limit")?.toInt() ?: 28).coerceIn(8, 40)
                if (artist.isBlank()) {
                    result.error("bad_args", "Missing artist", null)
                } else {
                    scope.launch {
                        val payload = runCatching {
                            withContext(Dispatchers.IO) {
                                resolveArtistProfilePayload(artist, limit)
                            }
                        }
                        payload.onSuccess(result::success)
                            .onFailure {
                                result.error(
                                    "artist_profile_failed",
                                    it.message ?: "Could not resolve artist",
                                    null,
                                )
                            }
                    }
                }
            }
            FoxyFlutterChannels.Methods.HOME_FEED -> {
                val params = call.argument<String>("params")?.trim()?.takeIf { it.isNotBlank() }
                val mood = call.argument<String>("mood")?.trim()?.takeIf { it.isNotBlank() }
                scope.launch {
                    val payload = runCatching {
                        withContext(Dispatchers.IO) {
                            if (!hasHomeFeedInternet(context)) {
                                throw UnknownHostException("No internet connection")
                            }
                            val byTitle = LinkedHashMap<String, RecommendationSection>()
                            val seenVideoIds = LinkedHashSet<String>()
                            fun isSuppressedHomeSection(title: String): Boolean {
                                val t = title.lowercase(Locale.US)
                                return t.contains("foxy mix") || t.contains("radio starter")
                            }
                            fun addAll(list: List<RecommendationSection>) {
                                for (s in list) {
                                    if (isSuppressedHomeSection(s.title)) continue
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
                            suspend fun searchSection(title: String, query: String, limit: Int = 18) =
                                RecommendationSection(
                                    title,
                                    withTimeoutOrNull(2_400) {
                                        YTMusicApi.search(query)
                                    }.orEmpty().take(limit),
                                )
                            suspend fun categorySections(seed: String): List<RecommendationSection> {
                                val normalized = seed.lowercase(Locale.US)
                                val pairs = when (normalized) {
                                    "moods" -> listOf(
                                        "Relax" to "relaxing songs chill mix",
                                        "Sleep" to "sleep music soft songs",
                                        "Focus" to "focus music deep work songs",
                                        "Workout" to "workout energetic songs",
                                        "Party" to "party hits dance songs",
                                        "Romance" to "romantic songs love hits",
                                    )
                                    "genres" -> listOf(
                                        "Bollywood" to "bollywood hits songs",
                                        "Punjabi" to "punjabi hits songs",
                                        "Indie" to "indie pop songs",
                                        "Pop" to "pop hits songs",
                                        "Hip-Hop" to "hip hop rap hits",
                                        "Electronic" to "electronic dance music songs",
                                        "Rock" to "rock hits songs",
                                    )
                                    "charts" -> listOf(
                                        "India top songs" to "india top songs today",
                                        "Global top songs" to "global top songs today",
                                        "Viral hits" to "viral songs trending now",
                                        "YouTube charts" to "youtube music charts songs",
                                        "New releases" to "new release songs this week",
                                    )
                                    "radio" -> listOf(
                                        "Foxy Radio" to "top songs radio mix",
                                        "Bollywood Radio" to "bollywood radio hits",
                                        "Punjabi Radio" to "punjabi radio hits",
                                        "Chill Radio" to "chill radio songs",
                                        "Throwback Radio" to "throwback radio hits",
                                    )
                                    "categories" -> listOf(
                                        "Phonk" to "phonk songs",
                                        "Classic hits" to "classic hits songs",
                                        "Old is gold" to "old hindi songs classics",
                                        "Acoustic" to "acoustic songs unplugged",
                                        "Lo-fi" to "lofi songs chill",
                                        "Devotional" to "devotional songs bhajan",
                                        "Romantic hits" to "romantic hits songs",
                                    )
                                    else -> listOf(
                                        seed.replaceFirstChar { it.titlecase(Locale.US) } to "$seed songs mix",
                                        "More ${seed.lowercase(Locale.US)}" to "$seed playlist songs",
                                    )
                                }
                                return pairs.map { (title, query) -> searchSection(title, query) }
                            }
                            suspend fun featuredArtistSongs(): List<Song> {
                                val names = listOf(
                                    "Ed Sheeran",
                                    "The Weeknd",
                                    "Taylor Swift",
                                    "Arijit Singh",
                                    "Anuv Jain",
                                    "Dua Lipa",
                                    "Bruno Mars",
                                    "Billie Eilish",
                                    "Diljit Dosanjh",
                                    "Ariana Grande",
                                )
                                return names.map { name ->
                                    async {
                                        withTimeoutOrNull(1_800) {
                                            YTMusicApi.searchArtistProfiles(name, 1).firstOrNull()
                                        }?.let { artist ->
                                            Song(
                                                videoId = artist.browseId.ifBlank { artist.name },
                                                title = artist.name,
                                                artist = artist.subscribers ?: "Artist",
                                                thumbnail = artist.thumbnail,
                                                artworkUrl = artist.thumbnail,
                                            )
                                        }
                                    }
                                }.awaitAll()
                                    .filterNotNull()
                                    .filter { it.videoId.isNotBlank() && it.title.isNotBlank() }
                                    .distinctBy { it.videoId }
                            }
                            val library = FoxyLibraryStore.state.value
                            if (mood != null) {
                                val moodKey = mood.lowercase(Locale.US)
                                when (moodKey) {
                                    "downloaded" -> {
                                        val downloaded = library.downloadedSongs.asReversed().take(24)
                                        addAll(
                                            listOf(
                                                RecommendationSection("Downloaded", downloaded),
                                                RecommendationSection(
                                                    "Offline replay",
                                                    downloaded.shuffled().take(18),
                                                ),
                                            ),
                                        )
                                    }
                                    "history" -> {
                                        val history = library.historySongs.take(24)
                                        addAll(
                                            listOf(
                                                RecommendationSection("History", history),
                                                RecommendationSection(
                                                    "Recently played",
                                                    history.drop(6).take(18),
                                                ),
                                            ),
                                        )
                                    }
                                    "moods", "genres", "charts", "radio" -> {
                                        addAll(categorySections(moodKey))
                                    }
                                    else -> {
                                        addAll(
                                            listOf(
                                                RecommendationSection(
                                                    "${mood.replaceFirstChar { it.titlecase(Locale.US) }} radio",
                                                    YTMusicApi.getMoodMix(mood).take(24),
                                                ),
                                                RecommendationSection(
                                                    "More ${mood.lowercase(Locale.US)}",
                                                    YTMusicApi.search("$mood songs mix").take(18),
                                                ),
                                            ),
                                        )
                                    }
                                }
                            }
                            if (params == null && mood == null) {
                                val historyIds = library.historySongs.map { it.videoId }.toHashSet()
                                val resume = library.historySongs.take(18)
                                val offline = library.downloadedSongs
                                    .asReversed()
                                    .filterNot { historyIds.contains(it.videoId) }
                                    .ifEmpty { library.downloadedSongs.asReversed() }
                                    .take(18)
                                if (resume.isNotEmpty()) {
                                    addAll(listOf(RecommendationSection("Listen again", resume)))
                                }
                                if (offline.isNotEmpty()) {
                                    addAll(listOf(RecommendationSection("Downloaded but forgotten", offline)))
                                }
                            }
                            val recentSeed = if (params == null && mood == null) {
                                library.historySongs.firstOrNull()
                            } else {
                                null
                            }
                            val foxyDiscoveryJobs = if (params == null && mood == null) {
                                listOf(
                                    async {
                                        recentSeed?.let { seed ->
                                            listOf(
                                                RecommendationSection(
                                                    "Because you played ${seed.title}",
                                                    withTimeoutOrNull(2_500) {
                                                        YTMusicApi.radio(seed)
                                                    }.orEmpty().drop(1).take(16),
                                                ),
                                            )
                                        } ?: emptyList()
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Trending now",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("trending songs today")
                                                }.orEmpty().take(16),
                                            ),
                                        )
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Featured artists",
                                                featuredArtistSongs(),
                                            ),
                                        )
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Bollywood radar",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("bollywood trending songs")
                                                }.orEmpty().take(16),
                                            ),
                                        )
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Punjabi heat",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("punjabi trending songs")
                                                }.orEmpty().take(16),
                                            ),
                                        )
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Indie discovery",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("indie pop discovery songs")
                                                }.orEmpty().take(16),
                                            ),
                                        )
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Focus flow",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("focus chill electronic songs")
                                                }.orEmpty().take(16),
                                            ),
                                        )
                                    },
                                    async {
                                        listOf(
                                            RecommendationSection(
                                                "Throwback radio",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("throwback hits songs")
                                                }.orEmpty().take(16),
                                            ),
                                        )
                                    },
                                )
                            } else {
                                emptyList()
                            }
                            val discoveryJobs = listOf(
                                async {
                                    runCatching {
                                        withTimeoutOrNull(3_200) {
                                            YTMusicApi.homeRecommendations(params)
                                        }.orEmpty()
                                    }
                                        .getOrElse { emptyList() }
                                },
                                async {
                                    if (params == null && mood == null) {
                                        listOf(
                                            RecommendationSection(
                                                "New releases",
                                                withTimeoutOrNull(2_200) {
                                                    YTMusicApi.search("new release songs this week")
                                                }.orEmpty().take(18),
                                            ),
                                        )
                                    } else {
                                        emptyList()
                                    }
                                },
                                async {
                                    if (params == null && mood == null) {
                                        val chartEarly =
                                            runCatching { YTMusicApi.chartsSections() }
                                                .getOrElse { emptyList() }
                                                .firstOrNull {
                                                    it.title.contains("chart", ignoreCase = true)
                                                }
                                                ?: RecommendationSection(
                                                    "Charts",
                                                    withTimeoutOrNull(2_200) {
                                                        YTMusicApi.search("billboard hot 100 songs")
                                                    }.orEmpty().take(14),
                                                )
                                        listOf(chartEarly)
                                    } else {
                                        emptyList()
                                    }
                                },
                            ) + foxyDiscoveryJobs
                            discoveryJobs.awaitAll().forEach(::addAll)
                            if (byTitle.isEmpty()) {
                                addAll(
                                    listOf(
                                        RecommendationSection(
                                            "Quick picks",
                                            YTMusicApi.search("top songs today").take(16),
                                        ),
                                    ).filter { it.songs.isNotEmpty() },
                                )
                            }
                            fun layoutFor(title: String): String {
                                val t = title.lowercase(Locale.US)
                                return when {
                                    t.contains("quick pick") -> "cards"
                                    t.contains("foxy mix") -> "mixes"
                                    t.contains("radio") || t.contains("starter") -> "square"
                                    t.contains("video") -> "video"
                                    t.contains("listen again") || t.contains("resume") || t.contains("replayed") ||
                                        t.contains("downloaded") -> "square"
                                    t.contains("release") || t.contains("discover") ||
                                        t.contains("daily") || t.contains("fresh") -> "square"
                                    t.contains("charting") || t.contains("trending") -> "chart"
                                    t.contains("artist") || t.contains("similar") -> "artist"
                                    t.contains("categories") -> "cards"
                                    t.contains("phonk") || t.contains("classic") || t.contains("old is gold") ||
                                        t.contains("acoustic") || t.contains("lo-fi") || t.contains("devotional") ||
                                        t.contains("romantic hits") -> "square"
                                    else -> "square"
                                }
                            }
                            val sections = byTitle.values.take(24).map { sec ->
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
                        .onFailure {
                            result.error(
                                "home_failed",
                                homeFeedErrorMessage(it),
                                null,
                            )
                        }
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

                    scope.launch {
                        delay(80)
                        emitLivePlayerStateEvent()
                        delay(200)
                        emitLivePlayerStateEvent(includeQueue = false)
                    }
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
                scheduleFlutterPlayerStatePush(includeQueue = true)
            }
            FoxyFlutterChannels.Methods.PREVIOUS -> {
                FoxyPlayerConnection.playPrevious()
                result.success(null)
                scheduleFlutterPlayerStatePush(includeQueue = true)
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
                    result.success(null)

                    // Aggressive updates for cold start
                    scope.launch {
                        delay(40)
                        emitLivePlayerStateEvent(includeQueue = true)
                        delay(120)
                        emitLivePlayerStateEvent(includeQueue = true)
                        delay(250)
                        emitLivePlayerStateEvent(includeQueue = true)
                        delay(500)
                        emitLivePlayerStateEvent(includeQueue = true)
                    }
                    scheduleFlutterPlayerStatePush(includeQueue = true)
                }
            }

            FoxyFlutterChannels.Methods.SKIP_TO_QUEUE_INDEX -> {
                val index = (call.argument<Number>("index")?.toInt() ?: 0).coerceAtLeast(0)
                FoxyPlayerConnection.skipToQueueIndex(context, index)
                result.success(null)
                scheduleFlutterPlayerStatePush(includeQueue = true)
            }
            FoxyFlutterChannels.Methods.REMOVE_FROM_QUEUE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.removeFromQueue(it) }
                result.success(null)
                scheduleFlutterPlayerStatePush(includeQueue = true)
            }
            FoxyFlutterChannels.Methods.MOVE_QUEUE_ITEM -> {
                val from = (call.argument<Number>("fromIndex")?.toInt() ?: -1)
                val to = (call.argument<Number>("toIndex")?.toInt() ?: -1)
                FoxyPlayerConnection.moveQueueItem(from, to)
                result.success(null)
                scheduleFlutterPlayerStatePush(includeQueue = true)
            }
            FoxyFlutterChannels.Methods.ENQUEUE_PLAY_NEXT -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.enqueuePlayNext(it) }
                result.success(null)
                scheduleFlutterPlayerStatePush(includeQueue = true)
            }
            FoxyFlutterChannels.Methods.ADD_TO_QUEUE -> {
                call.argument<Map<String, Any?>>("song")?.toSongOrNull()?.let { FoxyPlayerConnection.addToQueue(it) }
                result.success(null)
                scheduleFlutterPlayerStatePush(includeQueue = true)
            }
            FoxyFlutterChannels.Methods.SEEK_TO -> {
                val pos = (call.argument<Number>("positionMs")?.toLong() ?: 0L).coerceAtLeast(0L)
                FoxyPlayerConnection.seekTo(pos)
                result.success(null)
                scheduleFlutterPlayerStatePush()
            }
            FoxyFlutterChannels.Methods.SET_VOLUME -> {
                val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                FoxyPlayerConnection.setVolume(volume)
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
                    emitLibraryFeedChanged()
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
                    emitLibraryFeedChanged()
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
            "clearLyricsCache" -> {
                val cleared = LyricsRepository.clearMemoryCache()
                result.success(mapOf("ok" to true, "clearedEntries" to cleared))
            }
            "refreshDownloads" -> {
                scope.launch {
                    runCatching {
                        FoxyLibraryStore.refreshDownloadsFromDisk(context.applicationContext)
                    }.onSuccess {
                        result.success(mapOf("ok" to true))
                        emit(mapOf("type" to FoxyFlutterChannels.Events.LIBRARY_DOWNLOADS_CHANGED))
                        emitLibraryFeedChanged()
                    }.onFailure {
                        result.error("refresh_failed", it.message ?: "Refresh failed", null)
                    }
                }
            }
            "repairLibraryMetadata" -> {
                scope.launch {
                    runCatching {
                        FoxyLibraryStore.refreshDownloadsFromDisk(context.applicationContext)
                    }.onSuccess {
                        result.success(mapOf("ok" to true))
                        emit(mapOf("type" to FoxyFlutterChannels.Events.LIBRARY_DOWNLOADS_CHANGED))
                        emitLibraryFeedChanged()
                    }.onFailure {
                        result.error("repair_failed", it.message ?: "Repair failed", null)
                    }
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
            FoxyFlutterChannels.Methods.GET_VIDEO_CLIP_STREAM -> {
                val videoId = call.argument<String>("videoId").orEmpty().trim()
                val title = call.argument<String>("title").orEmpty().trim()
                val artist = call.argument<String>("artist").orEmpty().trim()
                if (videoId.isBlank()) {
                    result.error("bad_args", "Missing videoId", null)
                } else {
                    scope.launch {
                        val clip = withContext(Dispatchers.IO) {
                            StreamExtractor.getVideoClipResult(
                                videoId = videoId,
                                title = title,
                                artist = artist,
                            )
                        }
                        result.success(
                            mapOf(
                                "url" to clip.url,
                                "source" to clip.source,
                                "bitrate" to clip.bitrate,
                                "codec" to clip.codec,
                                "mimeType" to clip.mimeType,
                                "itag" to clip.itag,
                                "qualityLabel" to clip.qualityLabel,
                                "error" to clip.error,
                            ),
                        )
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        sinks.add(events)

        // Immediate strong update
        emitLivePlayerStateEvent(includeQueue = true)
        scheduleFlutterPlayerStatePush(includeQueue = true)
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
                FoxyPlayerConnection.state.collect { ui ->
                    val nativePlaying = MusicPlayer.isPlaying()
                    val effectivePlaying = ui.isPlaying || nativePlaying
                    val livePosition = MusicPlayer.currentPosition()
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
                        append(effectivePlaying)
                        append('|')
                        append(ui.isBuffering && !effectivePlaying)
                        append('|')
                        append(ui.error.orEmpty())
                        append('|')
                        append(livePosition / 500L)
                    }
                    if (fullKey != lastFullEmitKey) {
                        lastFullEmitKey = fullKey
                        lastLightEmitAtMs = 0L
                        emitLivePlayerStateEvent(ui, includeQueue = true)
                        return@collect
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastLightEmitAtMs < 180L) return@collect
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
                var lastFeedSignature = ""
                FoxyLibraryStore.notifyEpoch
                    .debounce(120)
                    .collect { _ ->
                        val state = FoxyLibraryStore.state.value
                        val nextSignature = buildString {
                            append(state.likedSongs.joinToString("|") { it.videoId })
                            append("::")
                            append(state.historySongs.joinToString("|") { it.videoId })
                            append("::")
                            append(
                                state.playCounts.entries
                                    .sortedBy { it.key }
                                    .joinToString("|") { "${it.key}:${it.value}" },
                            )
                            append("::")
                            append(state.localSongs.joinToString("|") { it.videoId })
                            append("::")
                            append(state.downloadedSongs.joinToString("|") { it.videoId })
                        }
                        if (nextSignature != lastFeedSignature) {
                            lastFeedSignature = nextSignature
                            emitLibraryFeedChanged()
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
            launch {
                FoxyRecognition.state.collect { status ->
                    emit(
                        mapOf(
                            "type" to FoxyFlutterChannels.Events.RECOGNITION_STATE,
                            "state" to status.toMap(),
                        ),
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

    fun startRecognition() {
        FoxyRecognition.start(context.applicationContext)
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

private fun hasHomeFeedInternet(context: Context): Boolean {
    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        ?: return true
    val network = cm.activeNetwork ?: return false
    val caps = cm.getNetworkCapabilities(network) ?: return false
    if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
}

private fun homeFeedErrorMessage(error: Throwable): String {
    val networkFailure =
        error is UnknownHostException ||
            error is SocketTimeoutException ||
            error is IOException ||
            error.cause is UnknownHostException ||
            error.cause is SocketTimeoutException ||
            error.cause is IOException
    return if (networkFailure) {
        "No internet connection"
    } else {
        error.message ?: "Home feed failed"
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
 * Respects [FoxySettings.lyricsPreferLrclib] (Foxy-style source order).
 * Does not return stale offline cache ahead of a live LRCLIB/YouTube fetch.
 */
private suspend fun fetchLyricsForUi(context: Context, song: Song): List<Map<String, Any>> {
    val romanize = FoxySettings.state.value.lyricsRomanize
    fun safeLyricText(raw: String): String {
        val original = raw.trim()
        if (original.isBlank()) return ""
        if (!romanize) return original
        return runCatching { LyricsRomanizer.romanizeLine(original, true).trim() }
            .getOrDefault(original)
            .ifBlank { original }
    }
    fun mapLines(lines: List<LyricLine>) = lines.mapNotNull {
        val text = safeLyricText(it.text)
        if (text.isBlank()) null else mapOf(
            "timeMs" to it.timeMs,
            "text" to text,
        )
    }
    val live = LyricsRepository.fetchSyncedLines(song)
    if (live.isNotEmpty()) return mapLines(live)
    if (song.isDownloaded) {
        val cached = FoxyOfflineBundle.readCachedLyrics(context, song.videoId) ?: return emptyList()
        return cached.mapNotNull { line ->
            val text = safeLyricText(line["text"]?.toString().orEmpty())
            if (text.isBlank()) null else mapOf<String, Any>(
                "timeMs" to ((line["timeMs"] as? Number)?.toLong() ?: 0L),
                "text" to text,
            )
        }
    }
    return emptyList()
}

private fun FoxyLibraryState.mostPlayedFromHistory(): List<Song> =
    playCounts.entries
        .filter { it.value > 1 }
        .sortedWith(
            compareByDescending<Map.Entry<String, Int>> { it.value }
                .thenByDescending { entry ->
                    historySongs.indexOfFirst { it.videoId == entry.key }
                        .let { if (it < 0) -1 else historySongs.size - it }
                },
        )
        .mapNotNull { (vid, _) ->
            historySongs.findLast { it.videoId == vid }
                ?: likedSongs.findLast { it.videoId == vid }
                ?: downloadedSongs.findLast { it.videoId == vid }
                ?: localSongs.findLast { it.videoId == vid }
                ?: allSongs.findLast { it.videoId == vid }
        }

private fun FoxyLibraryState.recentlyMerged(): List<Song> {
    val out = ArrayList<Song>()
    val seen = HashSet<String>()
    for (s in likedSongs.asReversed()) {
        if (seen.add(s.videoId)) out.add(s)
    }
    for (s in downloadedSongs.asReversed()) {
        if (seen.add(s.videoId)) out.add(s)
    }
    for (s in localSongs.asReversed()) {
        if (seen.add(s.videoId)) out.add(s)
    }
    for (s in historySongs) {
        if (seen.add(s.videoId)) out.add(s)
    }
    return out
}

private class FoxySearchHistoryPrefs(private val context: Context) {
    private val prefs by lazy {
        context.getSharedPreferences("foxy_search_history", Context.MODE_PRIVATE)
    }

    fun allQueries(): List<String> =
        runCatching {
            val raw = prefs.getString(KEY_QUERIES, "[]").orEmpty()
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val q = arr.optString(i).trim()
                    if (q.length >= 2) add(q)
                }
            }.distinctBy { it.lowercase(Locale.US) }.take(LIMIT)
        }.getOrDefault(emptyList())

    fun addQuery(raw: String): List<String> {
        val query = raw.trim()
        if (query.length < 2) return allQueries()
        val next = (listOf(query) + allQueries())
            .distinctBy { it.lowercase(Locale.US) }
            .take(LIMIT)
        save(next)
        return next
    }

    fun removeQuery(raw: String): List<String> {
        val target = raw.trim().lowercase(Locale.US)
        val next = allQueries().filterNot { it.lowercase(Locale.US) == target }
        save(next)
        return next
    }

    fun clear() {
        prefs.edit().remove(KEY_QUERIES).apply()
    }

    private fun save(queries: List<String>) {
        val arr = JSONArray()
        queries.take(LIMIT).forEach(arr::put)
        prefs.edit().putString(KEY_QUERIES, arr.toString()).apply()
    }

    private companion object {
        const val KEY_QUERIES = "queries"
        const val LIMIT = 10
    }
}

private fun recognitionMatchScore(
    song: Song,
    title: String,
    artist: String,
    youtubeVideoId: String,
): Int {
    var score = 0
    if (youtubeVideoId.isNotBlank() && song.videoId == youtubeVideoId) score += 1000
    val songTitle = song.title.trim().lowercase(Locale.US)
    val targetTitle = title.trim().lowercase(Locale.US)
    val songArtist = song.artist.trim().lowercase(Locale.US)
    val targetArtist = artist.trim().lowercase(Locale.US)
    if (targetTitle.isNotBlank() && songTitle == targetTitle) score += 400
    else if (targetTitle.isNotBlank() && songTitle.contains(targetTitle)) score += 180
    if (targetArtist.isNotBlank() && songArtist == targetArtist) score += 260
    else if (targetArtist.isNotBlank() && songArtist.contains(targetArtist)) score += 120
    val combined = "$songTitle $songArtist"
    if (combined.contains("live")) score -= 40
    if (combined.contains("cover")) score -= 55
    if (combined.contains("karaoke")) score -= 80
    if (combined.contains("slowed")) score -= 45
    if (combined.contains("remix")) score -= 25
    return score
}

private suspend fun resolveArtistProfilePayload(
    artist: String,
    limit: Int,
): Map<String, Any?> {
    val cleanArtist = primaryArtistName(artist)
    val search = YTMusicApi.searchAll(cleanArtist, limit)
    val bestProfile = YTMusicApi.searchArtistProfiles(cleanArtist, limit)
        .map { it to artistProfileScore(it, cleanArtist) }
        .maxByOrNull { it.second }
        ?.takeIf { it.second >= 118 }
        ?.first

    fun rankSongs(items: List<Song>): List<Song> =
        items
            .filter { it.videoId.isNotBlank() }
            .filter { artistSongScore(it, cleanArtist) > 0 }
            .distinctBy { it.videoId }
            .sortedByDescending { artistSongScore(it, cleanArtist) }

    val songs = rankSongs(search["songs"].orEmpty()).ifEmpty {
        rankSongs(YTMusicApi.search("$cleanArtist songs").take(limit))
    }.take(limit)
    val albums = search["albums"].orEmpty()
        .filter { it.videoId.isNotBlank() }
        .distinctBy { it.videoId }
        .sortedByDescending { artistSongScore(it, cleanArtist) }
        .take(12)

    val artwork = bestProfile?.thumbnail?.trim().orEmpty()

    return mapOf(
        "artist" to (bestProfile?.name?.takeIf { it.isNotBlank() } ?: cleanArtist),
        "artworkUrl" to artwork,
        "sourceLabel" to "YouTube Music discovery · SoundCloud playback fallback",
        "songs" to songs.map { it.toFlutterMap() },
        "albums" to albums.map { it.toFlutterMap() },
    )
}

private fun artistProfileScore(profile: ArtistProfileResult, artist: String): Int {
    val target = normalizeBridgeArtist(artist)
    val title = normalizeBridgeArtist(profile.name)
    val subtitle = normalizeBridgeArtist(profile.subscribers.orEmpty())
    var score = 0
    if (title == target) score += 120
    if (
        title.isNotBlank() &&
            target.isNotBlank() &&
            title != target &&
            (title.contains(" $target ") || target.contains(" $title "))
    ) {
        score += 28
    }
    if (profile.browseId.startsWith("UC")) score += 10
    if (subtitle.contains("subscriber")) score += 8
    val blob = "$title $subtitle"
    if (
        blob.contains("cover") ||
            blob.contains("karaoke") ||
            blob.contains("lyrics") ||
            blob.contains("fan") ||
            blob.contains("tribute")
    ) {
        score -= 65
    }
    return score
}

private fun artistSongScore(song: Song, artist: String): Int {
    val target = normalizeBridgeArtist(artist)
    val candidateArtist = normalizeBridgeArtist(song.artist)
    val title = normalizeBridgeArtist(song.title)
    var score = 0
    if (candidateArtist == target) score += 80
    if (candidateArtist.contains(target) || target.contains(candidateArtist)) score += 42
    if (title.contains(target)) score += 12
    val blob = "$title $candidateArtist"
    if (blob.contains("official audio")) score += 10
    if (blob.contains("lyrics") || blob.contains("visualizer")) score -= 8
    if (blob.contains("cover") || blob.contains("karaoke") || blob.contains("tutorial")) score -= 55
    return score
}

private fun normalizeBridgeArtist(value: String): String =
    value
        .lowercase(Locale.US)
        .replace(Regex("\\b(official|topic|vevo|artist|channel)\\b"), " ")
        .replace(Regex("\\([^)]*\\)|\\[[^]]*]"), " ")
        .replace(Regex("\\s+(feat|ft|featuring|with|x)\\s+.*$"), " ")
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()

private fun primaryArtistName(value: String): String =
    value
        .trim()
        .replace(Regex("\\([^)]*\\)|\\[[^]]*]"), " ")
        .split(
            Regex(
                "\\s*(?:,|&|/|\\+|\\bx\\b|\\bfeat\\.?\\b|\\bft\\.?\\b|\\bfeaturing\\b|\\bwith\\b)\\s*",
                RegexOption.IGNORE_CASE,
            ),
        )
        .firstOrNull { it.isNotBlank() }
        ?.trim()
        .orEmpty()
        .ifBlank { value.trim() }
