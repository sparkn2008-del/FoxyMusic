package com.foxymusic



import android.app.Notification

import androidx.core.app.NotificationCompat

import androidx.media3.exoplayer.offline.Download

import androidx.media3.exoplayer.offline.DownloadManager

import androidx.media3.exoplayer.offline.DownloadService

import androidx.media3.exoplayer.scheduler.PlatformScheduler

import androidx.media3.exoplayer.scheduler.Scheduler

import org.json.JSONObject

import java.nio.charset.StandardCharsets



/**

 * Foreground download service used by Media3's DownloadManager.

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



    override fun getForegroundNotification(

        downloads: MutableList<Download>,

        notMetRequirements: Int

    ): Notification {

        val active = downloads.firstOrNull { d ->

            d.state == Download.STATE_DOWNLOADING ||

                d.state == Download.STATE_QUEUED ||

                d.state == Download.STATE_RESTARTING

        }



        val builder = NotificationCompat.Builder(this, "foxy_downloads")

            .setSmallIcon(R.drawable.ic_stat_foxy_notification)

            .setOnlyAlertOnce(true)

            .setOngoing(true)

            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)



        if (active == null) {

            builder.setContentTitle(getString(R.string.downloads_channel_name))

                .setContentText(getString(R.string.downloads_channel_description))

                .setProgress(0, 0, true)

            return builder.build()

        }



        val title = downloadTrackTitle(active)

        builder.setContentTitle(title)

        val len = active.contentLength

        val indeterminate = len <= 0L

        val pct = if (!indeterminate) {

            ((100L * active.bytesDownloaded) / len).toInt().coerceIn(0, 100)

        } else {

            0

        }

        builder.setContentText(

            if (indeterminate) {

                getString(R.string.download_progress_indeterminate)

            } else {

                getString(R.string.download_progress_percent, pct)

            }

        )

        builder.setProgress(100, pct, indeterminate)

        return builder.build()

    }



    private fun downloadTrackTitle(d: Download): String {

        val raw = d.request.data ?: return d.request.id

        return try {

            JSONObject(String(raw, StandardCharsets.UTF_8))

                .optString("title")

                .ifBlank { d.request.id }

        } catch (_: Exception) {

            d.request.id

        }

    }

}


