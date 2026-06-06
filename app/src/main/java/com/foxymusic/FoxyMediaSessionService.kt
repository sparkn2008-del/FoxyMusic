package com.foxymusic

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.MediaStyleNotificationHelper
import androidx.compose.ui.graphics.toArgb
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.min

@OptIn(UnstableApi::class)
/**
 * Media3 session service — rich media-style notification (Foxy / YT Music–style shade card)
 * wired to ExoPlayer in [MusicPlayer].
 */
class FoxyMediaSessionService : MediaSessionService() {
    private val tag = "FoxyMediaSessionService"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val artworkScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        instance = this
        ensurePlaybackNotificationChannel()
        // Call startForeground before MediaSessionService wiring so the window after
        // startForegroundService() is satisfied on strict OEMs (e.g. MIUI).
        try {
            promoteToForeground("onCreate-early")
        } catch (e: Exception) {
            Log.e(tag, "early promoteToForeground failed", e)
        }
        super.onCreate()
        val provider = DefaultMediaNotificationProvider.Builder(this)
            .setChannelId(PLAYBACK_CHANNEL_ID)
            .setChannelName(R.string.playback_channel_name)
            .build()
        provider.setSmallIcon(R.drawable.ic_stat_foxy_notification)
        setMediaNotificationProvider(provider)

        // After Media3 wires the session, replace the placeholder with the full MediaStyle card
        // (artwork, transport, progress). Some OEMs / FGS timing race the first update.
        scheduleNotificationRefresh()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        artworkScope.cancel()
        super.onDestroy()
    }

    private fun scheduleNotificationRefresh() {
        mainHandler.post { requestMediaNotificationRefresh() }
        mainHandler.postDelayed({ requestMediaNotificationRefresh() }, 400)
        mainHandler.postDelayed({ requestMediaNotificationRefresh() }, 1200)
    }

    private fun requestMediaNotificationRefresh() {
        val session = MusicPlayer.mediaSession ?: return
        try {
            onUpdateNotification(session, false)
        } catch (e: Exception) {
            Log.w(tag, "requestMediaNotificationRefresh failed", e)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createPlaybackChannel() {
        val nm = ContextCompat.getSystemService(this, NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(PLAYBACK_CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            PLAYBACK_CHANNEL_ID,
            getString(R.string.playback_channel_name),
            // Higher importance helps the expanded media card / controls surface like YT Music.
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = getString(R.string.playback_channel_description)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(ch)
    }

    private fun ensurePlaybackNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createPlaybackChannel()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensurePlaybackNotificationChannel()
        // Every startForegroundService() must call startForeground() promptly; Media3's
        // onUpdateNotification can be delayed by scheduleNotificationRefresh posts.
        runCatching { promoteToForeground("onStartCommand") }
        if (intent?.action == ACTION_REFRESH_NOTIFICATION) {
            scheduleNotificationRefresh()
            maybeEnqueueArtworkForPlaceholder(
                DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID,
            )
            return START_STICKY
        }
        if (intent?.action == ACTION_MEDIA_COMMAND) {
            when (intent.getIntExtra(EXTRA_PLAYER_COMMAND, -1)) {
                Player.COMMAND_PLAY_PAUSE -> MusicPlayer.togglePlayPause()
                Player.COMMAND_SEEK_TO_NEXT -> MusicPlayer.playNextFromMediaSession()
                Player.COMMAND_SEEK_TO_PREVIOUS -> MusicPlayer.playPreviousFromMediaSession()
            }
            scheduleNotificationRefresh()
            return START_STICKY
        }
        scheduleNotificationRefresh()
        return START_STICKY
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return MusicPlayer.mediaSession
    }

    /**
     * Android 12+ may deny foreground promotions while backgrounded.
     * Never call [stopSelf] here — that removes the media session and shade controls until
     * the user starts playback again.
     *
     * If [super.onUpdateNotification] throws before calling [startForeground], the process
     * can crash with [android.app.ForegroundServiceDidNotStartInTimeException] after
     * [Context.startForegroundService]. Always promote with a minimal notification when the
     * Media3 path fails.
     */
    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        try {
            super.onUpdateNotification(session, startInForegroundRequired)
        } catch (e: Exception) {
            val isFgPolicy =
                e is ForegroundServiceStartNotAllowedException ||
                    (e is SecurityException && e.message?.contains("Foreground", ignoreCase = true) == true)
            if (isFgPolicy) {
                Log.w(
                    tag,
                    "Media3 foreground notification blocked; using rich placeholder startForeground",
                    e
                )
            } else {
                Log.e(tag, "onUpdateNotification failed", e)
            }
            runCatching {
                promoteToForeground("onUpdateNotification-fallback")
            }.onFailure { t ->
                Log.e(tag, "Fallback startForeground failed", t)
            }
        }
    }

    private fun buildFallbackForegroundNotification(largeIcon: Bitmap? = null): android.app.Notification {
        val ui = MusicPlayer.state.value
        val song = ui.currentSong
        val title = song?.title?.trim()?.takeIf { it.isNotEmpty() }
            ?: getString(R.string.app_name)
        val text = when {
            song == null -> getString(R.string.playback_foreground_placeholder)
            ui.error != null -> ui.error.orEmpty()
            ui.isBuffering -> getString(R.string.playback_buffering)
            else -> song.artist.trim().ifEmpty { getString(R.string.playback_foreground_placeholder) }
        }

        val b = NotificationCompat.Builder(this, PLAYBACK_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            // Brand line (expanded media templates show this above the title on many OEMs).
            .setSubText(getString(R.string.playback_notification_app))
            .setSmallIcon(R.drawable.ic_stat_foxy_notification)
            .setOngoing(ui.isPlaying || ui.isBuffering)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)

        FoxyDynamicTheme.accent.value?.let { composeColor ->
            runCatching {
                b.setColorized(true)
                b.color = composeColor.toArgb()
            }
        }

        if (largeIcon != null) {
            b.setLargeIcon(largeIcon)
        }

        val session = MusicPlayer.mediaSession
        if (session != null) {
            attachMediaTransportActions(b, session)
            b.setStyle(
                MediaStyleNotificationHelper.MediaStyle(session)
                    .setShowActionsInCompactView(0, 1, 2)
                    .setShowCancelButton(true),
            )
        }

        if (ui.durationMs > 500 && !ui.isBuffering) {
            val max = 100
            val prog = ((ui.positionMs.coerceAtLeast(0L) * max) / ui.durationMs.coerceAtLeast(1L))
                .toInt()
                .coerceIn(0, max)
            b.setProgress(max, prog, false)
        } else if (ui.isBuffering) {
            b.setProgress(0, 0, true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            b.setForegroundServiceBehavior(android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return b.build()
    }

    private fun attachMediaTransportActions(
        builder: NotificationCompat.Builder,
        session: MediaSession,
    ) {
        val player = session.player
        val commands = player.availableCommands
        fun addAction(command: Int, iconRes: Int, label: String) {
            if (!commands.contains(command)) return
            builder.addAction(
                NotificationCompat.Action.Builder(
                    iconRes,
                    label,
                    mediaCommandPendingIntent(command),
                ).build(),
            )
        }
        addAction(Player.COMMAND_SEEK_TO_PREVIOUS, R.drawable.ic_media_prev, "Previous")
        val playPauseIcon =
            if (player.isPlaying) R.drawable.ic_media_pause else R.drawable.ic_media_play
        addAction(Player.COMMAND_PLAY_PAUSE, playPauseIcon, "Play")
        addAction(Player.COMMAND_SEEK_TO_NEXT, R.drawable.ic_media_next, "Next")
    }

    private fun mediaCommandPendingIntent(command: Int): PendingIntent {
        val intent = Intent(this, FoxyMediaSessionService::class.java).apply {
            action = ACTION_MEDIA_COMMAND
            putExtra(EXTRA_PLAYER_COMMAND, command)
        }
        return PendingIntent.getService(
            this,
            command,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun promoteToForeground(reason: String) {
        val notification = buildFallbackForegroundNotification()
        val nid = DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID
        ServiceCompat.startForeground(
            this,
            nid,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )
        Log.i(tag, "startForeground ($reason) id=$nid")
        maybeEnqueueArtworkForPlaceholder(nid)
    }

    private fun maybeEnqueueArtworkForPlaceholder(notificationId: Int) {
        val song = MusicPlayer.state.value.currentSong ?: return
        artworkScope.launch {
            val bmp = withContext(Dispatchers.IO) { resolveNotificationArtwork(song) } ?: return@launch
            val nm = NotificationManagerCompat.from(this@FoxyMediaSessionService)
            nm.notify(notificationId, buildFallbackForegroundNotification(bmp))
        }
    }

    private fun resolveNotificationArtwork(song: Song): Bitmap? {
        val ctx = applicationContext
        FoxyOfflineBundle.offlineArtworkPath(ctx, song.videoId)?.let { path ->
            decodeAlbumArtFile(path)?.let { return it }
        }
        FoxyDynamicTheme.offlineArtworkPath.value?.let { path ->
            decodeAlbumArtFile(path)?.let { return it }
        }
        val url = song.highQualityArtworkUrl().trim()
        if (url.isEmpty()) return null
        return decodeAlbumArt(url)
    }

    private fun decodeAlbumArtFile(path: String): Bitmap? = runCatching {
        BitmapFactory.decodeFile(path)
    }.getOrNull()

    private fun decodeAlbumArt(url: String): Bitmap? = runCatching {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 15_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "FoxyMusic/1.0 (Android)")
            connect()
        }
        if (conn.responseCode !in 200..299) return@runCatching null
        conn.inputStream.use { input ->
            val raw = BitmapFactory.decodeStream(input) ?: return@runCatching null
            val maxSide = 720
            if (raw.width <= maxSide && raw.height <= maxSide) return@runCatching raw
            val scale = min(maxSide.toFloat() / raw.width, maxSide.toFloat() / raw.height)
            val w = (raw.width * scale).toInt().coerceAtLeast(1)
            val h = (raw.height * scale).toInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(raw, w, h, true).also {
                if (it != raw) raw.recycle()
            }
        }
    }.getOrNull()

    override fun onTaskRemoved(rootIntent: Intent?) {
        val continueInBackground = FoxySettings.state.value.continuePlaybackWhenDismissed
        val session = MusicPlayer.mediaSession
        if (!continueInBackground) {
            session?.player?.pause()
            stopSelf()
            return
        }
        if (session == null) {
            stopSelf()
            return
        }
        // Stay foreground so OEMs do not kill playback when the task is cleared from recents.
        runCatching { promoteToForeground("onTaskRemoved") }
        scheduleNotificationRefresh()
    }

    companion object {
        /** New channel id so IMPORTANCE_HIGH applies for users who had the old default channel. */
        const val PLAYBACK_CHANNEL_ID = "foxy_playback_media"
        private const val ACTION_MEDIA_COMMAND = "com.foxymusic.action.MEDIA_COMMAND"
        private const val ACTION_REFRESH_NOTIFICATION = "com.foxymusic.action.REFRESH_NOTIFICATION"
        private const val EXTRA_PLAYER_COMMAND = "player_command"

        @Volatile
        private var instance: FoxyMediaSessionService? = null

        /** Rebuild shade / lock-screen media card when the track changes. */
        fun refreshPlaybackNotification(context: Context) {
            val app = context.applicationContext
            val svc = instance
            if (svc != null) {
                svc.mainHandler.post {
                    svc.requestMediaNotificationRefresh()
                    svc.maybeEnqueueArtworkForPlaceholder(
                        DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID,
                    )
                }
                return
            }
            val intent = Intent(app, FoxyMediaSessionService::class.java).apply {
                action = ACTION_REFRESH_NOTIFICATION
            }
            runCatching { app.startService(intent) }
        }
    }
}
