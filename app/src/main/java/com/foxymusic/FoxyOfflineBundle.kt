package com.foxymusic

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Persists offline artwork, lyrics, and sidecar metadata next to downloaded audio files.
 */
object FoxyOfflineBundle {
    private const val TAG = "FoxyOfflineBundle"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient.Builder().retryOnConnectionFailure(true).build()

    private fun downloadsDir(context: Context) =
        File(context.getExternalFilesDir(null), "downloads").apply { mkdirs() }

    fun artFile(context: Context, videoId: String) =
        File(downloadsDir(context), "$videoId.art.jpg")

    fun lyricsFile(context: Context, videoId: String) =
        File(downloadsDir(context), "$videoId.lyrics.json")

    fun metaFile(context: Context, videoId: String) =
        File(downloadsDir(context), "$videoId.foxy-meta.json")

    /** After a progressive file download succeeds. */
    fun onProgressiveDownloadComplete(context: Context, song: Song, mediaFile: File) {
        val app = context.applicationContext
        writeMeta(app, song, mediaFile.absolutePath, hlsOffline = false, streamUrl = null)
        scope.launch {
            persistArtwork(app, song)
            persistLyrics(app, song)
            refreshLibraryAfterBundle(app)
        }
    }

    /** After Media3 finishes an HLS offline download. */
    fun onHlsDownloadComplete(context: Context, song: Song, streamUrl: String) {
        val app = context.applicationContext
        val updated = song.copy(isDownloaded = true, streamUrl = streamUrl, localPath = null)
        FoxyLibraryStore.markAsDownloaded(updated, localPath = null)
        writeMeta(app, updated, localPath = null, hlsOffline = true, streamUrl = streamUrl)
        scope.launch {
            persistArtwork(app, updated)
            persistLyrics(app, updated)
            refreshLibraryAfterBundle(app)
        }
    }

    private suspend fun refreshLibraryAfterBundle(context: Context) {
        FoxyLibraryStore.refreshDownloadsFromDisk(context)
        FoxyFlutterBridge.emitLibraryDownloadsChanged(context)
    }

    /**
     * Resolve a playable URL/path for an offline track (file:// or cached HLS manifest).
     */
    fun resolvePlayableUrl(context: Context, song: Song): String? {
        song.localPath?.trim()?.takeIf { it.isNotBlank() }?.let { path ->
            val f = File(path)
            if (f.isFile && f.length() > 0L) return android.net.Uri.fromFile(f).toString()
        }
        val vid = song.videoId.trim()
        if (vid.isBlank()) return null
        val dir = downloadsDir(context)
        val exts = setOf("webm", "mp4", "m4a", "opus", "mp3", "media", "mkv", "aac", "ogg")
        dir.listFiles()?.firstOrNull { f ->
            f.isFile && f.nameWithoutExtension == vid && f.extension.lowercase() in exts && f.length() > 0L
        }?.let { return android.net.Uri.fromFile(it).toString() }

        val meta = readMeta(context, vid) ?: return null
        if (meta.optBoolean("hlsOffline", false)) {
            val stream = meta.optString("streamUrl").trim()
            if (stream.isNotEmpty() && FoxyMedia3Downloads.isCompleted(context, vid)) {
                return stream
            }
        }
        return null
    }

    fun offlineArtworkPath(context: Context, videoId: String): String? {
        val f = artFile(context, videoId)
        return f.takeIf { it.isFile && it.length() > 0L }?.absolutePath
    }

    fun readCachedLyrics(context: Context, videoId: String): List<Map<String, Any>>? {
        val f = lyricsFile(context, videoId)
        if (!f.isFile || f.length() <= 0L) return null
        return try {
            val arr = JSONArray(f.readText())
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    add(
                        mapOf(
                            "timeMs" to o.optLong("timeMs", 0L),
                            "text" to o.optString("text", ""),
                        ),
                    )
                }
            }.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    private fun writeMeta(
        context: Context,
        song: Song,
        localPath: String?,
        hlsOffline: Boolean,
        streamUrl: String?,
    ) {
        try {
            val json = JSONObject().apply {
                put("videoId", song.videoId)
                put("title", song.title)
                put("artist", song.artist)
                put("thumbnail", song.thumbnail)
                put("artworkUrl", song.artworkUrl ?: "")
                put("duration", song.duration ?: "")
                put("album", song.album ?: "")
                put("localPath", localPath ?: "")
                put("hlsOffline", hlsOffline)
                put("streamUrl", streamUrl ?: "")
                val art = artFile(context, song.videoId)
                if (art.isFile) put("localArtPath", art.absolutePath)
            }
            metaFile(context, song.videoId).writeText(json.toString())
        } catch (e: Exception) {
            Log.w(TAG, "writeMeta failed: ${e.message}")
        }
    }

    fun readMeta(context: Context, videoId: String): JSONObject? {
        val f = metaFile(context, videoId)
        if (!f.isFile || f.length() <= 0L) return null
        return try {
            JSONObject(f.readText())
        } catch (_: Exception) {
            null
        }
    }

    private fun artworkDownloadUrls(song: Song): List<String> {
        val urls = LinkedHashSet<String>()
        song.artworkCandidates().forEach { u ->
            if (u.isNotBlank()) urls.add(u.trim())
        }
        song.highQualityArtworkUrl().trim().takeIf { it.isNotEmpty() }?.let { urls.add(it) }
        if (urls.isEmpty() && song.videoId.isNotBlank()) {
            urls.add("https://img.youtube.com/vi/${song.videoId}/maxresdefault.jpg")
            urls.add("https://img.youtube.com/vi/${song.videoId}/hqdefault.jpg")
        }
        return urls.toList()
    }

    private suspend fun persistArtwork(context: Context, song: Song) {
        withContext(Dispatchers.IO) {
            val urls = artworkDownloadUrls(song)
            if (urls.isEmpty()) return@withContext
            val out = artFile(context, song.videoId)
            for (url in urls) {
                try {
                    val req = Request.Builder()
                        .url(url)
                        .addHeader("User-Agent", StreamExtractor.STREAM_USER_AGENT)
                        .build()
                    client.newCall(req).execute().use { resp ->
                        if (!resp.isSuccessful) return@use
                        val bytes = resp.body?.bytes() ?: return@use
                        if (bytes.isEmpty()) return@use
                        if (BitmapFactory.decodeByteArray(bytes, 0, bytes.size) == null) {
                            return@use
                        }
                        out.writeBytes(bytes)
                        val meta = readMeta(context, song.videoId)
                        if (meta != null) {
                            meta.put("localArtPath", out.absolutePath)
                            metaFile(context, song.videoId).writeText(meta.toString())
                        }
                        return@withContext
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "persistArtwork ${song.videoId} ($url): ${e.message}")
                }
            }
        }
    }

    private suspend fun persistLyrics(context: Context, song: Song) {
        withContext(Dispatchers.IO) {
            try {
                val lines = LyricsRepository.fetchSyncedLines(song)
                if (lines.isEmpty()) return@withContext
                val arr = JSONArray()
                lines.forEach { line ->
                    arr.put(
                        JSONObject().apply {
                            put("timeMs", line.timeMs)
                            put("text", line.text)
                        },
                    )
                }
                lyricsFile(context, song.videoId).writeText(arr.toString())
                val meta = readMeta(context, song.videoId)
                if (meta != null) {
                    meta.put("lyricsCached", true)
                    metaFile(context, song.videoId).writeText(meta.toString())
                }
            } catch (e: Exception) {
                Log.w(TAG, "persistLyrics ${song.videoId}: ${e.message}")
            }
        }
    }
}
