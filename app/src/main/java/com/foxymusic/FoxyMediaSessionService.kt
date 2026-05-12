package com.foxymusic

import android.content.Intent
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Media3 session service — media notification and lock-screen controls wired to ExoPlayer in [MusicPlayer].
 */
class FoxyMediaSessionService : MediaSessionService() {

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return MusicPlayer.mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val session = MusicPlayer.mediaSession ?: run {
            stopSelf()
            return
        }
        if (!session.player.playWhenReady) {
            stopSelf()
        }
    }
}
