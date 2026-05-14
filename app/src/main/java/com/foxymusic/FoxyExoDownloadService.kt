package com.foxymusic

import android.app.Notification
import androidx.media3.exoplayer.scheduler.PlatformScheduler
import androidx.media3.exoplayer.scheduler.Scheduler
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadService

/**
 * Foreground download service used by Media3's DownloadManager.
 *
 * We keep notifications minimal for now; later we'll style this.
 */
class FoxyExoDownloadService : DownloadService(
    /* foregroundNotificationId = */ 4242,
    /* foregroundNotificationUpdateInterval = */ 1000L,
    /* channelId = */ "foxy_downloads",
    /* channelNameResourceId = */ R.string.downloads_channel_name,
    /* channelDescriptionResourceId = */ R.string.downloads_channel_description
) {
    override fun getScheduler(): Scheduler = PlatformScheduler(this, 4243)

    override fun getDownloadManager(): DownloadManager {
        return FoxyMedia3Downloads.managerOrThrow(this)
    }

    override fun getForegroundNotification(downloads: MutableList<androidx.media3.exoplayer.offline.Download>, notMetRequirements: Int): Notification {
        val builder = androidx.core.app.NotificationCompat.Builder(this, "foxy_downloads")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        return builder.build()
    }
}

