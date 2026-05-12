package com.foxymusic

import android.content.Context
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlin.random.Random

data class PlayerUiState(
    val currentSong: Song? = null,
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val durationMs: Long = 0L,
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
    private var stopAfterCurrentSong = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state

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
            queue = queue,
            queueIndex = queueIndex,
            shuffleEnabled = shuffleEnabled,
            repeatMode = repeatMode
        )
        runCatching { PlaybackService.start(context.applicationContext) }
            .onFailure { Log.w("FoxyMusic", "Playback service could not start yet", it) }

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
                                if (stopAfterCurrentSong) {
                                    stopAfterCurrentSong = false
                                    pause()
                                    return
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
                    }
                })
            }

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
            runCatching { PlaybackService.updateNowPlaying(context.applicationContext) }
                .onFailure { Log.w("FoxyMusic", "Playback notification update failed", it) }

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
        scope.launch { player?.seekTo(positionMs.coerceAtLeast(0L)) }
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
        scope.launch { player?.volume = volume.coerceIn(0f, 1f) }
    }

    fun setPlaybackAdjustments(speed: Float, pitch: Float) {
        scope.launch {
            player?.playbackParameters = PlaybackParameters(speed.coerceIn(0.5f, 2f), pitch.coerceIn(0.5f, 2f))
        }
    }

    fun toggleShuffle() {
        shuffleEnabled = !shuffleEnabled
        _state.update { it.copy(shuffleEnabled = shuffleEnabled) }
    }

    fun cycleRepeatMode() {
        repeatMode = when (repeatMode) {
            RepeatMode.Off -> RepeatMode.All
            RepeatMode.All -> RepeatMode.One
            RepeatMode.One -> RepeatMode.Off
        }
        _state.update { it.copy(repeatMode = repeatMode) }
    }

    fun addToQueue(song: Song) {
        queue = (queue + song).distinctBy { it.videoId }
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
    }

    fun removeFromQueue(song: Song) {
        val removedIndex = queue.indexOfFirst { it.videoId == song.videoId }
        queue = queue.filterNot { it.videoId == song.videoId }
        if (removedIndex != -1 && queueIndex > removedIndex) queueIndex -= 1
        queueIndex = queueIndex.coerceAtMost(queue.lastIndex)
        _state.update { it.copy(queue = queue, queueIndex = queueIndex) }
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
        sleepJob = scope.launch {
            delay(minutes * 60_000L)
            pause()
        }
    }

    fun sleepAfterCurrentSong() {
        sleepJob?.cancel()
        stopAfterCurrentSong = true
    }

    fun cancelSleepTimer() {
        sleepJob?.cancel()
        sleepJob = null
        stopAfterCurrentSong = false
    }

    fun release() {
        scope.launch {
            player?.release()
            player = null
            _state.value = PlayerUiState()
            Log.d("FoxyMusic", "Player released")
        }
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
