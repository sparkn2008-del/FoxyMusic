package com.foxymusic



import android.content.Context

import androidx.media3.database.DatabaseProvider

import androidx.media3.database.StandaloneDatabaseProvider

import androidx.media3.datasource.DataSource

import androidx.media3.datasource.cache.CacheDataSource

import androidx.media3.datasource.cache.SimpleCache

import androidx.media3.datasource.okhttp.OkHttpDataSource

import androidx.media3.exoplayer.offline.Download

import androidx.media3.exoplayer.offline.DownloadManager

import androidx.media3.exoplayer.offline.DownloadRequest

import androidx.media3.exoplayer.offline.DownloadService

import kotlinx.coroutines.CoroutineScope

import kotlinx.coroutines.Dispatchers

import kotlinx.coroutines.SupervisorJob

import kotlinx.coroutines.flow.MutableStateFlow

import kotlinx.coroutines.flow.StateFlow

import kotlinx.coroutines.launch

import okhttp3.OkHttpClient

import org.json.JSONObject

import java.io.File

import java.nio.charset.StandardCharsets

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



    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var applicationContext: Context? = null



    private val _downloads = MutableStateFlow<Map<String, Download>>(emptyMap())

    val downloads: StateFlow<Map<String, Download>> = _downloads



    fun ensureInitialized(context: Context) {

        if (downloadManager != null) return



        val app = context.applicationContext

        applicationContext = app

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

                    val id = download.request.id

                    when (download.state) {

                        Download.STATE_DOWNLOADING -> {

                            val len = download.contentLength

                            val frac = if (len > 0L) {

                                download.bytesDownloaded.toFloat() / len.toFloat()

                            } else {

                                0.05f

                            }

                            FoxyLibraryStore.setDownloadProgress(id, frac.coerceIn(0f, 0.995f))

                        }

                        Download.STATE_COMPLETED -> {

                            FoxyLibraryStore.clearDownloadProgress(id)

                            val ctx = applicationContext ?: return

                            val metaBytes = download.request.data

                            val song = runCatching {

                                val json = JSONObject(

                                    String(metaBytes ?: ByteArray(0), StandardCharsets.UTF_8),

                                )

                                Song(

                                    videoId = json.optString("videoId", id),

                                    title = json.optString("title").ifBlank { "Offline track" },

                                    artist = json.optString("artist").ifBlank { "Unknown artist" },

                                    thumbnail = json.optString("thumbnail"),

                                    duration = json.optString("duration").takeIf { it.isNotBlank() },

                                    album = json.optString("album").takeIf { it.isNotBlank() },

                                    artworkUrl = json.optString("artworkUrl").takeIf { it.isNotBlank() },

                                )

                            }.getOrElse {

                                Song(

                                    videoId = id,

                                    title = "Offline track",

                                    artist = "Unknown artist",

                                    thumbnail = "",

                                )

                            }

                            val streamUrl = download.request.uri.toString()

                            FoxyOfflineBundle.onHlsDownloadComplete(ctx, song, streamUrl)

                        }

                        Download.STATE_FAILED -> {

                            FoxyLibraryStore.clearDownloadProgress(id)

                        }

                        else -> Unit

                    }

                }



                override fun onDownloadRemoved(downloadManager: DownloadManager, download: Download) {

                    _downloads.value = _downloads.value - download.request.id

                    FoxyLibraryStore.clearDownloadProgress(download.request.id)

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

        val meta = FoxyOfflineBundle.songToDownloadPayload(song)

        val request = DownloadRequest.Builder(song.videoId, android.net.Uri.parse(uri))

            .setData(meta.toString().toByteArray(StandardCharsets.UTF_8))

            .build()

        DownloadService.sendAddDownload(

            context,

            FoxyExoDownloadService::class.java,

            request,

            /* foreground= */ false

        )

    }



    fun isCompleted(context: Context, videoId: String): Boolean {

        ensureInitialized(context)

        val d = downloadManager?.downloadIndex?.getDownload(videoId) ?: return false

        return d.state == Download.STATE_COMPLETED

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


