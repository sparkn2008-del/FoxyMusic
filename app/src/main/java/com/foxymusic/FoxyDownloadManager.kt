package com.foxymusic

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Minimal offline downloader.
 *
 * For now this supports direct progressive URLs (mp4/webm/etc) returned by [StreamExtractor].
 * HLS manifest downloads are not supported in this first iteration.
 */
object FoxyDownloadManager {
    private const val TAG = "FoxyDownloadManager"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient.Builder()
        .retryOnConnectionFailure(true)
        .build()

    private val activeDownloads = ConcurrentHashMap<String, Boolean>()
    private val lastNotifyPct = ConcurrentHashMap<String, Int>()

    fun isDownloading(videoId: String): Boolean = activeDownloads[videoId] == true

    fun downloadSong(context: Context, song: Song) {
        if (isDownloading(song.videoId)) return
        if (song.isDownloaded && !song.localPath.isNullOrBlank()) return

        val localDir = FoxyDownloadsPaths.dir(context)
        val outputPathBase = File(localDir, song.videoId).absolutePath

        scope.launch {
            activeDownloads[song.videoId] = true
            lastNotifyPct.remove(song.videoId)
            val appCtx = context.applicationContext
            FoxyOfflineBundle.prepareDownloadMeta(appCtx, song)
            FoxyActiveDownloadNotifier.ensureChannel(appCtx)
            var outFile: File? = null
            try {
                val tier = FoxySettings.state.value.downloadQualityTier
                val result = withContext(Dispatchers.IO) {
                    StreamExtractor.getStreamResult(
                        song.videoId,
                        tier,
                        song.bestQualitySearchQuery(),
                        song.title,
                        song.artist,
                    )
                }
                val url = result.url
                if (url.isNullOrBlank()) {
                    Log.w(TAG, "No downloadable URL for ${song.videoId}: ${result.error}")
                    FoxyActiveDownloadNotifier.cancel(appCtx, song.videoId)
                    return@launch
                }

                if (url.contains(".m3u8")) {
                    FoxyLibraryStore.setDownloadProgress(song.videoId, 0.01f)
                    FoxyMedia3Downloads.addDownload(context, song, url)
                    return@launch
                }

                val ext = outputExtFromUrl(url)
                outFile = File("$outputPathBase$ext")

                // Reset progress UI
                FoxyLibraryStore.setDownloadProgress(song.videoId, 0f)
                FoxyActiveDownloadNotifier.notifyProgress(appCtx, song, 0f)

                val account = FoxyAccount.state.value
                val requestBuilder = Request.Builder()
                    .url(url)
                    .addHeader("User-Agent", StreamExtractor.STREAM_USER_AGENT)
                    .addHeader("Origin", "https://music.youtube.com")
                    .addHeader("Referer", "https://music.youtube.com/")

                if (account.cookie.isNotBlank()) {
                    requestBuilder.addHeader("Cookie", account.cookie)
                    account.cookie.sapisidHashHeader()?.let { requestBuilder.addHeader("Authorization", it) }
                }

                val request = requestBuilder.build()

                client.newCall(request).execute().use { resp ->
                    if (!resp.isSuccessful) {
                        throw IllegalStateException("HTTP ${resp.code} while downloading ${song.videoId}")
                    }

                    val body = resp.body ?: throw IllegalStateException("Empty response body")
                    val contentLength = body.contentLength().coerceAtLeast(1L)

                    FileOutputStream(outFile).use { out ->
                        var downloaded = 0L
                        val buffer = ByteArray(128 * 1024)
                        while (true) {
                            val read = body.byteStream().read(buffer)
                            if (read <= 0) break
                            out.write(buffer, 0, read)
                            downloaded += read
                            val progress = downloaded.toFloat() / contentLength.toFloat()
                            FoxyLibraryStore.setDownloadProgress(song.videoId, progress)
                            val pct = (progress * 100f).toInt().coerceIn(0, 100)
                            val prev = lastNotifyPct[song.videoId] ?: -1
                            if (pct >= prev + 2 || pct >= 99 || prev < 0) {
                                lastNotifyPct[song.videoId] = pct
                                FoxyActiveDownloadNotifier.notifyProgress(appCtx, song, progress)
                            }
                        }
                        out.flush()
                    }
                }

                if (outFile.length() <= 0L) {
                    Log.w(TAG, "Downloaded file is empty: ${outFile.absolutePath}")
                    outFile.delete()
                    FoxyActiveDownloadNotifier.cancel(appCtx, song.videoId)
                    return@launch
                }

                val finalSong = song.copy(
                    localPath = outFile.absolutePath,
                    isDownloaded = true,
                    streamUrl = null,
                    bitrate = result.bitrate,
                )
                FoxyLibraryStore.markAsDownloaded(finalSong, outFile.absolutePath)
                FoxyOfflineBundle.onProgressiveDownloadComplete(appCtx, finalSong, outFile)
                FoxyLibraryStore.clearDownloadProgress(song.videoId)
                FoxyActiveDownloadNotifier.cancel(appCtx, song.videoId)
            } catch (e: Exception) {
                Log.e(TAG, "Download failed for ${song.videoId}: ${e.message}", e)
                // Clear progress so UI doesn't get stuck.
                FoxyLibraryStore.clearDownloadProgress(song.videoId)
                FoxyActiveDownloadNotifier.cancel(appCtx, song.videoId)
                outFile?.delete()
            } finally {
                activeDownloads[song.videoId] = false
                lastNotifyPct.remove(song.videoId)
            }
        }
    }

    fun removeDownload(context: Context, song: Song) {
        activeDownloads[song.videoId] = false
        runCatching { FoxyMedia3Downloads.removeDownload(context, song.videoId) }
        FoxyLibraryStore.removeDownload(song, context)
    }

    private fun outputExtFromUrl(url: String): String {
        return when {
            url.contains(".flac", ignoreCase = true) || url.contains("audio%2Fflac", ignoreCase = true) || url.contains("audio/flac", ignoreCase = true) -> ".flac"
            url.contains(".alac", ignoreCase = true) -> ".m4a"
            url.contains(".wav", ignoreCase = true) || url.contains("audio%2Fwav", ignoreCase = true) || url.contains("audio/wav", ignoreCase = true) -> ".wav"
            url.contains(".webm", ignoreCase = true) -> ".webm"
            url.contains(".mp4", ignoreCase = true) -> ".mp4"
            url.contains(".m4a", ignoreCase = true) -> ".m4a"
            url.contains(".opus", ignoreCase = true) -> ".opus"
            url.contains("audio%2Fwebm", ignoreCase = true) || url.contains("audio/webm", ignoreCase = true) -> ".webm"
            url.contains("audio%2Fmp4", ignoreCase = true) || url.contains("audio/mp4", ignoreCase = true) -> ".mp4"
            else -> ".media"
        }
    }

    // (best-effort) future: support HLS offline downloads using Media3 DownloadManager.
}

