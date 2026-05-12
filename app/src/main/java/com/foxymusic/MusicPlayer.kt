package com.foxymusic

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.datasource.DefaultHttpDataSource
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

    private var player: ExoPlayer? = null
    private var appContext: Context? = null
    private var queue: List<Song> = emptyList()
    private var queueIndex: Int = -1
    private var shuffleEnabled = false
    private var repeatMode = RepeatMode.Off
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
        queue = session.queue
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
                val dur = if (durRaw > 0L) durRaw else _state.value.durationMs
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
        val dur = p.duration.takeIf { it > 0L } ?: _state.value.durationMs.takeIf { it > 0L } ?: run {
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
        val dur = p.duration.takeIf { it > 0L } ?: _state.value.durationMs
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
            _state.value = _state.value.copy(
                currentSong = song,
                isBuffering = true,
                isPlaying = false,
                error = null,
                positionMs = 0L,
                bufferedFraction = 0f,
                queue = queue,
                queueIndex = queueIndex,
                shuffleEnabled = shuffleEnabled,
                repeatMode = repeatMode
            )
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
            positionMs = 0L,
            bufferedFraction = 0f,
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode
        )
        try {
            if (player == null) {
                val httpFactory = DefaultHttpDataSource.Factory()
                    .setUserAgent(StreamExtractor.STREAM_USER_AGENT)
                    .setDefaultRequestProperties(buildStreamHeaders())
                    .setAllowCrossProtocolRedirects(true)

                player = ExoPlayer.Builder(context.applicationContext)
                    .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
                    .build()

                player?.addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        _state.update {
                            it.copy(
                                isBuffering = state == Player.STATE_BUFFERING,
                                durationMs = player?.duration?.takeIf { duration -> duration > 0 } ?: it.durationMs
                            )
                        }
                        when (state) {
                            Player.STATE_BUFFERING -> Log.d("FoxyMusic", "Buffering...")
                            Player.STATE_READY -> Log.d("FoxyMusic", "Ready to play!")
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
                        _state.update {
                            it.copy(
                                isPlaying = false,
                                isBuffering = false,
                                error = error.message ?: "Playback failed"
                            )
                        }
                    }
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        Log.d("FoxyMusic", "Is playing: $isPlaying")
                        _state.update {
                            it.copy(isPlaying = isPlaying, isBuffering = false, error = null)
                        }
                        persistPlaybackSnapshot()
                    }
                })
            }

            syncMediaSession(context.applicationContext)

            player?.stop()
            player?.clearMediaItems()
            val metadata = MediaMetadata.Builder()
                .setTitle(song.title)
                .setArtist(song.artist)
                .setArtworkUri(song.bestArtworkUrl().takeIf { it.isNotBlank() }?.let(android.net.Uri::parse))
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

    fun duration(): Long = player?.duration?.takeIf { it > 0 } ?: state.value.durationMs

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
            Log.d("FoxyMusic", "Player released")
        }
    }

    private fun syncMediaSession(context: Context) {
        val p = player ?: return
        if (mediaSessionHolder == null) {
            mediaSessionHolder = MediaSession.Builder(context.applicationContext, p).build()
        }
        startMediaSessionService(context.applicationContext)
    }

    private fun startMediaSessionService(context: Context) {
        val intent = Intent(context, FoxyMediaSessionService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun stopMediaSessionService() {
        val ctx = appContext ?: return
        runCatching { ctx.stopService(Intent(ctx, FoxyMediaSessionService::class.java)) }
    }
}

private fun buildStreamHeaders(): Map<String, String> {
    val headers = mutableMapOf(
        "Origin" to "https://music.youtube.com",
        "Referer" to "https://music.youtube.com/"
    )
    val account = FoxyAccount.state.value
    if (account.cookie.isNotBlank()) {
        headers["Cookie"] = account.cookie
        account.cookie.sapisidHashHeader()?.let { headers["Authorization"] = it }
    }
    return headers
}

private object MimeTypeHint {
    fun fromUrl(url: String): String? {
        return when {
            url.contains(".m3u8", ignoreCase = true) -> MimeTypes.APPLICATION_M3U8
            url.contains("mime=audio%2Fwebm") || url.contains("mime=audio/webm") -> MimeTypes.AUDIO_WEBM
            url.contains("mime=audio%2Fmp4") || url.contains("mime=audio/mp4") -> MimeTypes.AUDIO_MP4
            else -> null
        }
    }
}
