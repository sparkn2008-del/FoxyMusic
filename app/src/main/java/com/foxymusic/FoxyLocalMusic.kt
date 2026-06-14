package com.foxymusic

import android.content.Context
import android.net.Uri
import android.media.MediaMetadataRetriever
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.UUID

object FoxyLocalMusic {
    private const val DIR_NAME = "local_music"
    private const val INDEX_NAME = "local_music.json"

    private val audioExtensions = setOf(
        "flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "alac", "webm",
    )

    fun dir(context: Context): File =
        File(context.getExternalFilesDir(null), DIR_NAME).apply { mkdirs() }

    private fun indexFile(context: Context): File =
        File(dir(context), INDEX_NAME)

    fun all(context: Context): List<Song> {
        val file = indexFile(context)
        if (!file.isFile || file.length() <= 0L) return emptyList()
        val arr = runCatching { JSONArray(file.readText()) }.getOrNull() ?: return emptyList()
        val out = ArrayList<Song>()
        for (i in 0 until arr.length()) {
            val song = arr.optJSONObject(i)?.toSong() ?: continue
            val path = song.localPath?.takeIf { it.isNotBlank() } ?: continue
            if (File(path).isFile) out += song
        }
        return out.distinctBy { it.videoId }
    }

    fun importUris(context: Context, uris: List<Uri>): Map<String, Any?> {
        val app = context.applicationContext
        val existing = all(app).toMutableList()
        val imported = ArrayList<Song>()
        for (uri in uris.distinct()) {
            val song = runCatching { importOne(app, uri, existing + imported) }.getOrNull()
            if (song != null) imported += song
        }
        if (imported.isNotEmpty()) {
            save(app, existing + imported)
            FoxyLibraryStore.setLocalSongs(existing + imported)
            FoxyBackup.requestAutoBackup(app)
        }
        return mapOf(
            "ok" to true,
            "imported" to imported.size,
        )
    }

    private fun importOne(context: Context, uri: Uri, existing: List<Song>): Song? {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri).orEmpty()
        val ext = extensionFor(uri, mime)
        if (ext !in audioExtensions) return null
        val id = "local_${UUID.randomUUID().toString().replace("-", "")}"
        val audioFile = File(dir(context), "$id.$ext")
        resolver.openInputStream(uri)?.use { input ->
            audioFile.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        if (!audioFile.isFile || audioFile.length() <= 0L) return null

        val meta = readMetadata(audioFile)
        val artPath = writeEmbeddedArtwork(context, id, meta.embeddedPicture)
        val title = meta.title.ifBlank { audioFile.nameWithoutExtension.replace('_', ' ') }
        val artist = meta.artist.ifBlank { "Local music" }
        val song = Song(
            videoId = id,
            title = title,
            artist = artist,
            thumbnail = artPath.orEmpty(),
            duration = meta.durationMs?.let { formatDuration(it) },
            album = meta.album.takeIf { it.isNotBlank() },
            localPath = audioFile.absolutePath,
            isDownloaded = false,
            fileSize = audioFile.length(),
            bitrate = meta.bitrate,
            artworkUrl = artPath,
            genre = meta.genre.takeIf { it.isNotBlank() },
            year = meta.year,
        )
        val duplicate = existing.firstOrNull {
            it.title.equals(song.title, true) && it.artist.equals(song.artist, true)
        }
        if (duplicate != null) {
            audioFile.delete()
            artPath?.let { runCatching { File(it).delete() } }
            return null
        }
        return song
    }

    private fun extensionFor(uri: Uri, mime: String): String {
        val pathExt = uri.lastPathSegment
            ?.substringAfterLast('.', "")
            ?.lowercase(Locale.US)
            ?.takeIf { it.isNotBlank() }
        if (pathExt in audioExtensions) return pathExt!!
        return when (mime.lowercase(Locale.US)) {
            "audio/flac", "audio/x-flac" -> "flac"
            "audio/mpeg" -> "mp3"
            "audio/mp4", "audio/x-m4a" -> "m4a"
            "audio/aac" -> "aac"
            "audio/ogg" -> "ogg"
            "audio/opus" -> "opus"
            "audio/wav", "audio/x-wav" -> "wav"
            "audio/webm" -> "webm"
            else -> "m4a"
        }
    }

    private data class LocalMeta(
        val title: String = "",
        val artist: String = "",
        val album: String = "",
        val durationMs: Long? = null,
        val bitrate: Int? = null,
        val genre: String = "",
        val year: Int? = null,
        val embeddedPicture: ByteArray? = null,
    )

    private fun readMetadata(file: File): LocalMeta {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(file.absolutePath)
            LocalMeta(
                title = r.meta(MediaMetadataRetriever.METADATA_KEY_TITLE),
                artist = r.meta(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                album = r.meta(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                durationMs = r.meta(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    .toLongOrNull()?.takeIf { it > 0L },
                bitrate = r.meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                    .toIntOrNull()?.takeIf { it > 0 },
                genre = r.meta(MediaMetadataRetriever.METADATA_KEY_GENRE),
                year = r.meta(MediaMetadataRetriever.METADATA_KEY_YEAR)
                    .take(4).toIntOrNull()?.takeIf { it > 0 },
                embeddedPicture = r.embeddedPicture,
            )
        } catch (_: Exception) {
            LocalMeta()
        } finally {
            runCatching { r.release() }
        }
    }

    private fun MediaMetadataRetriever.meta(key: Int): String =
        extractMetadata(key)?.trim().orEmpty()

    private fun writeEmbeddedArtwork(context: Context, id: String, bytes: ByteArray?): String? {
        if (bytes == null || bytes.isEmpty()) return null
        val f = File(dir(context), "$id.art.jpg")
        return runCatching {
            f.writeBytes(bytes)
            f.absolutePath
        }.getOrNull()
    }

    private fun save(context: Context, songs: List<Song>) {
        val arr = JSONArray()
        songs.distinctBy { it.videoId }.forEach { arr.put(it.toJson()) }
        indexFile(context).writeText(arr.toString(2))
    }

    private fun Song.toJson(): JSONObject = JSONObject().apply {
        put("videoId", videoId)
        put("title", title)
        put("artist", artist)
        put("thumbnail", thumbnail)
        put("duration", duration ?: "")
        put("album", album ?: "")
        put("localPath", localPath ?: "")
        put("fileSize", fileSize ?: 0L)
        put("bitrate", bitrate ?: 0)
        put("artworkUrl", artworkUrl ?: "")
        put("genre", genre ?: "")
        put("year", year ?: 0)
    }

    private fun JSONObject.toSong(): Song? {
        val id = optString("videoId").takeIf { it.isNotBlank() } ?: return null
        return Song(
            videoId = id,
            title = optString("title").ifBlank { "Local track" },
            artist = optString("artist").ifBlank { "Local music" },
            thumbnail = optString("thumbnail"),
            duration = optString("duration").takeIf { it.isNotBlank() },
            album = optString("album").takeIf { it.isNotBlank() },
            localPath = optString("localPath").takeIf { it.isNotBlank() },
            isDownloaded = false,
            fileSize = optLong("fileSize", 0L).takeIf { it > 0L },
            bitrate = optInt("bitrate", 0).takeIf { it > 0 },
            artworkUrl = optString("artworkUrl").takeIf { it.isNotBlank() },
            genre = optString("genre").takeIf { it.isNotBlank() },
            year = optInt("year", 0).takeIf { it > 0 },
        )
    }

    private fun formatDuration(ms: Long): String {
        val total = (ms / 1000L).coerceAtLeast(0L)
        val h = total / 3600L
        val m = (total % 3600L) / 60L
        val s = total % 60L
        return if (h > 0L) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }
}
