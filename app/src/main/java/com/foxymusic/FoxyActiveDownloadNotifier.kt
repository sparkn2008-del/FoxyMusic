package com.foxymusic

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import kotlin.math.roundToInt

/**
 * Ongoing notification for progressive (OkHttp) downloads — complements Media3's
 * [FoxyExoDownloadService] notification for HLS jobs.
 */
object FoxyActiveDownloadNotifier {

    private const val CHANNEL_ID = "foxy_direct_download"
    private const val BASE_ID = 5353

    private fun mgr(ctx: Context) =
        ctx.applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            ctx.getString(R.string.direct_download_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = ctx.getString(R.string.direct_download_channel_description)
            setShowBadge(false)
        }
        mgr(ctx).createNotificationChannel(ch)
    }

    fun notifyProgress(ctx: Context, song: Song, progress01: Float) {
        ensureChannel(ctx)
        val pct = (progress01.coerceIn(0f, 1f) * 100f).roundToInt().coerceIn(0, 100)
        val nm = mgr(ctx)
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_foxy_notification)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentTitle(ctx.getString(R.string.direct_download_title, song.title))
            .setContentText(ctx.getString(R.string.download_progress_percent, pct))
            .setProgress(100, pct, false)
            .build()
        nm.notify(notificationId(song.videoId), notif)
    }

    fun cancel(ctx: Context, videoId: String) {
        mgr(ctx).cancel(notificationId(videoId))
    }

    private fun notificationId(videoId: String): Int =
        BASE_ID + (videoId.hashCode() and 0x7fff_ffff)
}
