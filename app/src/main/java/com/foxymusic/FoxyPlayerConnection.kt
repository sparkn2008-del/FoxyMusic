package com.foxymusic

import android.content.Context
import kotlinx.coroutines.flow.StateFlow

/**
 * UI-facing contract for controlling/observing playback.
 *
 * The goal is to keep screens/components from talking directly to the `MusicPlayer`
 * singleton. Later we can back this connection with a real service binder if needed.
 */
object FoxyPlayerConnection {

    val state: StateFlow<PlayerUiState> = MusicPlayer.state
    val sleepTimerState: StateFlow<SleepTimerUiState> = MusicPlayer.sleepTimerState

    fun init(context: Context) = MusicPlayer.init(context)

    fun playQueue(
        context: Context,
        songs: List<Song>,
        startIndex: Int = 0,
        radioTail: Boolean = false,
        offlineQueueOnly: Boolean = false,
    ) = MusicPlayer.playQueue(context, songs, startIndex, radioTail, offlineQueueOnly)

    fun playWithRadio(context: Context, seed: Song) =
        FoxyPlayback.playWithRadio(context, seed)

    fun playDiscoveryQueue(context: Context, songs: List<Song>, startIndex: Int = 0) =
        FoxyPlayback.playQueue(context, songs, startIndex)

    fun play(context: Context, song: Song) = MusicPlayer.play(context, song)
    fun play(context: Context, url: String, song: Song) = MusicPlayer.play(context, url, song)

    fun togglePlayPause() = MusicPlayer.togglePlayPause()
    fun pause() = MusicPlayer.pause()
    fun seekTo(positionMs: Long) = MusicPlayer.seekTo(positionMs)

    fun playNext(loop: Boolean = false) = MusicPlayer.playNext(loop)
    fun playPrevious() = MusicPlayer.playPrevious()

    fun toggleShuffle() = MusicPlayer.toggleShuffle()
    fun cycleRepeatMode() = MusicPlayer.cycleRepeatMode()

    fun addToQueue(song: Song) = MusicPlayer.addToQueue(song)
    fun enqueuePlayNext(song: Song) = MusicPlayer.enqueuePlayNext(song)
    fun removeFromQueue(song: Song) = MusicPlayer.removeFromQueue(song)
    fun moveQueueItem(fromIndex: Int, toIndex: Int) =
        MusicPlayer.moveQueueItem(fromIndex, toIndex)

    fun skipToQueueIndex(context: Context, index: Int) =
        MusicPlayer.skipToQueueIndex(context, index)

    fun startRadio(context: Context, seed: Song) = MusicPlayer.startRadio(context, seed)

    fun setVolume(volume: Float) = MusicPlayer.setVolume(volume)
    fun setPlaybackAdjustments(speed: Float, pitch: Float) = MusicPlayer.setPlaybackAdjustments(speed, pitch)
    fun refreshPlaybackAudioSettings() = MusicPlayer.refreshPlaybackAudioSettings()

    fun scheduleSleepTimer(minutes: Int) = MusicPlayer.scheduleSleepTimer(minutes)
    fun sleepAfterCurrentSong() = MusicPlayer.sleepAfterCurrentSong()
    fun cancelSleepTimer() = MusicPlayer.cancelSleepTimer()

    fun release() = MusicPlayer.release()
}

