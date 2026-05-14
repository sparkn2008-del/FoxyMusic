package com.foxymusic

import android.content.Context
import androidx.media3.database.DatabaseProvider
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.offline.Download
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.Executor

/**
 * Media3 offline downloads (supports HLS and progressive) using DownloadManager.
 *
 * This is a lightweight adaptation for FoxyMusic: we keep our own state store and UI,
 * but use Media3's downloader for correctness and HLS support.
 */
object FoxyMedia3Downloads {
    private const val MAX_PARALLEL = 2

    private var downloadCache: SimpleCache? = null
    private var databaseProvider: DatabaseProvider? = null
    private var downloadManager: DownloadManager? = null

    private val _downloads = MutableStateFlow<Map<String, Download>>(emptyMap())
    val downloads: StateFlow<Map<String, Download>> = _downloads

    fun ensureInitialized(context: Context) {
        if (downloadManager != null) return

        val app = context.applicationContext
        val db = StandaloneDatabaseProvider(app)
        databaseProvider = db

        val dir = File(app.getExternalFilesDir(null), "media3_download_cache").apply { mkdirs() }
        val cache = SimpleCache(dir, androidx.media3.datasource.cache.NoOpCacheEvictor(), db)
        downloadCache = cache

        val okHttp = OkHttpClient.Builder().retryOnConnectionFailure(true).build()
        val upstreamFactory: DataSource.Factory = OkHttpDataSource.Factory(okHttp)
            .setUserAgent(StreamExtractor.STREAM_USER_AGENT)
            .setDefaultRequestProperties(buildFoxyStreamHeaders())

        val dataSourceFactory = CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(upstreamFactory)

        val mgr = DownloadManager(
            app,
            db,
            cache,
            dataSourceFactory,
            Executor(Runnable::run)
        ).apply {
            maxParallelDownloads = MAX_PARALLEL
            addListener(object : DownloadManager.Listener {
                override fun onDownloadChanged(
                    downloadManager: DownloadManager,
                    download: Download,
                    finalException: Exception?
                ) {
                    _downloads.value = _downloads.value + (download.request.id to download)
                }

                override fun onDownloadRemoved(downloadManager: DownloadManager, download: Download) {
                    _downloads.value = _downloads.value - download.request.id
                }
            })
        }

        // Seed current download index.
        val result = mutableMapOf<String, Download>()
        val cursor = mgr.downloadIndex.getDownloads()
        while (cursor.moveToNext()) {
            result[cursor.download.request.id] = cursor.download
        }
        _downloads.value = result

        downloadManager = mgr
    }

    fun managerOrThrow(context: Context): DownloadManager {
        ensureInitialized(context)
        return downloadManager ?: error("DownloadManager not initialized")
    }

    fun addDownload(context: Context, song: Song, uri: String) {
        ensureInitialized(context)
        val request = DownloadRequest.Builder(song.videoId, android.net.Uri.parse(uri))
            .setData(song.videoId.toByteArray())
            .build()
        DownloadService.sendAddDownload(
            context,
            FoxyExoDownloadService::class.java,
            request,
            /* foreground= */ false
        )
    }

    fun removeDownload(context: Context, videoId: String) {
        ensureInitialized(context)
        DownloadService.sendRemoveDownload(
            context,
            FoxyExoDownloadService::class.java,
            videoId,
            /* foreground= */ false
        )
    }
}

