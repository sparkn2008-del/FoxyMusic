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
 * Persists offline artwork, synced lyrics, and sidecar metadata next to downloaded audio.
 *
 * Each track gets:
 * - `{videoId}.foxy-meta.json` — title, artist, album, duration, thumbnails, paths, flags
 * - `{videoId}.art.jpg` — cached cover art
 * - `{videoId}.lyrics.json` — synced lyrics (LRCLIB / YouTube)
 */
object FoxyOfflineBundle {
    private const val TAG = "FoxyOfflineBundle"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient.Builder().retryOnConnectionFailure(true).build()

    private fun downloadsDir(context: Context) = FoxyDownloadsPaths.dir(context)

    fun artFile(context: Context, videoId: String) = FoxyDownloadsPaths.artFile(context, videoId)

    fun lyricsFile(context: Context, videoId: String) = FoxyDownloadsPaths.lyricsFile(context, videoId)

    fun metaFile(context: Context, videoId: String) = FoxyDownloadsPaths.metaFile(context, videoId)

    /** Write metadata as soon as a download is queued (before bytes finish). */
    /** JSON embedded in Media3 [DownloadRequest] data for HLS completion recovery. */
    fun songToDownloadPayload(song: Song): JSONObject = JSONObject().apply {
        put("videoId", song.videoId)
        put("title", song.title)
        put("artist", song.artist)
        put("thumbnail", song.thumbnail)
        put("artworkUrl", song.artworkUrl ?: "")
        put("duration", song.duration ?: "")
        put("album", song.album ?: "")
        put("playlistId", song.playlistId ?: "")
        put("genre", song.genre ?: "")
        if (song.year != null) put("year", song.year)
    }

    fun prepareDownloadMeta(context: Context, song: Song) {
        val app = context.applicationContext
        writeSongMeta(
            context = app,
            song = song,
            localPath = null,
            hlsOffline = false,
            streamUrl = null,
            downloadPending = true,
        )
    }

    /** After a progressive file download succeeds. */
    fun onProgressiveDownloadComplete(context: Context, song: Song, mediaFile: File) {
        val app = context.applicationContext
        val enriched = song.copy(
            localPath = mediaFile.absolutePath,
            isDownloaded = true,
            fileSize = mediaFile.length(),
        )
        writeSongMeta(
            context = app,
            song = enriched,
            localPath = mediaFile.absolutePath,
            hlsOffline = false,
            streamUrl = null,
            downloadPending = false,
            fileSizeBytes = mediaFile.length(),
        )
        scope.launch {
            persistArtwork(app, enriched)
            persistLyrics(app, enriched)
            refreshLibraryAfterBundle(app)
        }
    }

    /** After Media3 finishes an HLS offline download. */
    fun onHlsDownloadComplete(context: Context, song: Song, streamUrl: String) {
        val app = context.applicationContext
        val updated = song.copy(
            isDownloaded = true,
            streamUrl = streamUrl,
            localPath = null,
        )
        writeSongMeta(
            context = app,
            song = updated,
            localPath = null,
            hlsOffline = true,
            streamUrl = streamUrl,
            downloadPending = false,
        )
        FoxyLibraryStore.markAsDownloaded(updated, localPath = null)
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
        FoxyDownloadsPaths.findMediaFile(context, vid)?.let {
            return android.net.Uri.fromFile(it).toString()
        }

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

    /**
     * Full sidecar metadata for a downloaded track. Merges with any existing file so async
     * artwork/lyrics updates are not lost.
     */
    fun writeSongMeta(
        context: Context,
        song: Song,
        localPath: String? = null,
        hlsOffline: Boolean = false,
        streamUrl: String? = null,
        downloadPending: Boolean = false,
        fileSizeBytes: Long? = null,
    ) {
        try {
            val existing = readMeta(context, song.videoId)
            val art = artFile(context, song.videoId)
            val lyrics = lyricsFile(context, song.videoId)
            val resolvedLocal = localPath?.takeIf { it.isNotBlank() }
                ?: song.localPath?.takeIf { it.isNotBlank() }
                ?: existing?.optString("localPath")?.takeIf { it.isNotBlank() }
            val json = JSONObject().apply {
                put("videoId", song.videoId)
                put("title", song.title)
                put("artist", song.artist)
                put("thumbnail", song.thumbnail)
                put("artworkUrl", song.artworkUrl ?: "")
                put("duration", song.duration ?: "")
                put("album", song.album ?: "")
                put("playlistId", song.playlistId ?: "")
                put("genre", song.genre ?: "")
                if (song.year != null) put("year", song.year) else remove("year")
                put("localPath", resolvedLocal ?: "")
                put("hlsOffline", hlsOffline)
                put("streamUrl", streamUrl?.takeIf { it.isNotBlank() } ?: song.streamUrl ?: "")
                put("downloadPending", downloadPending)
                put("isDownloaded", !downloadPending)
                val size = fileSizeBytes ?: song.fileSize
                if (size != null && size > 0L) put("fileSizeBytes", size)
                if (song.bitrate != null) put("bitrate", song.bitrate)
                song.lyrics?.takeIf { it.isNotBlank() }?.let { put("lyricsPlain", it) }
                if (art.isFile && art.length() > 0L) put("localArtPath", art.absolutePath)
                if (lyrics.isFile && lyrics.length() > 0L) {
                    put("lyricsCached", true)
                    put("lyricsPath", lyrics.absolutePath)
                } else {
                    put("lyricsCached", existing?.optBoolean("lyricsCached") == true)
                    existing?.optString("lyricsPath")?.takeIf { it.isNotBlank() }?.let { put("lyricsPath", it) }
                }
                val downloadedAt = existing?.optLong("downloadedAt", 0L)?.takeIf { it > 0L }
                    ?: System.currentTimeMillis()
                put("downloadedAt", downloadedAt)
                if (!downloadPending && resolvedLocal.isNullOrBlank() && !hlsOffline) {
                    put("completedAt", System.currentTimeMillis())
                } else if (!downloadPending) {
                    put("completedAt", System.currentTimeMillis())
                }
            }
            metaFile(context, song.videoId).writeText(json.toString(2))
        } catch (e: Exception) {
            Log.w(TAG, "writeSongMeta failed: ${e.message}")
        }
    }

    /** Build a [Song] from stored sidecar metadata (library scan / playback). */
    fun songFromStoredMeta(
        context: Context,
        videoId: String,
        localPathOverride: String? = null,
    ): Song? {
        val json = readMeta(context, videoId) ?: return null
        return songFromMetaJson(context, json, localPathOverride)
    }

    fun songFromMetaJson(
        context: Context,
        json: JSONObject,
        localPathOverride: String? = null,
    ): Song {
        val videoId = json.optString("videoId").ifBlank { "" }
        val diskArt = offlineArtworkPath(context, videoId)
            ?: json.optString("localArtPath").takeIf { it.isNotBlank() }
        val path = localPathOverride?.takeIf { it.isNotBlank() }
            ?: json.optString("localPath").takeIf { it.isNotBlank() }
        val year = json.optInt("year", 0).takeIf { it > 0 }
        return Song(
            videoId = videoId,
            title = json.optString("title").ifBlank { "Offline track" },
            artist = json.optString("artist").ifBlank { "Unknown artist" },
            thumbnail = diskArt ?: json.optString("thumbnail"),
            duration = json.optString("duration").takeIf { it.isNotBlank() },
            album = json.optString("album").takeIf { it.isNotBlank() },
            playlistId = json.optString("playlistId").takeIf { it.isNotBlank() },
            localPath = path,
            streamUrl = json.optString("streamUrl").takeIf { it.isNotBlank() },
            isDownloaded = json.optBoolean("isDownloaded", true) && !json.optBoolean("downloadPending"),
            fileSize = json.optLong("fileSizeBytes", 0L).takeIf { it > 0L },
            bitrate = json.optInt("bitrate", 0).takeIf { it > 0 },
            artworkUrl = diskArt ?: json.optString("artworkUrl").takeIf { it.isNotBlank() },
            lyrics = json.optString("lyricsPlain").takeIf { it.isNotBlank() },
            genre = json.optString("genre").takeIf { it.isNotBlank() },
            year = year,
        )
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
                        writeSongMeta(
                            context = context,
                            song = song,
                            localPath = song.localPath,
                            hlsOffline = readMeta(context, song.videoId)?.optBoolean("hlsOffline") == true,
                            streamUrl = readMeta(context, song.videoId)?.optString("streamUrl"),
                            downloadPending = false,
                            fileSizeBytes = song.fileSize,
                        )
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
                lyricsFile(context, song.videoId).writeText(arr.toString(2))
                writeSongMeta(
                    context = context,
                    song = song,
                    localPath = song.localPath,
                    hlsOffline = readMeta(context, song.videoId)?.optBoolean("hlsOffline") == true,
                    streamUrl = readMeta(context, song.videoId)?.optString("streamUrl"),
                    downloadPending = false,
                    fileSizeBytes = song.fileSize,
                )
            } catch (e: Exception) {
                Log.w(TAG, "persistLyrics ${song.videoId}: ${e.message}")
            }
        }
    }
}
