package com.foxymusic

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.TaskStackBuilder
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.core.content.getSystemService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.min


enum class SleepTimerMode { Off, AfterMinutes, AfterCurrentTrack }

/** Shown in the player UI; mirrors scheduled sleep timer / end-of-track stop. */
data class SleepTimerUiState(
    val mode: SleepTimerMode = SleepTimerMode.Off,
    /** Wall-clock time when a timed sleep fires; only for [SleepTimerMode.AfterMinutes]. */
    val fireAtEpochMs: Long = 0L
)

data class PlayerUiState(
    val currentSong: Song? = null,
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val durationMs: Long = 0L,
    /** Driven by ExoPlayer position updates for consistent mini + full player UI. */
    val positionMs: Long = 0L,
    val bufferedFraction: Float = 0f,
    val error: String? = null,
    val queue: List<Song> = emptyList(),
    val queueIndex: Int = -1,
    val shuffleEnabled: Boolean = false,
    val repeatMode: RepeatMode = RepeatMode.Off,
    val volume: Float = 1f,
    val streamBitrate: Int? = null,
    val streamCodec: String? = null,
    val streamMimeType: String? = null,
    val streamSampleRate: Int? = null,
    val streamItag: Int? = null,
    val streamSource: String? = null,
    val streamQualityLabel: String? = null,
)

enum class RepeatMode { Off, All, One }

object MusicPlayer {

    private var player: Player? = null
    private var appContext: Context? = null
    private var queue: List<Song> = emptyList()
    private var queueIndex: Int = -1
    private var shuffleEnabled = false
    private var repeatMode = RepeatMode.Off
    /** Ensures we don't loop forever if a resolved stream URL turns out invalid. */
    private var retryAttemptsForCurrent = 0
    @Volatile
    private var activePlayRequestId = 0L
    private var sleepJob: Job? = null
    private var progressJob: Job? = null
    private var stopAfterCurrentSong = false
    /** User-requested output level; combined with crossfade ramps. */
    private var userVolume = 1f
    private var sponsorRangesMs: List<Pair<Long, Long>> = emptyList()
    /** Blocks overlapping track loads (next/prev/end-of-track races). */
    private val playbackMutex = Mutex()
    /**
     * While true, [Player.STATE_ENDED] must not auto-advance — we call stop/replace during
     * [playResolved] and that used to re-enter [playNext] and crash.
     */
    @Volatile
    private var suppressEndAdvance = false
    /** Paired with [suppressEndAdvance] so a delayed clear cannot unblock the wrong track swap. */
    @Volatile
    private var suppressEndAdvanceGeneration = 0
    /** Avoid repeated [startForegroundService] on every skip — causes FGS timeout crashes. */
    @Volatile
    private var mediaSessionServiceStarted = false
    /** Pre-resolved stream URL for the upcoming queue item (videoId to url). */
    @Volatile
    private var preloadedStream: Pair<String, String>? = null
    private var preloadJob: Job? = null
    private var preloadedForQueueIndex: Int = -1
    private var radioSession: YtmRadioSession? = null
    /** When true, next/prev and autoplay stay within downloaded tracks only (no radio extension). */
    private var offlineQueueOnly = false
    private var radioExtendJob: Job? = null
    private var crossfadeAdvanceJob: Job? = null
    @Volatile
    private var manualVolumeRamp = false
    private var exoPlayer: ExoPlayer? = null
    private val streamResolveInFlight = ConcurrentHashMap.newKeySet<String>()
    private var trackEntryMs = 0L
    /** How long before track end we resolve URL + attach the next Exo media item. */
    private const val PRELOAD_LEAD_MS = 75_000L
    /** Foxy: prefetch more radio tracks when this many queue items remain. */
    private const val RADIO_LOAD_MORE_THRESHOLD = 5
    /** Chronological play order for back (previous track), Foxy-style. */
    private val playbackTimeline = mutableListOf<Song>()
    private var playbackTimelineIndex = -1
    @Volatile
    private var suppressTimelineRecord = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state
    private val _sleepTimerState = MutableStateFlow(SleepTimerUiState())
    val sleepTimerState: StateFlow<SleepTimerUiState> = _sleepTimerState

    /** Load persisted queue metadata (no automatic playback until the user presses play). */
    fun init(context: Context) {
        appContext = context.applicationContext
        FoxyDynamicTheme.bindContext(context.applicationContext)
        restorePersistedSession(context.applicationContext)
    }

    private fun restorePersistedSession(context: Context) {
        if (!FoxySettings.state.value.persistentQueue) return
        val session = PlaybackPersistence.loadSession(context) ?: return
        // If the user had downloaded some tracks, re-attach local paths so offline playback
        // continues to work after process restart.
        val localById = FoxyDownloadsPaths.listDownloadFiles(context)
            .associateBy({ it.nameWithoutExtension }, { it })

        queue = session.queue
            .map { song ->
                val localFile = localById[song.videoId]
                if (localFile != null && localFile.length() > 0L) {
                    song.copy(
                        localPath = localFile.absolutePath,
                        isDownloaded = true,
                        streamUrl = null,
                    )
                } else {
                    song
                }
            }
            .musicQueueTracksOnly()
        queueIndex = session.queueIndex
        shuffleEnabled = session.shuffle
        repeatMode = when (session.repeatOrdinal) {
            1 -> RepeatMode.All
            2 -> RepeatMode.One
            else -> RepeatMode.Off
        }
        val song = queue.getOrNull(queueIndex)
        _state.value = PlayerUiState(
            currentSong = song,
            isPlaying = false,
            isBuffering = false,
            durationMs = 0L,
            positionMs = session.positionMs.coerceAtLeast(0L),
            bufferedFraction = 0f,
            error = null,
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode
        )
    }

    private fun persistPlaybackSnapshot() {
        val ctx = appContext ?: return
        if (!FoxySettings.state.value.persistentQueue) return
        if (queue.isEmpty()) {
            PlaybackPersistence.clearSession(ctx)
            return
        }
        val pos = player?.currentPosition?.coerceAtLeast(0L) ?: _state.value.positionMs
        PlaybackPersistence.saveSession(
            ctx,
            queue,
            queueIndex,
            shuffleEnabled,
            repeatMode.ordinal,
            pos
        )
    }

    private fun startProgressTicker() {
    progressJob?.cancel()
    progressJob = scope.launch {
        while (isActive && player != null) {
            val p = player ?: break
            val durRaw = p.duration
            val dur = if (durRaw != C.TIME_UNSET && durRaw > 0L) durRaw else _state.value.durationMs
            val pos = p.currentPosition.coerceAtLeast(0L)
            val buffered = if (dur > 0L) {
                (p.bufferedPosition.toFloat() / dur.toFloat()).coerceIn(0f, 1f)
            } else 0f

            _state.update {
                it.copy(
                    positionMs = pos,
                    durationMs = dur.takeIf { d -> d > 0L } ?: it.durationMs,
                    bufferedFraction = buffered,
                    isPlaying = p.isPlaying,
                    isBuffering = p.playbackState == Player.STATE_BUFFERING && !p.isPlaying
                )
            }

            maybeScheduleEarlyPreload(dur, pos)
            if (!offlineQueueOnly) scheduleRadioExtendIfNeeded()
            applyVolumeCrossfade()
            maybeTriggerCrossfadeAdvance(dur, pos)
            maybeSkipSponsor(pos)

            delay(180)
        }
    }
}

    /**
     * Dynamic LoadControl tuned for YouTube audio streams.
     * Adapts buffer sizes based on WiFi vs Mobile + metered status.
     */
    private fun createDynamicLoadControl(context: Context): LoadControl {
        val connectivityManager = context.getSystemService<ConnectivityManager>()
        val network = connectivityManager?.activeNetwork
        val capabilities = network?.let { connectivityManager.getNetworkCapabilities(it) }

        val isWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val isMetered = connectivityManager?.isActiveNetworkMetered == true

        // Base conservative values good for flaky YT connections
        var minBufferMs = 25_000
        var maxBufferMs = 90_000
        var bufferForPlaybackMs = 3_000
        var bufferForPlaybackAfterRebufferMs = 8_000

        when {
            isWifi && !isMetered -> {
                // Fast connection → faster start
                minBufferMs = 18_000
                maxBufferMs = 120_000
                bufferForPlaybackMs = 2_000
            }
            capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> {
                // Mobile data → more buffering
                if (isMetered) {
                    minBufferMs = 35_000
                    maxBufferMs = 70_000
                    bufferForPlaybackMs = 5_000
                } else {
                    minBufferMs = 28_000
                    bufferForPlaybackMs = 3_500
                }
            }
            else -> {
                // Poor/unknown network
                minBufferMs = 40_000
                bufferForPlaybackMs = 6_000
            }
        }

        // Respect user's quality tier preference
        if (FoxySettings.state.value.streamQualityTier >= 2) {
            minBufferMs += 8_000
            maxBufferMs += 30_000
        }

        return DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                minBufferMs,
                maxBufferMs,
                bufferForPlaybackMs,
                bufferForPlaybackAfterRebufferMs
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .setTargetBufferBytes(DefaultLoadControl.DEFAULT_TARGET_BUFFER_BYTES)
            .build()
    }
    /** Foxy-style target level when normalization is enabled (reduces hot masters). */
    private fun effectiveUserVolume(): Float {
        var level = userVolume
        if (FoxySettings.state.value.normalizeVolume) {
            level *= 0.78f
        }
        return level.coerceIn(0f, 1f)
    }

    private fun applyVolumeCrossfade() {
        if (manualVolumeRamp) return
        val p = player ?: return
        val base = effectiveUserVolume()
        val cross = FoxySettings.state.value.crossfadeMs
        if (cross <= 0) {
            p.volume = base
            return
        }
        val rawDur = p.duration
        val dur = if (rawDur != C.TIME_UNSET && rawDur > 0L) rawDur else _state.value.durationMs.takeIf { it > 0L } ?: run {
            p.volume = base
            return
        }
        val pos = p.currentPosition.coerceAtLeast(0L)
        val c = cross.toLong()
        val rem = (dur - pos).coerceAtLeast(0L)
        val fadeOut = if (rem < c) (rem.toFloat() / c.toFloat()).coerceIn(0f, 1f) else 1f
        val entryElapsed = (SystemClock.elapsedRealtime() - trackEntryMs).coerceAtLeast(0L)
        val fadeIn = if (entryElapsed < c) (entryElapsed.toFloat() / c.toFloat()).coerceIn(0f, 1f) else 1f
        p.volume = base * min(fadeOut, fadeIn)
    }

    private suspend fun rampVolumeTo(
        target: Float,
        durationMs: Long,
        manageRampFlag: Boolean = true,
    ) {
        val p = player ?: return
        if (manageRampFlag) manualVolumeRamp = true
        try {
            val start = p.volume
            if (durationMs <= 0L) {
                p.volume = target
                return
            }
            val steps = (durationMs / 40L).coerceIn(1L, 24L).toInt()
            val stepMs = (durationMs / steps).coerceAtLeast(16L)
            repeat(steps) { step ->
                val t = (step + 1).toFloat() / steps.toFloat()
                p.volume = start + (target - start) * t
                delay(stepMs)
            }
            p.volume = target
        } finally {
            if (manageRampFlag) manualVolumeRamp = false
        }
    }

    private fun maybeScheduleEarlyPreload(durationMs: Long, positionMs: Long) {
        if (durationMs <= 0L) return
        val remaining = (durationMs - positionMs).coerceAtLeast(0L)
        val cross = FoxySettings.state.value.crossfadeMs.toLong()
        val leadMs = maxOf(PRELOAD_LEAD_MS, cross * 2L, 25_000L)
        if (remaining <= leadMs) {
            schedulePreloadNextTrack()
        }
    }

    private fun maybeTriggerCrossfadeAdvance(durationMs: Long, positionMs: Long) {
        val cross = FoxySettings.state.value.crossfadeMs
        if (cross <= 0 || repeatMode == RepeatMode.One) return
        if (durationMs <= cross) return
        val remaining = (durationMs - positionMs).coerceAtLeast(0L)
        if (remaining > cross || remaining <= 0L) return
        if (crossfadeAdvanceJob?.isActive == true) return
        crossfadeAdvanceJob = scope.launch {
            playbackMutex.withLock {
                crossfadeToNextTrackLocked()
            }
        }
    }

    private fun warmStreamUrl(videoId: String) {
        val vid = videoId.trim()
        if (vid.isEmpty()) return
        val tier = effectiveStreamQualityTier()
        if (StreamUrlCache.peek(vid, tier) != null) return
        if (!streamResolveInFlight.add(vid)) return
        scope.launch(Dispatchers.IO) {
            try {
                StreamExtractor.getStreamResult(vid, tier)
            } finally {
                streamResolveInFlight.remove(vid)
            }
        }
    }

    private fun effectiveStreamQualityTier(): Int {
        val settings = FoxySettings.state.value
        val fallback = settings.streamQualityTier.coerceIn(0, 4)
        val ctx = appContext ?: return fallback
        val cm = ctx.getSystemService<ConnectivityManager>() ?: return fallback
        val network = cm.activeNetwork ?: return fallback
        val capabilities = cm.getNetworkCapabilities(network) ?: return fallback
        val override = when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> settings.wifiQualityTier
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> settings.mobileQualityTier
            else -> -1
        }
        return if (override >= 0) override.coerceIn(0, 4) else fallback
    }

    /** Re-apply crossfade / normalization after settings change while playing. */
    fun refreshPlaybackAudioSettings() {
        scope.launch {
            applyVolumeCrossfade()
            runCatching {
                exoPlayer?.setSkipSilenceEnabled(FoxySettings.state.value.skipSilence)
            }
        }
    }

    private fun maybeSkipSponsor(positionMs: Long) {
        if (!FoxySettings.state.value.sponsorBlockEnabled || sponsorRangesMs.isEmpty()) return
        val p = player ?: return
        val rawDur = p.duration
        val dur = if (rawDur != C.TIME_UNSET && rawDur > 0L) rawDur else _state.value.durationMs
        val posSec = positionMs / 1000.0
        for ((startMs, endMs) in sponsorRangesMs) {
            val start = startMs / 1000.0
            val end = endMs / 1000.0
            if (posSec >= start && posSec < end - 0.07) {
                val target = if (dur > 0L) endMs.coerceAtMost(dur) else endMs
                p.seekTo(target)
                _state.update { it.copy(positionMs = target) }
                return
            }
        }
    }

    private fun loadSponsorSegments(videoId: String) {
        sponsorRangesMs = emptyList()
        if (!FoxySettings.state.value.sponsorBlockEnabled || videoId.isBlank()) return
        scope.launch(Dispatchers.IO) {
            val ranges = SponsorBlockApi.fetchSkipRangesSeconds(videoId).map { (s, e) ->
                (s * 1000).toLong() to (e * 1000).toLong()
            }
            withContext(Dispatchers.Main.immediate) {
                if (_state.value.currentSong?.videoId == videoId) {
                    sponsorRangesMs = ranges
                }
            }
        }
    }

    private fun stopProgressTicker() {
        progressJob?.cancel()
        progressJob = null
    }

    /** Pushes timeline duration into UI once the decoder knows stream length (fixes 0:00 / stuck seek). */
    private fun publishDurationFromPlayer() {
        val p = player ?: return
        val d = p.duration
        if (d == C.TIME_UNSET || d <= 0L) return
        _state.update { prev ->
            if (prev.durationMs == d) prev
            else prev.copy(durationMs = d)
        }
    }

    private var mediaSessionHolder: MediaSession? = null
    val mediaSession: MediaSession?
        get() = mediaSessionHolder

    /**
     * Pushes queue + "now playing" to [state] on the current thread so Flutter's
     * `getPlayerState` (called right after `playQueue` / `play` returns) already sees the new track.
     * Heavy work (radio fetch, stream URL) still runs inside [playPrepared] on the coroutine.
     */
    private fun publishInstantPlaybackUi(song: Song) {
        retryAttemptsForCurrent = 0
        _state.value = _state.value.copy(
            currentSong = song,
            isBuffering = true,
            isPlaying = false,
            error = null,
            durationMs = 0L,
            positionMs = 0L,
            bufferedFraction = 0f,
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode
        )
    }

    fun playQueue(
        context: Context,
        songs: List<Song>,
        startIndex: Int = 0,
        radioTail: Boolean = false,
        offlineQueueOnly: Boolean = false,
    ) {
        if (songs.isEmpty()) return
        appContext = context.applicationContext
        val ctx = context.applicationContext
        this.offlineQueueOnly = offlineQueueOnly
        if (offlineQueueOnly) {
            radioSession = null
            val offlineQueue = buildOfflinePlayQueue(ctx, songs)
            if (offlineQueue.isEmpty()) {
                _state.update {
                    it.copy(
                        error = "No downloaded tracks ready to play offline",
                        isBuffering = false,
                        isPlaying = false,
                    )
                }
                return
            }
            queue = offlineQueue
            val startVid = songs.getOrNull(startIndex.coerceIn(0, songs.lastIndex))?.videoId
            queueIndex = queue.indexOfFirst { it.videoId == startVid }.takeIf { it >= 0 }
                ?: 0
            val startSong = queue[queueIndex]
            publishInstantPlaybackUi(startSong)
            val requestId = ++activePlayRequestId
            scope.launch { playPrepared(ctx, startSong, requestId) }
            return
        }
        if (radioTail) {
            val idx = startIndex.coerceIn(0, songs.lastIndex)
            val seed = songs[idx]
            queue = songs.distinctBy { it.videoId }.ifEmpty { listOf(seed) }
            queueIndex = queue.indexOfFirst { it.videoId == seed.videoId }
                .takeIf { it >= 0 } ?: 0
            publishInstantPlaybackUi(seed)
            warmStreamUrl(seed.videoId)
            radioSession = YtmRadioSession.forSeed(seed.videoId)
            val requestId = ++activePlayRequestId
            scope.launch { playPrepared(ctx, seed, requestId) }
            scope.launch {
                val (session, radio) = withContext(Dispatchers.IO) {
                    runCatching { YTMusicApi.fetchRadioPage(seed, radioSession) }
                        .getOrDefault(radioSession!! to emptyList())
                }
                radioSession = session
                val ordered = radio.distinctBy { it.videoId }.filter { it.isMusicQueueTrack() }
                queue = if (ordered.any { it.videoId == seed.videoId }) {
                    ordered
                } else {
                    listOf(seed) + ordered
                }
                if (queue.isEmpty()) queue = listOf(seed)
                queueIndex = session.queueStartIndex.coerceIn(0, queue.lastIndex)
                if (queue.getOrNull(queueIndex)?.videoId != seed.videoId) {
                    queueIndex = queue.indexOfFirst { it.videoId == seed.videoId }
                        .takeIf { it >= 0 } ?: 0
                }
                val startSong = queue[queueIndex]
                _state.update {
                    it.copy(queue = queue, queueIndex = queueIndex)
                }
                if (startSong.videoId != seed.videoId) {
                    playPrepared(ctx, startSong, requestId)
                }
            }
        } else {
            radioSession = null
            val filtered = songs.distinctBy { it.videoId }.musicQueueTracksOnly()
            if (filtered.isEmpty()) return
            queue = filtered
            queueIndex = startIndex.coerceIn(0, queue.lastIndex)
            val startSong = queue[queueIndex]
            publishInstantPlaybackUi(startSong)
            warmStreamUrl(startSong.videoId)
            scope.launch {
                val requestId = ++activePlayRequestId
                playPrepared(ctx, startSong, requestId)
            }
        }
    }

    fun play(context: Context, song: Song) {
        appContext = context.applicationContext
        offlineQueueOnly = false
        radioSession = null
        if (queue.none { it.videoId == song.videoId }) {
            queue = listOf(song)
            queueIndex = 0
        } else {
            queueIndex = queue.indexOfFirst { it.videoId == song.videoId }
        }
        publishInstantPlaybackUi(song)
        warmStreamUrl(song.videoId)
        scope.launch {
            val requestId = ++activePlayRequestId
            playPrepared(context.applicationContext, song, requestId)
        }
    }

    fun play(context: Context, url: String, song: Song) {
        scope.launch {
            playResolved(context.applicationContext, url, song)
        }
    }

    /** Queue of library downloads that have a local file or offline HLS bundle. */
    private fun buildOfflinePlayQueue(context: Context, songs: List<Song>): List<Song> {
        val downloadedById = FoxyLibraryStore.state.value.downloadedSongs.associateBy { it.videoId }
        return songs
            .distinctBy { it.videoId }
            .mapNotNull { raw ->
                val base = downloadedById[raw.videoId] ?: raw
                val enriched = enrichOfflineSong(context, base)
                if (FoxyOfflineBundle.resolvePlayableUrl(context, enriched) != null) enriched else null
            }
            .musicQueueTracksOnly()
    }

    private fun enrichOfflineSong(context: Context, song: Song): Song {
        val local = song.localPath?.trim()?.takeIf { it.isNotBlank() }?.let { File(it) }
            ?.takeIf { it.isFile && it.length() > 0L }
            ?: FoxyDownloadsPaths.findMediaFile(context, song.videoId)
        return song.copy(
            isDownloaded = true,
            localPath = local?.absolutePath,
            streamUrl = null,
        )
    }

    private fun resolveOfflineMediaFile(context: Context, song: Song): File? {
        song.localPath?.trim()?.takeIf { it.isNotBlank() }?.let { path ->
            File(path).takeIf { it.isFile && it.length() > 0L }?.let { return it }
        }
        val vid = song.videoId.trim()
        if (vid.isBlank()) return null
        return FoxyDownloadsPaths.findMediaFile(context, vid)
    }

    private suspend fun playPrepared(context: Context, song: Song, requestId: Long = activePlayRequestId) {
        playbackMutex.withLock {
            if (requestId != activePlayRequestId) return@withLock
            playPreparedLocked(context, song, requestId)
        }
    }

    private fun recordPlaybackTimeline(song: Song) {
        if (suppressTimelineRecord) return
        val vid = song.videoId.trim()
        if (vid.isEmpty()) return
        if (playbackTimelineIndex in 0 until playbackTimeline.lastIndex) {
            playbackTimeline.subList(playbackTimelineIndex + 1, playbackTimeline.size).clear()
        }
        val last = playbackTimeline.lastOrNull()
        if (last?.videoId == vid) {
            playbackTimelineIndex = playbackTimeline.lastIndex
        } else {
            playbackTimeline.add(song)
            playbackTimelineIndex = playbackTimeline.lastIndex
        }
    }

    private fun canPlayTimelinePrevious(): Boolean = playbackTimelineIndex > 0

    private suspend fun playPreparedLocked(context: Context, song: Song, requestId: Long = activePlayRequestId) {
        if (requestId != activePlayRequestId) return
        appContext = context.applicationContext
        crossfadeAdvanceJob?.cancel()
        recordPlaybackTimeline(song)
        if (queue.none { it.videoId == song.videoId }) {
            queue = listOf(song)
            queueIndex = 0
        } else {
            queueIndex = queue.indexOfFirst { it.videoId == song.videoId }
        }
        // Reset retry state whenever user selects a new track (or queue index changes to a new track).
        retryAttemptsForCurrent = 0
        _state.value = _state.value.copy(
                currentSong = song,
                isBuffering = true,
                isPlaying = false,
                error = null,
                durationMs = 0L,
                positionMs = 0L,
                bufferedFraction = 0f,
                queue = queue,
                queueIndex = queueIndex,
                shuffleEnabled = shuffleEnabled,
                repeatMode = repeatMode
            )

        // Offline: library metadata + local file or cached HLS manifest.
        val librarySong = FoxyLibraryStore.state.value.downloadedSongs
            .firstOrNull { it.videoId == song.videoId }
            ?: FoxyLibraryStore.state.value.getSongById(song.videoId)
        val offlineBase = librarySong ?: song
        FoxyOfflineBundle.resolvePlayableUrl(context, offlineBase)?.let { url ->
            if (requestId != activePlayRequestId) return
            val enriched = offlineBase.copy(isDownloaded = true)
            playResolved(context, url, enriched)
            if (!offlineQueueOnly) scope.launch { maybeExtendQueueForAutoplay() }
            return
        }

        if (tryAdvanceToPreloadedInExo(song)) {
            if (!offlineQueueOnly) scope.launch { maybeExtendQueueForAutoplay() }
            return
        }

        val cached = preloadedStream
        if (cached != null && cached.first == song.videoId && !cached.second.isNullOrBlank()) {
            if (requestId != activePlayRequestId) return
            preloadedStream = null
            playResolved(context, cached.second, song)
            return
        }

        val tier = effectiveStreamQualityTier()
        StreamExtractor.peekCachedStreamResult(song.videoId, tier, song.streamSearchQuery())?.url?.let { url ->
            if (requestId != activePlayRequestId) return
            playResolved(context, url, song)
            if (!offlineQueueOnly) scope.launch { maybeExtendQueueForAutoplay() }
            return
        }

        if (offlineQueueOnly) {
            _state.update {
                it.copy(isBuffering = false, isPlaying = false, error = "Track is not available offline")
            }
            return
        }

        val result = resolveFreshStreamResult(song, tier)
        if (requestId != activePlayRequestId) return
        result.url?.let {
            playResolved(context, it, song, result)
            if (!offlineQueueOnly) scope.launch { maybeExtendQueueForAutoplay() }
        } ?: _state.update {
            it.copy(isBuffering = false, isPlaying = false, error = result.error ?: "Playback failed")
        }
    }

    /**
     * Foxy-style infinite queue: paginated Innertube radio (`RDAMVM` + continuation).
     */
    private suspend fun maybeExtendQueueForAutoplay(): Boolean {
        if (offlineQueueOnly) return false
        if (queue.isEmpty() || shuffleEnabled) return false
        val remaining = queue.lastIndex - queueIndex
        if (queue.size > 1 && remaining > RADIO_LOAD_MORE_THRESHOLD) return false
        val seed = _state.value.currentSong ?: queue.getOrNull(queueIndex) ?: return false
        val session = radioSession?.takeIf { it.seedVideoId == seed.videoId }
            ?: YtmRadioSession.forSeed(seed.videoId).also { radioSession = it }
        if (session.exhausted && session.continuation == null && queue.size > 1) return false

        val (updatedSession, more) = withContext(Dispatchers.IO) {
            runCatching { YTMusicApi.fetchRadioPage(seed, session) }.getOrDefault(session to emptyList())
        }
        radioSession = updatedSession
        if (more.isEmpty()) return false
        val merged = (queue + more).distinctBy { it.videoId }.musicQueueTracksOnly()
        if (merged.size <= queue.size) return false
        queue = merged
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
        schedulePreloadNextTrack()
        return true
    }

    private fun scheduleRadioExtendIfNeeded() {
        if (offlineQueueOnly) return
        if (shuffleEnabled || queue.isEmpty()) return
        val remaining = queue.lastIndex - queueIndex
        if (remaining > RADIO_LOAD_MORE_THRESHOLD) return
        val seed = _state.value.currentSong ?: return
        val session = radioSession
        if (session != null && session.seedVideoId != seed.videoId) {
            radioSession = YtmRadioSession.forSeed(seed.videoId)
        }
        if (radioExtendJob?.isActive == true) return
        radioExtendJob = scope.launch {
            playbackMutex.withLock {
                maybeExtendQueueForAutoplay()
            }
        }
    }

    private fun peekNextQueueIndex(): Int? {
        if (queue.isEmpty()) return null
        if (queue.size == 1) {
            return if (repeatMode == RepeatMode.All) 0 else null
        }
        return when {
            shuffleEnabled -> indexOfRandomMusicTrack(queueIndex)
            else -> indexOfNextMusicTrack(queueIndex, repeatMode == RepeatMode.All)
        }
    }

    private fun peekNextQueueSong(): Song? {
        val index = peekNextQueueIndex() ?: return null
        return queue.getOrNull(index)
    }

    private suspend fun resolveNextQueueIndex(loop: Boolean): Int? {
        if (queue.isEmpty()) return null
        if (queue.size == 1) return if (loop) 0 else null
        var nextIndex = when {
            shuffleEnabled && queue.size > 1 -> indexOfRandomMusicTrack(queueIndex)
            else -> indexOfNextMusicTrack(queueIndex, loop)
        }
        if (nextIndex == null && !shuffleEnabled) {
            if (!maybeExtendQueueForAutoplay()) return null
            nextIndex = indexOfNextMusicTrack(queueIndex, loop)
        }
        return nextIndex
    }

    /** Skip non-songs, podcasts, playlists, and tracks longer than 10 minutes. */
    private fun indexOfNextMusicTrack(fromIndex: Int, loop: Boolean): Int? {
        if (queue.isEmpty()) return null
        for (i in (fromIndex + 1)..queue.lastIndex) {
            if (queue[i].isMusicQueueTrack() && !queue[i].exceedsQueueDurationCap()) return i
        }
        if (loop) {
            for (i in 0..fromIndex.coerceAtMost(queue.lastIndex)) {
                if (queue[i].isMusicQueueTrack() && !queue[i].exceedsQueueDurationCap()) return i
            }
        }
        return null
    }

    private fun indexOfRandomMusicTrack(excluding: Int): Int? {
        val picks = queue.indices.filter {
            it != excluding && queue[it].isMusicQueueTrack() && !queue[it].exceedsQueueDurationCap()
        }
        return picks.randomOrNull()
    }

    private fun schedulePreloadNextTrack() {
        preloadJob?.cancel()
        val ctx = appContext ?: return
        val nextIndex = peekNextQueueIndex() ?: run {
            preloadedStream = null
            preloadedForQueueIndex = -1
            return
        }
        val next = queue.getOrNull(nextIndex) ?: return
        val vid = next.videoId
        warmStreamUrl(vid)
        if (preloadedStream?.first == vid && preloadedForQueueIndex == nextIndex) {
            scope.launch(Dispatchers.Main.immediate) {
                attachNextMediaItemToExo(next, preloadedStream!!.second)
            }
            return
        }
        preloadedForQueueIndex = nextIndex
        preloadJob = scope.launch(Dispatchers.IO) {
            val url = resolveStreamUrlForSong(ctx, next)
            if (url.isNullOrBlank()) return@launch
            if (peekNextQueueIndex() != nextIndex) return@launch
            preloadedStream = vid to url
            withContext(Dispatchers.Main.immediate) {
                if (peekNextQueueIndex() == nextIndex) {
                    attachNextMediaItemToExo(next, url)
                }
            }
        }
    }

    /**
     * Seamless handoff when [schedulePreloadNextTrack] already attached the next item to Exo.
     * Avoids [playResolved] wiping the playlist and causing a buffer gap ("ghost pause").
     */
    private suspend fun tryAdvanceToPreloadedInExo(song: Song): Boolean {
        val exo = exoPlayer ?: return false
        if (!exoHasPreloadedNext(song)) return false
        val idx = queue.indexOfFirst { it.videoId == song.videoId }
        if (idx < 0) return false
        queueIndex = idx
        crossfadeAdvanceJob?.cancel()
        recordPlaybackTimeline(song)
        retryAttemptsForCurrent = 0
        val gen = ++suppressEndAdvanceGeneration
        suppressEndAdvance = true
        try {
            exo.seekToNextMediaItem()
            trimPlayedMediaItemsBehindCurrent()
            trackEntryMs = SystemClock.elapsedRealtime()
            applyNowPlayingUi(song)
            publishDurationFromPlayer()
            preloadedStream = null
            preloadedForQueueIndex = -1
            val url = exo.currentMediaItem?.localConfiguration?.uri?.toString().orEmpty()
            if (!url.startsWith("file:", ignoreCase = true)) {
                loadSponsorSegments(song.videoId)
            } else {
                sponsorRangesMs = emptyList()
            }
            schedulePreloadNextTrack()
            persistPlaybackSnapshot()
            FoxyMediaSessionService.refreshPlaybackNotification(appContext ?: return true)
            return true
        } finally {
            scope.launch {
                delay(450)
                if (suppressEndAdvanceGeneration == gen) {
                    suppressEndAdvance = false
                }
            }
        }
    }

    /** If Exo already auto-advanced to the preloaded item, sync app queue state (no second load). */
    private fun syncIfExoAlreadyOnDifferentTrack(): Boolean {
        val exo = exoPlayer ?: return false
        if (exo.mediaItemCount <= 1) return false
        val mediaId = exo.currentMediaItem?.mediaId ?: return false
        val playingId = _state.value.currentSong?.videoId ?: return false
        if (mediaId == playingId) return false
        val matched = queue.firstOrNull { it.videoId == mediaId } ?: return false
        val idx = queue.indexOfFirst { it.videoId == mediaId }
        if (idx >= 0) queueIndex = idx
        trackEntryMs = SystemClock.elapsedRealtime()
        applyNowPlayingUi(matched)
        schedulePreloadNextTrack()
        return true
    }

    private suspend fun resolveStreamUrlForSong(context: Context, song: Song): String? {
        val librarySong = FoxyLibraryStore.state.value.downloadedSongs
            .firstOrNull { it.videoId == song.videoId }
            ?: FoxyLibraryStore.state.value.getSongById(song.videoId)
        val offlineBase = librarySong ?: song
        FoxyOfflineBundle.resolvePlayableUrl(context, offlineBase)?.let { return it }
        preloadedStream?.takeIf { it.first == song.videoId }?.second?.let { return it }
        val tier = effectiveStreamQualityTier()
        StreamExtractor.peekCachedStreamResult(song.videoId, tier, song.streamSearchQuery())?.url?.let { return it }
        return resolveFreshStreamResult(song, tier).url
    }

    private suspend fun resolveFreshStreamResult(song: Song, tier: Int): StreamResult =
        withContext(Dispatchers.IO) {
            val preferred = tier.coerceIn(0, 4)
            val attempts = (preferred downTo 0).toList()
            var last = StreamResult(null, "Could not fetch stream URL")
            for (attemptTier in attempts) {
                val result = StreamExtractor.getStreamResult(song.videoId, attemptTier, song.streamSearchQuery())
                if (!result.url.isNullOrBlank()) return@withContext result
                last = result
            }
            last
        }

    private fun buildMediaItem(song: Song, url: String): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(song.title)
            .setDisplayTitle(song.title)
            .setArtist(song.artist)
            .apply {
                song.album?.takeIf { it.isNotBlank() }?.let { setAlbumTitle(it) }
            }
            .setArtworkUri(song.highQualityArtworkUrl().takeIf { it.isNotBlank() }?.let(Uri::parse))
            .build()
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaId(song.videoId)
            .setMediaMetadata(metadata)
        MimeTypeHint.fromUrl(url)?.let { itemBuilder.setMimeType(it) }
        return itemBuilder.build()
    }

    private fun attachNextMediaItemToExo(song: Song, url: String) {
        val exo = exoPlayer ?: return
        val currentIndex = exo.currentMediaItemIndex
        if (currentIndex < 0) return
        if (exo.mediaItemCount > currentIndex + 1) {
            val existing = exo.getMediaItemAt(currentIndex + 1)
            if (existing.mediaId == song.videoId) return
            exo.removeMediaItem(currentIndex + 1)
        }
        exo.addMediaItem(buildMediaItem(song, url))
    }

    private fun trimPlayedMediaItemsBehindCurrent() {
        val exo = exoPlayer ?: return
        while (exo.mediaItemCount > 1 && exo.currentMediaItemIndex > 0) {
            exo.removeMediaItem(0)
        }
    }

    private fun applyNowPlayingUi(song: Song) {
        if (FoxySettings.state.value.saveHistory) {
            FoxyLibraryStore.addHistory(song)
        }
        FoxyDynamicTheme.updateFromSong(song)
        _state.value = _state.value.copy(
            currentSong = song,
            isBuffering = false,
            error = null,
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode,
        )
        FoxyMediaSessionService.refreshPlaybackNotification(appContext ?: return)
    }

    private fun publishPendingNowPlayingUi(
        song: Song,
        isPlaying: Boolean = false,
        isBuffering: Boolean = true,
    ) {
        FoxyDynamicTheme.updateFromSong(song)
        _state.value = _state.value.copy(
            currentSong = song,
            isPlaying = isPlaying,
            isBuffering = isBuffering,
            error = null,
            durationMs = 0L,
            positionMs = 0L,
            bufferedFraction = 0f,
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode,
        )
        FoxyMediaSessionService.refreshPlaybackNotification(appContext ?: return)
    }

    private fun exoHasPreloadedNext(song: Song): Boolean {
        val exo = exoPlayer ?: return false
        val index = exo.currentMediaItemIndex
        if (index < 0 || exo.mediaItemCount <= index + 1) return false
        return exo.getMediaItemAt(index + 1).mediaId == song.videoId
    }

    private suspend fun crossfadeToNextTrackLocked() {
        val context = appContext ?: return
        val cross = FoxySettings.state.value.crossfadeMs
        if (cross <= 0 || repeatMode == RepeatMode.One) return
        val current = _state.value.currentSong ?: return
        val loop = repeatMode == RepeatMode.All
        val nextIndex = resolveNextQueueIndex(loop) ?: return
        val nextSong = queue.getOrNull(nextIndex) ?: return
        if (nextSong.videoId == current.videoId) return

        val url = resolveStreamUrlForSong(context, nextSong) ?: return
        preloadedStream = nextSong.videoId to url
        preloadedForQueueIndex = nextIndex

        val exo = exoPlayer ?: return
        val rawDur = exo.duration
        val dur = if (rawDur != C.TIME_UNSET && rawDur > 0L) rawDur else _state.value.durationMs
        val pos = exo.currentPosition.coerceAtLeast(0L)
        val remaining = (dur - pos).coerceAtLeast(0L)
        val fadeOutMs = remaining.coerceAtMost((cross / 2).toLong()).coerceAtLeast(80L)

        val gen = ++suppressEndAdvanceGeneration
        suppressEndAdvance = true
        manualVolumeRamp = true
        try {
            rampVolumeTo(0f, fadeOutMs, manageRampFlag = false)
            attachNextMediaItemToExo(nextSong, url)
            queueIndex = nextIndex
            recordPlaybackTimeline(nextSong)
            retryAttemptsForCurrent = 0
            preloadedStream = null
            preloadedForQueueIndex = -1

            if (exoHasPreloadedNext(nextSong)) {
                exo.seekToNextMediaItem()
                trimPlayedMediaItemsBehindCurrent()
                trackEntryMs = SystemClock.elapsedRealtime()
                applyNowPlayingUi(nextSong)
                publishDurationFromPlayer()
                if (!url.startsWith("file:", ignoreCase = true)) {
                    loadSponsorSegments(nextSong.videoId)
                } else {
                    sponsorRangesMs = emptyList()
                }
                rampVolumeTo(effectiveUserVolume(), (cross / 2).toLong(), manageRampFlag = false)
                schedulePreloadNextTrack()
            } else {
                playResolved(context, url, nextSong)
            }
        } finally {
            manualVolumeRamp = false
            applyVolumeCrossfade()
            scope.launch {
                delay(500)
                if (suppressEndAdvanceGeneration == gen) {
                    suppressEndAdvance = false
                }
            }
        }
    }

    private fun playResolved(context: Context, url: String, song: Song, stream: StreamResult? = null) {
        appContext = context.applicationContext
        FoxyDynamicTheme.bindContext(context.applicationContext)
        if (FoxySettings.state.value.saveHistory) {
            FoxyLibraryStore.addHistory(song)
        }
        FoxyDynamicTheme.updateFromSong(song)
        _state.value = _state.value.copy(
            currentSong = song,
            isBuffering = true,
            error = null,
            durationMs = 0L,
            positionMs = 0L,
            bufferedFraction = 0f,
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode,
            volume = userVolume,
            streamBitrate = stream?.bitrate,
            streamCodec = stream?.codec,
            streamMimeType = stream?.mimeType,
            streamSampleRate = stream?.sampleRate,
            streamItag = stream?.itag,
            streamSource = stream?.source,
            streamQualityLabel = stream?.qualityLabel,
        )
        val swapGen = ++suppressEndAdvanceGeneration
        suppressEndAdvance = true
        try {
            if (player == null) {
                val okHttp = FoxyNetworking.streamingClient()

                val upstreamFactory = OkHttpDataSource.Factory(okHttp)
                    .setUserAgent(StreamExtractor.STREAM_USER_AGENT)
                    .setDefaultRequestProperties(buildStreamHeaders())

                val defaultDataSourceFactory = DefaultDataSource.Factory(
                    context.applicationContext,
                    upstreamFactory,
                )

                val cacheFactory = CacheDataSource.Factory()
                    .setCache(FoxyCache.get(context.applicationContext))
                    .setUpstreamDataSourceFactory(defaultDataSourceFactory)
                    .setFlags(
                        CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR,
                    )
                val exo = ExoPlayer.Builder(context.applicationContext)
                    .setLoadControl(createDynamicLoadControl(context.applicationContext))
                    .setMediaSourceFactory(DefaultMediaSourceFactory(cacheFactory))
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(C.USAGE_MEDIA)
                            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                            .build(),
                        /* handleAudioFocus = */ true
                    )
                    .setHandleAudioBecomingNoisy(true)
                    .build()
                runCatching {
                    exo.setSkipSilenceEnabled(FoxySettings.state.value.skipSilence)
                }
                exoPlayer = exo
                player = FoxyQueueForwardingPlayer(exo)

                player?.addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        val p = player
                        _state.update {
                            it.copy(
                                isBuffering = state == Player.STATE_BUFFERING &&
                                    p?.isPlaying != true,
                                isPlaying = when (state) {
                                    Player.STATE_READY -> p?.isPlaying == true
                                    Player.STATE_IDLE,
                                    Player.STATE_ENDED -> false
                                    else -> p?.isPlaying == true
                                },
                                error = if (state == Player.STATE_READY) null else it.error,
                                durationMs = player?.duration?.takeIf { duration ->
                                    duration != C.TIME_UNSET && duration > 0
                                } ?: it.durationMs
                            )
                        }
                        when (state) {
                            Player.STATE_BUFFERING -> Unit
                            Player.STATE_READY -> {
                                _state.update {
                                    it.copy(
                                        isBuffering = false,
                                        isPlaying = p?.isPlaying == true,
                                        error = null,
                                    )
                                }
                                publishDurationFromPlayer()
                                schedulePreloadNextTrack()
                            }
                            Player.STATE_ENDED -> {
                                if (suppressEndAdvance) {
                                    return
                                }
                                // Never call prepare/stop/playNext synchronously from Player.Listener — ExoPlayer can crash.
                                scope.launch {
                                    delay(40)
                                    if (appContext == null || suppressEndAdvance) return@launch
                                    playbackMutex.withLock {
                                        if (suppressEndAdvance) return@withLock
                                        if (syncIfExoAlreadyOnDifferentTrack()) {
                                            return@withLock
                                        }
                                        if (stopAfterCurrentSong) {
                                            stopAfterCurrentSong = false
                                            _sleepTimerState.value = SleepTimerUiState()
                                            pause()
                                            return@withLock
                                        }
                                        when (repeatMode) {
                                            RepeatMode.One -> {
                                                player?.seekTo(0)
                                                player?.playWhenReady = true
                                            }
                                            RepeatMode.All -> advanceToNextLocked(loop = true)
                                            RepeatMode.Off -> advanceToNextLocked(loop = false)
                                        }
                                    }
                                }
                            }
                            Player.STATE_IDLE -> Unit
                        }
                    }
                    override fun onPlayerError(error: PlaybackException) {
                        Log.e("FoxyMusic", "Playback error: ${error.message}")
                        Log.e("FoxyMusic", "Error cause: ${error.cause}")

                        // One-time retry: stream URL resolution can occasionally fail transiently.
                        // If it fails again, we surface the error to the UI.
                        val current = _state.value.currentSong
                        val shouldRetry = current != null && retryAttemptsForCurrent == 0
                        if (shouldRetry) {
                            retryAttemptsForCurrent = 1
                            StreamUrlCache.invalidate(current.videoId)
                            scope.launch {
                                val ctx = appContext ?: return@launch
                                try {
                                    val tier = effectiveStreamQualityTier()
                                    val result = withContext(Dispatchers.IO) {
                                        resolveFreshStreamResult(current, tier)
                                    }
                                    val url = result.url
                                    if (url != null) {
                                        playResolved(ctx, url, current, result)
                                    } else {
                                        _state.update {
                                            it.copy(
                                                isPlaying = false,
                                                isBuffering = false,
                                                error = result.error ?: (error.message ?: "Playback failed")
                                            )
                                        }
                                    }
                                } catch (_: Exception) {
                                    _state.update {
                                        it.copy(
                                            isPlaying = false,
                                            isBuffering = false,
                                            error = error.message ?: "Playback failed"
                                        )
                                    }
                                }
                            }
                        } else {
                            if (FoxySettings.state.value.autoSkipNextOnError && queue.size > 1) {
                                scope.launch {
                                    playbackMutex.withLock {
                                        advanceToNextLocked(loop = false)
                                    }
                                }
                            } else {
                                _state.update {
                                    it.copy(
                                        isPlaying = false,
                                        isBuffering = false,
                                        error = error.message ?: "Playback failed"
                                    )
                                }
                            }
                        }
                    }
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        _state.update {
                            it.copy(isPlaying = isPlaying, isBuffering = false, error = null)
                        }
                        publishDurationFromPlayer()
                        persistPlaybackSnapshot()
                    }

                    override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
                        publishDurationFromPlayer()
                    }

                    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                        publishDurationFromPlayer()
                        val item = mediaItem ?: return
                        val song = queue.getOrNull(queueIndex)
                        if (song?.videoId == item.mediaId) return
                        val matched = queue.firstOrNull { it.videoId == item.mediaId } ?: return
                        val idx = queue.indexOfFirst { it.videoId == matched.videoId }
                        if (idx >= 0) queueIndex = idx
                        trackEntryMs = SystemClock.elapsedRealtime()
                        applyNowPlayingUi(matched)
                        schedulePreloadNextTrack()
                    }

                    override fun onEvents(player: Player, events: Player.Events) {
                        if (events.contains(Player.EVENT_TIMELINE_CHANGED) ||
                            events.contains(Player.EVENT_TRACKS_CHANGED) ||
                            events.contains(Player.EVENT_IS_LOADING_CHANGED)
                        ) {
                            publishDurationFromPlayer()
                            _state.update {
                                it.copy(
                                    isBuffering = player.playbackState == Player.STATE_BUFFERING &&
                                        !player.isPlaying,
                                    isPlaying = player.isPlaying,
                                    durationMs = player.duration.takeIf { duration ->
                                        duration != C.TIME_UNSET && duration > 0
                                    } ?: it.durationMs
                                )
                            }
                        }
                    }
                })
            }

            syncMediaSession(context.applicationContext)

            val mediaItem = buildMediaItem(song, url)
            val exo = exoPlayer ?: throw IllegalStateException("Player not initialized")
            crossfadeAdvanceJob?.cancel()
            trackEntryMs = SystemClock.elapsedRealtime()
            exo.playWhenReady = true
            exo.stop()
            exo.clearMediaItems()
            exo.setMediaItem(mediaItem, /* resetPosition= */ true)
            exo.prepare()
            exo.playWhenReady = true
            exo.play()
            scheduleBufferWatchdog(song.videoId, swapGen)
            FoxyMediaSessionService.refreshPlaybackNotification(context.applicationContext)
            if (!url.startsWith("file:", ignoreCase = true)) {
                loadSponsorSegments(song.videoId)
            } else {
                sponsorRangesMs = emptyList()
            }
            applyVolumeCrossfade()
            startProgressTicker()
            persistPlaybackSnapshot()
            schedulePreloadNextTrack()

        } catch (e: Exception) {
            Log.e("FoxyMusic", "Exception in play(): ${e.message}")
            _state.update {
                it.copy(isPlaying = false, isBuffering = false, error = e.message ?: "Playback failed")
            }
        } finally {
            val gen = swapGen
            scope.launch {
                delay(450)
                if (suppressEndAdvanceGeneration == gen) {
                    suppressEndAdvance = false
                }
            }
        }
    }

    private fun scheduleBufferWatchdog(videoId: String, generation: Int) {
        scope.launch {
            delay(9000)
            val current = _state.value.currentSong ?: return@launch
            if (generation != suppressEndAdvanceGeneration) return@launch
            if (current.videoId != videoId) return@launch
            val exo = player ?: return@launch
            if (exo.playbackState != Player.STATE_BUFFERING) return@launch
            if (exo.isPlaying) return@launch
            if (retryAttemptsForCurrent > 0) return@launch
            retryAttemptsForCurrent = 1
            StreamUrlCache.invalidate(videoId)
            val ctx = appContext ?: return@launch
            val tier = effectiveStreamQualityTier()
            val song = _state.value.currentSong?.takeIf { it.videoId == videoId }
                ?: queue.firstOrNull { it.videoId == videoId }
                ?: Song(videoId = videoId, title = videoId, artist = "")
            val result = resolveFreshStreamResult(song, tier)
            val freshUrl = result.url
            if (freshUrl.isNullOrBlank()) {
                _state.update {
                    it.copy(
                        isBuffering = false,
                        isPlaying = false,
                        error = result.error ?: "Playback failed",
                    )
                }
                return@launch
            }
            playResolved(ctx, freshUrl, current, result)
        }
    }

    fun togglePlayPause() {
        scope.launch {
            val ctx = appContext
            val exo = player
            if (exo == null) {
                val song = _state.value.currentSong
                    ?: queue.getOrNull(queueIndex.coerceAtLeast(0))
                if (song == null || ctx == null) {
                    Log.w("FoxyMusic", "togglePlayPause: no track loaded to restart")
                    return@launch
                }
                playPrepared(ctx, song)
                return@launch
            }
            if (exo.isPlaying) {
                _state.update { it.copy(isPlaying = false, isBuffering = false, error = null) }
                exo.pause()
            } else {
                _state.update { it.copy(isPlaying = true, isBuffering = false, error = null) }
                exo.play()
            }
        }
    }

    fun pause() {
        scope.launch { player?.pause() }
    }

    fun isPlaying(): Boolean = player?.isPlaying ?: false

    fun currentPosition(): Long = player?.currentPosition?.coerceAtLeast(0L) ?: 0L

    fun duration(): Long {
        val d = player?.duration ?: C.TIME_UNSET
        return if (d != C.TIME_UNSET && d > 0L) d else state.value.durationMs
    }

    fun seekTo(positionMs: Long) {
        val pos = positionMs.coerceAtLeast(0L)
        scope.launch {
            player?.seekTo(pos)
            _state.update { it.copy(positionMs = pos) }
            persistPlaybackSnapshot()
        }
    }

    fun playNext(loop: Boolean = false) {
        scope.launch {
            playbackMutex.withLock {
                advanceToNextLocked(loop)
            }
        }
    }

    private suspend fun advanceToNextLocked(loop: Boolean) {
        val context = appContext ?: return
        if (queue.isEmpty()) return
        val requestId = ++activePlayRequestId
        if (queue.size == 1) {
            queueIndex = 0
            player?.let { p ->
                val gen = ++suppressEndAdvanceGeneration
                suppressEndAdvance = true
                try {
                    p.seekTo(0L)
                    p.playWhenReady = true
                    p.play()
                } finally {
                    scope.launch {
                        delay(200)
                        if (suppressEndAdvanceGeneration == gen) {
                            suppressEndAdvance = false
                        }
                    }
                }
            }
            return
        }
        val nextIndex = resolveNextQueueIndex(loop) ?: return
        val nextSong = queue[nextIndex]
        val cross = FoxySettings.state.value.crossfadeMs
        if (cross > 0 && repeatMode != RepeatMode.One) {
            crossfadeToNextTrackLocked()
            return
        }
        queueIndex = nextIndex
        publishPendingNowPlayingUi(
            nextSong,
            isPlaying = _state.value.isPlaying,
            isBuffering = false,
        )
        if (tryAdvanceToPreloadedInExo(nextSong)) {
            if (!offlineQueueOnly) maybeExtendQueueForAutoplay()
            return
        }
        val url = resolveStreamUrlForSong(context, nextSong)
        if (requestId != activePlayRequestId) return
        if (url != null) {
            playResolved(context, url, nextSong)
            return
        }
        playPreparedLocked(context, nextSong, requestId)
    }

    fun playPrevious() {
        scope.launch {
            playbackMutex.withLock {
                val context = appContext ?: return@withLock
                val requestId = ++activePlayRequestId
                if (canPlayTimelinePrevious()) {
                    suppressTimelineRecord = true
                    try {
                        playbackTimelineIndex--
                        val song = playbackTimeline[playbackTimelineIndex]
                        val inQueue = queue.indexOfFirst { it.videoId == song.videoId }
                        if (inQueue >= 0) queueIndex = inQueue
                        publishPendingNowPlayingUi(
                            song,
                            isPlaying = _state.value.isPlaying,
                            isBuffering = false,
                        )
                        playPreparedLocked(context, song, requestId)
                    } finally {
                        suppressTimelineRecord = false
                    }
                    return@withLock
                }
                if (queue.isEmpty()) return@withLock
                val previousIndex = (queueIndex - 1).coerceAtLeast(0)
                if (previousIndex == queueIndex) return@withLock
                queueIndex = previousIndex
                val song = queue[queueIndex]
                publishPendingNowPlayingUi(
                    song,
                    isPlaying = _state.value.isPlaying,
                    isBuffering = false,
                )
                playPreparedLocked(context, song, requestId)
            }
        }
    }

    fun canPlayPrevious(): Boolean =
        canPlayTimelinePrevious() || (queue.isNotEmpty() && queueIndex > 0)

    fun setVolume(volume: Float) {
        userVolume = volume.coerceIn(0f, 1f)
        scope.launch {
            applyVolumeCrossfade()
            _state.update { it.copy(volume = userVolume) }
        }
    }

    fun setPlaybackAdjustments(speed: Float, pitch: Float) {
        scope.launch {
            player?.playbackParameters = PlaybackParameters(speed.coerceIn(0.5f, 2f), pitch.coerceIn(0.5f, 2f))
        }
    }

    fun toggleShuffle() {
        shuffleEnabled = !shuffleEnabled
        _state.update { it.copy(shuffleEnabled = shuffleEnabled) }
        persistPlaybackSnapshot()
    }

    fun cycleRepeatMode() {
        repeatMode = when (repeatMode) {
            RepeatMode.Off -> RepeatMode.All
            RepeatMode.All -> RepeatMode.One
            RepeatMode.One -> RepeatMode.Off
        }
        _state.update { it.copy(repeatMode = repeatMode) }
        persistPlaybackSnapshot()
    }

    fun addToQueue(song: Song) {
        if (!song.isMusicQueueTrack()) return
        queue = (queue + song).distinctBy { it.videoId }
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
        persistPlaybackSnapshot()
    }

    fun enqueuePlayNext(song: Song) {
        if (!song.isMusicQueueTrack()) return
        scope.launch {
            if (queue.isEmpty()) {
                val ctx = appContext ?: return@launch
                play(ctx, song)
                return@launch
            }
            val without = queue.filterNot { it.videoId == song.videoId }.toMutableList()
            val insertAt = (queueIndex + 1).coerceIn(0, without.size)
            without.add(insertAt, song)
            queue = without
            if (queueIndex >= queue.size) queueIndex = queue.lastIndex.coerceAtLeast(0)
            _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
            persistPlaybackSnapshot()
        }
    }

    fun removeFromQueue(song: Song) {
        val removedIndex = queue.indexOfFirst { it.videoId == song.videoId }
        queue = queue.filterNot { it.videoId == song.videoId }
        if (removedIndex != -1 && queueIndex > removedIndex) queueIndex -= 1
        queueIndex = if (queue.isEmpty()) -1 else queueIndex.coerceAtMost(queue.lastIndex)
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
        persistPlaybackSnapshot()
    }

    fun moveQueueItem(fromIndex: Int, toIndex: Int) {
        if (queue.size < 2) return
        if (fromIndex !in queue.indices) return
        val target = toIndex.coerceIn(0, queue.lastIndex)
        if (fromIndex == target) return
        val currentId = queue.getOrNull(queueIndex)?.videoId
        val mutable = queue.toMutableList()
        val moved = mutable.removeAt(fromIndex)
        mutable.add(target, moved)
        queue = mutable
        queueIndex = currentId
            ?.let { id -> queue.indexOfFirst { it.videoId == id } }
            ?.takeIf { it >= 0 }
            ?: queueIndex.coerceIn(0, queue.lastIndex)
        preloadedStream = null
        preloadedForQueueIndex = -1
        preloadJob?.cancel()
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
        persistPlaybackSnapshot()
        schedulePreloadNextTrack()
    }

    fun skipToQueueIndex(context: Context, index: Int) {
        scope.launch {
            if (queue.isEmpty()) return@launch
            queueIndex = index.coerceIn(0, queue.lastIndex)
            val song = queue[queueIndex]
            val requestId = ++activePlayRequestId
            publishPendingNowPlayingUi(
                song,
                isPlaying = _state.value.isPlaying,
                isBuffering = false,
            )
            playPrepared(context.applicationContext, song, requestId)
        }
    }

    fun startRadio(context: Context, seed: Song) {
        offlineQueueOnly = false
        val current = _state.value.currentSong
        if (current?.videoId == seed.videoId && queue.isNotEmpty()) {
            radioSession = YtmRadioSession.forSeed(seed.videoId)
            scope.launch {
                val (session, radio) = withContext(Dispatchers.IO) {
                    runCatching { YTMusicApi.fetchRadioPage(seed, radioSession) }
                        .getOrDefault(radioSession!! to emptyList())
                }
                radioSession = session
                val ordered = radio.distinctBy { it.videoId }.filter { it.isMusicQueueTrack() }
                queue = if (ordered.any { it.videoId == seed.videoId }) ordered else listOf(seed) + ordered
                queueIndex = session.queueStartIndex.coerceIn(0, queue.lastIndex.coerceAtLeast(0))
                _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
                if (!offlineQueueOnly) scheduleRadioExtendIfNeeded()
                schedulePreloadNextTrack()
            }
            return
        }
        playQueue(context, listOf(seed), startIndex = 0, radioTail = true)
    }

    fun scheduleSleepTimer(minutes: Int) {
        sleepJob?.cancel()
        stopAfterCurrentSong = false
        val end = System.currentTimeMillis() + minutes * 60_000L
        _sleepTimerState.value = SleepTimerUiState(SleepTimerMode.AfterMinutes, end)
        sleepJob = scope.launch {
            delay(minutes * 60_000L)
            _sleepTimerState.value = SleepTimerUiState()
            pause()
        }
    }

    fun sleepAfterCurrentSong() {
        sleepJob?.cancel()
        stopAfterCurrentSong = true
        _sleepTimerState.value = SleepTimerUiState(SleepTimerMode.AfterCurrentTrack, 0L)
    }

    fun cancelSleepTimer() {
        sleepJob?.cancel()
        sleepJob = null
        stopAfterCurrentSong = false
        _sleepTimerState.value = SleepTimerUiState()
    }

    fun release() {
        scope.launch {
            persistPlaybackSnapshot()
            stopProgressTicker()
            mediaSessionHolder?.release()
            mediaSessionHolder = null
            mediaSessionServiceStarted = false
            preloadJob?.cancel()
            preloadJob = null
            preloadedStream = null
            preloadedForQueueIndex = -1
            radioSession = null
            radioExtendJob?.cancel()
            crossfadeAdvanceJob?.cancel()
            player?.release()
            player = null
            exoPlayer = null
            stopMediaSessionService()
            _state.value = PlayerUiState()
            _sleepTimerState.value = SleepTimerUiState()
            sponsorRangesMs = emptyList()
            FoxyDynamicTheme.clearAccent()
        }
    }

    private fun syncMediaSession(context: Context) {
        val p = player ?: return
        if (mediaSessionHolder == null) {
            val sessionActivity = TaskStackBuilder.create(context.applicationContext)
                .addNextIntent(Intent(context.applicationContext, MainActivity::class.java))
                .getPendingIntent(
                    1,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
                ?: throw IllegalStateException("Failed to create session activity PendingIntent")
            mediaSessionHolder = MediaSession.Builder(context.applicationContext, p)
                .setSessionActivity(sessionActivity)
                .setPeriodicPositionUpdateEnabled(true)
                .build()
            startMediaSessionService(context.applicationContext)
            mediaSessionServiceStarted = true
        }
    }

    /**
     * True when the queue / repeat rules allow a "next" action for the media notification.
     * Single-item queues still get a Next control (restart from the top), matching common
     * music-app behaviour and satisfying Media3's COMMAND_SEEK_TO_NEXT* checks.
     */
    internal fun mediaNotificationHasNext(): Boolean {
        if (queue.isEmpty()) return false
        if (queue.size == 1) return true
        if (shuffleEnabled && queue.size > 1) return true
        if (queueIndex + 1 <= queue.lastIndex) return true
        return repeatMode == RepeatMode.All
    }

    internal fun mediaNotificationHasPrevious(): Boolean = queue.isNotEmpty()

    /** Advertise play/pause in MediaStyle whenever we have an active session / track. */
    internal fun mediaSessionWantsTransportControls(): Boolean =
        queue.isNotEmpty() || _state.value.currentSong != null

    internal fun playNextFromMediaSession() {
        playNext(loop = repeatMode == RepeatMode.All)
    }

    internal fun playPreviousFromMediaSession() {
        playPrevious()
    }

    private fun startMediaSessionService(context: Context) {
        val intent = Intent(context, FoxyMediaSessionService::class.java)
        // Media3 posts the media notification and promotes this service to foreground.
        // On API 26+, prefer startForegroundService so Android 12–14 reliably show the
        // media player in the shade when playback begins from the foreground activity.
        // If the system rejects FGS start, fall back to startService (legacy path).
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                @Suppress("DEPRECATION")
                context.startService(intent)
            }
        } catch (e: IllegalStateException) {
            Log.w("MusicPlayer", "startForegroundService rejected; trying startService", e)
            context.startService(intent)
        }
    }

    private fun stopMediaSessionService() {
        val ctx = appContext ?: return
        runCatching { ctx.stopService(Intent(ctx, FoxyMediaSessionService::class.java)) }
    }
}

private fun Song.streamSearchQuery(): String =
    listOf(title, artist)
        .map { it.trim() }
        .filter { it.isNotBlank() && it != videoId }
        .distinct()
        .joinToString(" ")
        .ifBlank { videoId }

private fun buildStreamHeaders(): Map<String, String> = buildFoxyStreamHeaders()

private object MimeTypeHint {
    fun fromUrl(url: String): String? {
        if (url.startsWith("file:", ignoreCase = true)) {
            val path = runCatching { Uri.parse(url).path }.getOrNull().orEmpty()
            if (path.isBlank()) return null
            return when (path.substringAfterLast('.', "").lowercase()) {
                "webm" -> MimeTypes.AUDIO_WEBM
                "mp4", "m4a" -> MimeTypes.AUDIO_MP4
                "opus" -> "audio/opus"
                "mp3", "mpeg" -> MimeTypes.AUDIO_MPEG
                "aac" -> MimeTypes.AUDIO_AAC
                "ogg" -> MimeTypes.AUDIO_OGG
                "flac" -> MimeTypes.AUDIO_FLAC
                "wav" -> MimeTypes.AUDIO_WAV
                else -> null
            }
        }
        return when {
            url.contains(".m3u8", ignoreCase = true) -> MimeTypes.APPLICATION_M3U8
            url.contains(".webm", ignoreCase = true) -> MimeTypes.AUDIO_WEBM
            url.contains(".mp4", ignoreCase = true) -> MimeTypes.AUDIO_MP4
            url.contains(".m4a", ignoreCase = true) -> MimeTypes.AUDIO_MP4
            url.contains(".opus", ignoreCase = true) -> "audio/opus"

            // Query-string based MIME hints returned by some extractors.
            url.contains("mime=audio%2Fwebm", ignoreCase = true) || url.contains("mime=audio/webm", ignoreCase = true) -> MimeTypes.AUDIO_WEBM
            url.contains("mime=audio%2Fmp4", ignoreCase = true) || url.contains("mime=audio/mp4", ignoreCase = true) -> MimeTypes.AUDIO_MP4
            else -> null
        }
    }
}
