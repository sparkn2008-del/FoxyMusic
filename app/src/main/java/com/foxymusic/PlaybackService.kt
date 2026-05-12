package com.foxymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class PlaybackService : Service() {
    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> MusicPlayer.togglePlayPause()
            ACTION_NEXT -> MusicPlayer.playNext()
            ACTION_PREVIOUS -> MusicPlayer.playPrevious()
            ACTION_STOP -> {
                MusicPlayer.release()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "FoxyMusic playback", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val song = MusicPlayer.state.value.currentSong
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPendingIntent = PendingIntent.getActivity(this, 10, openIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(song?.title ?: "FoxyMusic")
            .setContentText(song?.artist ?: "Ready to play")
            .setContentIntent(openPendingIntent)
            .setOngoing(MusicPlayer.isPlaying())
            .addAction(android.R.drawable.ic_media_previous, "Previous", serviceIntent(ACTION_PREVIOUS, 1))
            .addAction(android.R.drawable.ic_media_pause, "Play/Pause", serviceIntent(ACTION_PLAY_PAUSE, 2))
            .addAction(android.R.drawable.ic_media_next, "Next", serviceIntent(ACTION_NEXT, 3))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", serviceIntent(ACTION_STOP, 4))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun serviceIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).setAction(action)
        return PendingIntent.getService(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    companion object {
        private const val CHANNEL_ID = "foxy_playback"
        private const val NOTIFICATION_ID = 42
        private const val ACTION_PLAY_PAUSE = "com.foxymusic.PLAY_PAUSE"
        private const val ACTION_NEXT = "com.foxymusic.NEXT"
        private const val ACTION_PREVIOUS = "com.foxymusic.PREVIOUS"
        private const val ACTION_STOP = "com.foxymusic.STOP"

        fun start(context: Context) {
            val intent = Intent(context, PlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun updateNowPlaying(context: Context) {
            start(context)
        }
    }
}
