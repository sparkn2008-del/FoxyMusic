package com.foxymusic

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.TaskStackBuilder
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.datasource.DefaultHttpDataSource
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
import kotlin.random.Random
import java.io.File

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
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state
    private val _sleepTimerState = MutableStateFlow(SleepTimerUiState())
    val sleepTimerState: StateFlow<SleepTimerUiState> = _sleepTimerState

    /** Load persisted queue metadata (no automatic playback until the user presses play). */
    fun init(context: Context) {
        appContext = context.applicationContext
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
                delay(320)
            }
        }
    }

    private fun applyVolumeCrossfade() {
        val p = player ?: return
        val cross = FoxySettings.state.value.crossfadeMs
        if (cross <= 0) {
            p.volume = userVolume
            return
        }
        val rawDur = p.duration
        val dur = if (rawDur != C.TIME_UNSET && rawDur > 0L) rawDur else _state.value.durationMs.takeIf { it > 0L } ?: run {
            p.volume = userVolume
            return
        }
        val pos = p.currentPosition.coerceAtLeast(0L)
        val c = cross.toLong()
        val rem = (dur - pos).coerceAtLeast(0L)
        val fadeOut = if (rem < c) (rem.toFloat() / c.toFloat()).coerceIn(0f, 1f) else 1f
        val fadeIn = if (pos < c) (pos.toFloat() / c.toFloat()).coerceIn(0f, 1f) else 1f
        p.volume = userVolume * minOf(fadeOut, fadeIn)
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

    fun playQueue(context: Context, songs: List<Song>, startIndex: Int = 0) {
        if (songs.isEmpty()) return
        scope.launch {
            queue = songs.distinctBy { it.videoId }
            queueIndex = startIndex.coerceIn(0, queue.lastIndex)
            playPrepared(context.applicationContext, queue[queueIndex])
        }
    }

    fun play(context: Context, song: Song) {
        scope.launch {
            if (queue.none { it.videoId == song.videoId }) {
                queue = listOf(song)
                queueIndex = 0
            }
            playPrepared(context.applicationContext, song)
        }
    }

    fun play(context: Context, url: String, song: Song) {
        scope.launch {
            playResolved(context.applicationContext, url, song)
        }
    }

    private suspend fun playPrepared(context: Context, song: Song) {
        appContext = context.applicationContext
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

        // Offline: if we have a local file, play it directly (no stream extraction).
        val localPath = song.localPath
        if (song.isDownloaded && !localPath.isNullOrBlank()) {
            val f = File(localPath)
            if (f.exists() && f.length() > 0L) {
                val localUri = "file://${f.absolutePath}"
                playResolved(context, localUri, song)
                return
            }
        }

        val result = withContext(Dispatchers.IO) {
            StreamExtractor.getStreamResult(song.videoId)
        }
        result.url?.let { playResolved(context, it, song) } ?: _state.update {
            it.copy(isBuffering = false, isPlaying = false, error = result.error ?: "Playback failed")
        }
    }

    private fun playResolved(context: Context, url: String, song: Song) {
        appContext = context.applicationContext
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
        try {
            if (player == null) {
                val okHttp = FoxyNetworking.streamingClient()

                val upstreamFactory = OkHttpDataSource.Factory(okHttp)
                    .setUserAgent(StreamExtractor.STREAM_USER_AGENT)
                    .setDefaultRequestProperties(buildStreamHeaders())

                val cacheFactory = CacheDataSource.Factory()
                    .setCache(FoxyCache.get(context.applicationContext))
                    .setUpstreamDataSourceFactory(upstreamFactory)
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
                                // Never call prepare/stop/playNext synchronously from Player.Listener — ExoPlayer can crash.
                                scope.launch {
                                    delay(40)
                                    if (appContext == null) return@launch
                                    if (stopAfterCurrentSong) {
                                        stopAfterCurrentSong = false
                                        _sleepTimerState.value = SleepTimerUiState()
                                        pause()
                                        return@launch
                                    }
                                    when (repeatMode) {
                                        RepeatMode.One -> {
                                            player?.seekTo(0)
                                            player?.playWhenReady = true
                                        }
                                        RepeatMode.All -> playNext(loop = true)
                                        RepeatMode.Off -> playNext()
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
                })
            }

            syncMediaSession(context.applicationContext)

            player?.stop()
            player?.clearMediaItems()
            val metadata = MediaMetadata.Builder()
                .setTitle(song.title)
                .setDisplayTitle(song.title)
                .setArtist(song.artist)
                .apply {
                    song.album?.takeIf { it.isNotBlank() }?.let { setAlbumTitle(it) }
                }
                .setArtworkUri(song.highQualityArtworkUrl().takeIf { it.isNotBlank() }?.let(android.net.Uri::parse))
                .build()
            val mediaItem = MediaItem.Builder()
                .setUri(url)
                .setMediaId(song.videoId)
                .setMediaMetadata(metadata)
                .setMimeType(MimeTypeHint.fromUrl(url))
                .build()
            player?.setMediaItem(mediaItem)
            player?.prepare()
            player?.playWhenReady = true
            loadSponsorSegments(song.videoId)
            applyVolumeCrossfade()
            startProgressTicker()
            persistPlaybackSnapshot()

        } catch (e: Exception) {
            Log.e("FoxyMusic", "Exception in play(): ${e.message}")
            _state.update {
                it.copy(isPlaying = false, isBuffering = false, error = e.message ?: "Playback failed")
            }
        }
    }

    fun togglePlayPause() {
        scope.launch {
            player?.let {
                if (it.isPlaying) {
                    it.pause()
                    Log.d("FoxyMusic", "Paused")
                } else {
                    it.play()
                    Log.d("FoxyMusic", "Resumed")
                }
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
            val context = appContext ?: return@launch
            if (queue.isEmpty()) return@launch
            val nextIndex = when {
                shuffleEnabled && queue.size > 1 -> {
                    generateSequence { Random.nextInt(queue.size) }
                        .first { it != queueIndex }
                }
                queueIndex + 1 <= queue.lastIndex -> queueIndex + 1
                loop -> 0
                else -> return@launch
            }
            queueIndex = nextIndex
            playPrepared(context, queue[queueIndex])
        }
    }

    fun playPrevious() {
        scope.launch {
            val context = appContext ?: return@launch
            if (queue.isEmpty()) return@launch
            val previousIndex = (queueIndex - 1).coerceAtLeast(0)
            queueIndex = previousIndex
            playPrepared(context, queue[queueIndex])
        }
    }

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
        }
        startMediaSessionService(context.applicationContext)
    }

    internal fun mediaNotificationHasNext(): Boolean {
        if (queue.isEmpty()) return false
        if (shuffleEnabled && queue.size > 1) return true
        if (queueIndex + 1 <= queue.lastIndex) return true
        return false
    }

    internal fun mediaNotificationHasPrevious(): Boolean = queue.isNotEmpty()

    internal fun playNextFromMediaSession() {
        playNext(loop = false)
    }

    internal fun playPreviousFromMediaSession() {
        playPrevious()
    }

    private fun startMediaSessionService(context: Context) {
        val intent = Intent(context, FoxyMediaSessionService::class.java)
        // Media3 owns foreground promotion for the media notification. Starting this
        // as a foreground service ourselves can crash on OEM ROMs if the notification
        // update is delayed: "Context.startForegroundService() did not then call
        // Service.startForeground()". A regular start keeps the session alive while
        // Media3 publishes transport controls.
        context.startService(intent)
    }

    private fun stopMediaSessionService() {
        val ctx = appContext ?: return
        runCatching { ctx.stopService(Intent(ctx, FoxyMediaSessionService::class.java)) }
    }
}

private fun buildStreamHeaders(): Map<String, String> = buildFoxyStreamHeaders()

private object MimeTypeHint {
    fun fromUrl(url: String): String? {
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
