package com.foxymusic

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object FoxyUpdateNotifier {

    private const val CHANNEL_ID = "foxy_app_updates"
    private const val NOTIFICATION_ID = 9001

    fun show(context: Context, tag: String, htmlUrl: String, body: String?) {
        val app = context.applicationContext
        ensureChannel(app)
        val url = htmlUrl.takeIf { it.isNotBlank() }
            ?: "https://github.com/sparkn2008-del/FoxyMusic/releases/latest"
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pending = PendingIntent.getActivity(
            app,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notes = body?.trim()?.take(180).orEmpty()
        val text = if (notes.isNotEmpty()) {
            "$tag — $notes"
        } else {
            "A new FoxyMusic release is available on GitHub."
        }
        val notification = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("FoxyMusic update available")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(app).notify(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "App updates",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Notifies when a newer FoxyMusic APK is published on GitHub."
        }
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }
}
