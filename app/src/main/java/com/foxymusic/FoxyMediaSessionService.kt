package com.foxymusic

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.ForegroundServiceStartNotAllowedException
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Media3 session service — media notification and lock-screen controls wired to ExoPlayer in [MusicPlayer].
 */
class FoxyMediaSessionService : MediaSessionService() {
    private val tag = "FoxyMediaSessionService"

    override fun onCreate() {
        ensurePlaybackNotificationChannel()
        super.onCreate()
        val provider = DefaultMediaNotificationProvider.Builder(this)
            .setChannelId(PLAYBACK_CHANNEL_ID)
            .setChannelName(R.string.playback_channel_name)
            .build()
        provider.setSmallIcon(R.mipmap.ic_launcher)
        setMediaNotificationProvider(provider)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createPlaybackChannel() {
        val nm = ContextCompat.getSystemService(this, NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(PLAYBACK_CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            PLAYBACK_CHANNEL_ID,
            getString(R.string.playback_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = getString(R.string.playback_channel_description)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
    }

    private fun ensurePlaybackNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createPlaybackChannel()
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return MusicPlayer.mediaSession
    }

    /**
     * Android 12+ may deny foreground promotions while backgrounded.
     * Don't crash playback; just stop this service if denied.
     */
    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        try {
            super.onUpdateNotification(session, startInForegroundRequired)
        } catch (e: ForegroundServiceStartNotAllowedException) {
            Log.w(tag, "Foreground start denied during notification update; stopping service", e)
            stopSelf()
        }
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

    companion object {
        const val PLAYBACK_CHANNEL_ID = "foxy_playback"
    }
}
