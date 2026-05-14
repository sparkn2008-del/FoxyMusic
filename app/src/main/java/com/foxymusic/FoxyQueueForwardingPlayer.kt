package com.foxymusic

import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi

private const val PREVIOUS_RESTART_THRESHOLD_MS = 3_000L

/**
 * Exposes in-app queue navigation to the system media session / notification while the
 * underlying [androidx.media3.exoplayer.ExoPlayer] only holds the current stream as a single item.
 */
@UnstableApi
class FoxyQueueForwardingPlayer(delegate: Player) : ForwardingPlayer(delegate) {

    override fun getAvailableCommands(): Player.Commands {
        val base = super.getAvailableCommands()
        val builder = Player.Commands.Builder().addAll(base)
        if (MusicPlayer.mediaNotificationHasNext()) {
            builder.add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
            builder.add(Player.COMMAND_SEEK_TO_NEXT)
        }
        if (MusicPlayer.mediaNotificationHasPrevious()) {
            builder.add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
            builder.add(Player.COMMAND_SEEK_TO_PREVIOUS)
        }
        return builder.build()
    }

    override fun isCommandAvailable(command: Int): Boolean =
        when (command) {
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_NEXT ->
                MusicPlayer.mediaNotificationHasNext() || super.isCommandAvailable(command)
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_PREVIOUS ->
                MusicPlayer.mediaNotificationHasPrevious() || super.isCommandAvailable(command)
            else -> super.isCommandAvailable(command)
        }

    override fun seekToNextMediaItem() {
        if (MusicPlayer.mediaNotificationHasNext()) {
            MusicPlayer.playNextFromMediaSession()
        } else {
            super.seekToNextMediaItem()
        }
    }

    override fun seekToNext() {
        if (MusicPlayer.mediaNotificationHasNext()) {
            MusicPlayer.playNextFromMediaSession()
        } else {
            super.seekToNext()
        }
    }

    override fun seekToPreviousMediaItem() {
        handleSeekToPrevious()
    }

    override fun seekToPrevious() {
        handleSeekToPrevious()
    }

    private fun handleSeekToPrevious() {
        if (!MusicPlayer.mediaNotificationHasPrevious()) {
            super.seekToPrevious()
            return
        }
        val pos = currentPosition.coerceAtLeast(0L)
        val duration = duration
        val hasDuration = duration != C.TIME_UNSET && duration > 0L
        if (pos > PREVIOUS_RESTART_THRESHOLD_MS) {
            seekTo(0L)
            return
        }
        if (hasDuration && pos > duration - 500L) {
            seekTo(0L)
            return
        }
        MusicPlayer.playPreviousFromMediaSession()
    }
}
