package com.foxymusic

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.TaskStackBuilder
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
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
import kotlin.random.Random

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
    val repeatMode: RepeatMode = RepeatMode.Off
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
    /** Chronological play order for back (previous track), SimpMusic-style. */
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
        val downloadsDir = File(context.getExternalFilesDir(null), "downloads")
        val localById = downloadsDir.listFiles()
            ?.associateBy({ it.nameWithoutExtension }, { it })
            .orEmpty()

        queue = session.queue.map { song ->
            val localFile = localById[song.videoId]
            if (localFile != null && localFile.length() > 0L) {
                song.copy(
                    localPath = localFile.absolutePath,
                    isDownloaded = true,
                    streamUrl = null
                )
            } else {
                song
            }
        }
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
                val buffered =
                    if (dur > 0L) {
                        (p.bufferedPosition.toFloat() / dur.toFloat()).coerceIn(0f, 1f)
                    } else {
                        0f
                    }
                _state.update {
                    it.copy(
                        positionMs = pos,
                        durationMs = dur.takeIf { d -> d > 0L } ?: it.durationMs,
                        bufferedFraction = buffered
                    )
                }
                applyVolumeCrossfade()
                maybeSkipSponsor(pos)
                delay(480)
            }
        }
    }

    /** SimpMusic-style target level when normalization is enabled (reduces hot masters). */
    private fun effectiveUserVolume(): Float {
        var level = userVolume
        if (FoxySettings.state.value.normalizeVolume) {
            level *= 0.78f
        }
        return level.coerceIn(0f, 1f)
    }

    private fun applyVolumeCrossfade() {
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
        val fadeIn = if (pos < c) (pos.toFloat() / c.toFloat()).coerceIn(0f, 1f) else 1f
        p.volume = base * minOf(fadeOut, fadeIn)
    }

    /** Re-apply crossfade / normalization after settings change while playing. */
    fun refreshPlaybackAudioSettings() {
        scope.launch { applyVolumeCrossfade() }
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
                Log.d("FoxyMusic", "SponsorBlock: skipped to ${target}ms")
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

    fun playQueue(context: Context, songs: List<Song>, startIndex: Int = 0, radioTail: Boolean = false) {
        if (songs.isEmpty()) return
        appContext = context.applicationContext
        val ctx = context.applicationContext
        if (radioTail) {
            val idx = startIndex.coerceIn(0, songs.lastIndex)
            val seed = songs[idx]
            queue = listOf(seed)
            queueIndex = 0
            publishInstantPlaybackUi(seed)
            scope.launch {
                val radio = withContext(Dispatchers.IO) {
                    runCatching { YTMusicApi.radio(seed) }.getOrDefault(emptyList())
                }
                queue = (listOf(seed) + radio).distinctBy { it.videoId }
                queueIndex = 0
                _state.update {
                    it.copy(queue = queue, queueIndex = queueIndex)
                }
                playPrepared(ctx, seed)
            }
        } else {
            queue = songs.distinctBy { it.videoId }
            queueIndex = startIndex.coerceIn(0, queue.lastIndex)
            publishInstantPlaybackUi(queue[queueIndex])
            scope.launch {
                playPrepared(ctx, queue[queueIndex])
            }
        }
    }

    fun play(context: Context, song: Song) {
        appContext = context.applicationContext
        if (queue.none { it.videoId == song.videoId }) {
            queue = listOf(song)
            queueIndex = 0
        } else {
            queueIndex = queue.indexOfFirst { it.videoId == song.videoId }
        }
        publishInstantPlaybackUi(song)
        scope.launch {
            playPrepared(context.applicationContext, song)
        }
    }

    fun play(context: Context, url: String, song: Song) {
        scope.launch {
            playResolved(context.applicationContext, url, song)
        }
    }

    private fun resolveOfflineMediaFile(context: Context, song: Song): File? {
        song.localPath?.trim()?.takeIf { it.isNotBlank() }?.let { path ->
            File(path).takeIf { it.isFile && it.length() > 0L }?.let { return it }
        }
        val vid = song.videoId.trim()
        if (vid.isBlank()) return null
        val dir = File(context.getExternalFilesDir(null), "downloads")
        if (!dir.isDirectory) return null
        val exts = setOf(
            "webm", "mp4", "m4a", "opus", "mp3", "media", "mkv", "aac", "ogg",
        )
        return dir.listFiles()?.firstOrNull { f ->
            f.isFile &&
                f.nameWithoutExtension == vid &&
                f.extension.lowercase() in exts &&
                f.length() > 0L
        }
    }

    private suspend fun playPrepared(context: Context, song: Song) {
        playbackMutex.withLock {
            playPreparedLocked(context, song)
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

    private suspend fun playPreparedLocked(context: Context, song: Song) {
        appContext = context.applicationContext
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
            val enriched = offlineBase.copy(isDownloaded = true)
            playResolved(context, url, enriched)
            scope.launch { maybeExtendQueueForAutoplay() }
            return
        }

        val cached = preloadedStream
        if (cached != null && cached.first == song.videoId && !cached.second.isNullOrBlank()) {
            preloadedStream = null
            playResolved(context, cached.second, song)
            return
        }

        val result = withContext(Dispatchers.IO) {
            StreamExtractor.getStreamResult(song.videoId)
        }
        result.url?.let {
            playResolved(context, it, song)
            scope.launch { maybeExtendQueueForAutoplay() }
        } ?: _state.update {
            it.copy(isBuffering = false, isPlaying = false, error = result.error ?: "Playback failed")
        }
    }

    /**
     * Metrolist-style “infinite” queue: when near the end, append [YTMusicApi.radio] suggestions
     * inferred from the current track (phonk, bollywood, artist mix, etc.).
     */
    private suspend fun maybeExtendQueueForAutoplay(): Boolean {
        if (queue.isEmpty() || shuffleEnabled) return false
        val remaining = queue.lastIndex - queueIndex
        if (queue.size > 1 && remaining > 2) return false
        val seed = _state.value.currentSong ?: queue.getOrNull(queueIndex) ?: return false
        val more = withContext(Dispatchers.IO) {
            runCatching { YTMusicApi.radio(seed) }.getOrDefault(emptyList())
        }
        if (more.isEmpty()) return false
        val merged = (queue + more).distinctBy { it.videoId }
        if (merged.size <= queue.size) return false
        queue = merged
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
        schedulePreloadNextTrack()
        Log.d("FoxyMusic", "Autoplay extended queue to ${queue.size} tracks")
        return true
    }

    private fun peekNextQueueSong(): Song? {
        if (queue.isEmpty() || shuffleEnabled || queue.size <= 1) return null
        val nextIndex = when {
            queueIndex + 1 <= queue.lastIndex -> queueIndex + 1
            repeatMode == RepeatMode.All -> 0
            else -> return null
        }
        return queue.getOrNull(nextIndex)
    }

    private fun schedulePreloadNextTrack() {
        preloadJob?.cancel()
        val ctx = appContext ?: return
        val next = peekNextQueueSong() ?: run {
            preloadedStream = null
            return
        }
        val vid = next.videoId
        if (preloadedStream?.first == vid) return
        preloadJob = scope.launch(Dispatchers.IO) {
            resolveOfflineMediaFile(ctx, next)?.let { file ->
                if (peekNextQueueSong()?.videoId == vid) {
                    preloadedStream = vid to Uri.fromFile(file).toString()
                }
                return@launch
            }
            val url = StreamExtractor.getStreamResult(vid).url
            if (url != null && peekNextQueueSong()?.videoId == vid) {
                preloadedStream = vid to url
            }
        }
    }

    private fun playResolved(context: Context, url: String, song: Song) {
        appContext = context.applicationContext
        FoxyDynamicTheme.bindContext(context.applicationContext)
        Log.d("FoxyMusic", "Attempting to play: ${song.title}")
        Log.d("FoxyMusic", "Stream URL: $url")
        Log.d("FoxyMusic", "Artwork candidates: ${song.artworkCandidates().joinToString()}")
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
            repeatMode = repeatMode
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
                    .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

                val exo = ExoPlayer.Builder(context.applicationContext)
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
                player = FoxyQueueForwardingPlayer(exo)

                player?.addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        _state.update {
                            it.copy(
                                isBuffering = state == Player.STATE_BUFFERING,
                                durationMs = player?.duration?.takeIf { duration ->
                                    duration != C.TIME_UNSET && duration > 0
                                } ?: it.durationMs
                            )
                        }
                        when (state) {
                            Player.STATE_BUFFERING -> Log.d("FoxyMusic", "Buffering...")
                            Player.STATE_READY -> {
                                Log.d("FoxyMusic", "Ready to play!")
                                publishDurationFromPlayer()
                            }
                            Player.STATE_ENDED -> {
                                Log.d("FoxyMusic", "Playback ended")
                                if (suppressEndAdvance) {
                                    Log.d("FoxyMusic", "Ignoring ENDED during track swap")
                                    return
                                }
                                // Never call prepare/stop/playNext synchronously from Player.Listener — ExoPlayer can crash.
                                scope.launch {
                                    delay(40)
                                    if (appContext == null || suppressEndAdvance) return@launch
                                    playbackMutex.withLock {
                                        if (suppressEndAdvance) return@withLock
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
                            Player.STATE_IDLE -> Log.d("FoxyMusic", "Player idle")
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
                            scope.launch {
                                val ctx = appContext ?: return@launch
                                try {
                                    val result = withContext(Dispatchers.IO) {
                                        StreamExtractor.getStreamResult(current.videoId)
                                    }
                                    val url = result.url
                                    if (url != null) {
                                        playResolved(ctx, url, current)
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
                            _state.update {
                                it.copy(
                                    isPlaying = false,
                                    isBuffering = false,
                                    error = error.message ?: "Playback failed"
                                )
                            }
                        }
                    }
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        Log.d("FoxyMusic", "Is playing: $isPlaying")
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
                    }

                    override fun onEvents(player: Player, events: Player.Events) {
                        if (events.contains(Player.EVENT_TIMELINE_CHANGED) ||
                            events.contains(Player.EVENT_TRACKS_CHANGED) ||
                            events.contains(Player.EVENT_IS_LOADING_CHANGED)
                        ) {
                            publishDurationFromPlayer()
                            _state.update {
                                it.copy(
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

            val metadata = MediaMetadata.Builder()
                .setTitle(song.title)
                .setDisplayTitle(song.title)
                .setArtist(song.artist)
                .apply {
                    song.album?.takeIf { it.isNotBlank() }?.let { setAlbumTitle(it) }
                }
                .setArtworkUri(song.highQualityArtworkUrl().takeIf { it.isNotBlank() }?.let(android.net.Uri::parse))
                .build()
            val itemBuilder = MediaItem.Builder()
                .setUri(Uri.parse(url))
                .setMediaId(song.videoId)
                .setMediaMetadata(metadata)
            MimeTypeHint.fromUrl(url)?.let { itemBuilder.setMimeType(it) }
            val mediaItem = itemBuilder.build()
            val exo = player ?: throw IllegalStateException("Player not initialized")
            exo.setMediaItem(mediaItem, /* resetPosition= */ true)
            exo.prepare()
            exo.playWhenReady = true
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
                Log.d("FoxyMusic", "Reloading unloaded player for ${song.title}")
                playPrepared(ctx, song)
                return@launch
            }
            if (exo.isPlaying) {
                exo.pause()
                Log.d("FoxyMusic", "Paused")
            } else {
                exo.play()
                Log.d("FoxyMusic", "Resumed")
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
        val nextIndex = when {
            shuffleEnabled && queue.size > 1 -> {
                generateSequence { Random.nextInt(queue.size) }
                    .first { it != queueIndex }
            }
            queueIndex + 1 <= queue.lastIndex -> queueIndex + 1
            loop -> 0
            else -> {
                if (!maybeExtendQueueForAutoplay()) return
                if (queueIndex + 1 > queue.lastIndex) return
                queueIndex + 1
            }
        }
        queueIndex = nextIndex
        playPreparedLocked(context, queue[queueIndex])
    }

    fun playPrevious() {
        scope.launch {
            playbackMutex.withLock {
                val context = appContext ?: return@withLock
                if (canPlayTimelinePrevious()) {
                    suppressTimelineRecord = true
                    try {
                        playbackTimelineIndex--
                        val song = playbackTimeline[playbackTimelineIndex]
                        val inQueue = queue.indexOfFirst { it.videoId == song.videoId }
                        if (inQueue >= 0) queueIndex = inQueue
                        playPreparedLocked(context, song)
                    } finally {
                        suppressTimelineRecord = false
                    }
                    return@withLock
                }
                if (queue.isEmpty()) return@withLock
                val previousIndex = (queueIndex - 1).coerceAtLeast(0)
                if (previousIndex == queueIndex) return@withLock
                queueIndex = previousIndex
                playPreparedLocked(context, queue[queueIndex])
            }
        }
    }

    fun canPlayPrevious(): Boolean =
        canPlayTimelinePrevious() || (queue.isNotEmpty() && queueIndex > 0)

    fun setVolume(volume: Float) {
        userVolume = volume.coerceIn(0f, 1f)
        scope.launch {
            applyVolumeCrossfade()
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
        queue = (queue + song).distinctBy { it.videoId }
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
        persistPlaybackSnapshot()
    }

    fun enqueuePlayNext(song: Song) {
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

    fun skipToQueueIndex(context: Context, index: Int) {
        scope.launch {
            if (queue.isEmpty()) return@launch
            queueIndex = index.coerceIn(0, queue.lastIndex)
            playPrepared(context.applicationContext, queue[queueIndex])
        }
    }

    fun startRadio(context: Context, seed: Song) {
        scope.launch {
            val radio = withContext(Dispatchers.IO) {
                runCatching { YTMusicApi.radio(seed) }.getOrDefault(emptyList())
            }
            playQueue(context.applicationContext, (listOf(seed) + radio).distinctBy { it.videoId }, 0)
        }
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
            player?.release()
            player = null
            stopMediaSessionService()
            _state.value = PlayerUiState()
            _sleepTimerState.value = SleepTimerUiState()
            sponsorRangesMs = emptyList()
            FoxyDynamicTheme.clearAccent()
            Log.d("FoxyMusic", "Player released")
        }
    }

    @OptIn(UnstableApi::class)
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
