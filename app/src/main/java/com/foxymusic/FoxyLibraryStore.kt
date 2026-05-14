package com.foxymusic

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File

data class FoxyLibraryState(
    val allSongs: List<Song> = emptyList(),
    val downloadedSongs: List<Song> = emptyList(),
    val historySongs: List<Song> = emptyList(),
    val likedSongs: List<Song> = emptyList(),
    val savedSongs: List<Song> = emptyList(),
    val downloadProgress: Map<String, Float> = emptyMap(),
    val isLoading: Boolean = false
) {
    fun isDownloaded(song: Song?): Boolean {
        if (song == null) return false
        return downloadedSongs.any { it.videoId == song.videoId } ||
            song.isDownloaded ||
            !song.localPath.isNullOrBlank()
    }

    fun getSongById(videoId: String): Song? {
        return allSongs.find { it.videoId == videoId }
            ?: downloadedSongs.find { it.videoId == videoId }
    }
}

object FoxyLibraryStore {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    val state = mutableStateOf(FoxyLibraryState())

    private var appContext: Context? = null

    private fun downloadsRoot(context: Context) =
        File(context.getExternalFilesDir(null), "downloads")

    private fun metaFile(context: Context, videoId: String) =
        File(downloadsRoot(context), "$videoId.foxy-meta.json")

    private val mediaExtensions = setOf(
        "webm", "mp4", "m4a", "opus", "mp3", "media", "mkv", "aac", "ogg"
    )

    // ====================== Public API ======================

    fun setDownloadProgress(videoId: String, progress: Float) {
        val p = progress.coerceIn(0f, 1f)
        state.value = state.value.copy(
            downloadProgress = state.value.downloadProgress + (videoId to p)
        )
    }

    fun clearDownloadProgress(videoId: String) {
        state.value = state.value.copy(
            downloadProgress = state.value.downloadProgress - videoId
        )
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        scope.launch {
            loadDownloadedSongs(context.applicationContext)
        }
    }

    fun toggleLiked(song: Song) {
        val current = state.value
        val liked = current.likedSongs.any { it.videoId == song.videoId }
        val nextLiked =
            if (liked) current.likedSongs.filterNot { it.videoId == song.videoId }
            else current.likedSongs + song
        state.value = current.copy(likedSongs = nextLiked.distinctBy { it.videoId })
    }

    fun isLiked(song: Song?): Boolean =
        song != null && state.value.likedSongs.any { it.videoId == song.videoId }

    fun addSong(song: Song) {
        val current = state.value
        val updatedList = current.allSongs + song.copy(isDownloaded = false)

        state.value = current.copy(
            allSongs = updatedList.distinctBy { it.videoId }
        )
    }

    fun addHistory(song: Song) {
        val current = state.value
        val nextHistory = (listOf(song) + current.historySongs)
            .distinctBy { it.videoId }
            .take(200)
        state.value = current.copy(historySongs = nextHistory)
    }

    fun markAsDownloaded(song: Song, localPath: String) {
        val current = state.value

        val updatedSong = song.copy(
            localPath = localPath,
            isDownloaded = true,
            streamUrl = null
        )

        val newAllSongs = current.allSongs.map {
            if (it.videoId == song.videoId) updatedSong else it
        }

        val newDownloaded = (current.downloadedSongs + updatedSong)
            .distinctBy { it.videoId }

        state.value = current.copy(
            allSongs = newAllSongs,
            downloadedSongs = newDownloaded,
            downloadProgress = current.downloadProgress - song.videoId
        )
        writeDownloadMeta(updatedSong)
    }

    fun removeDownload(song: Song, context: Context) {
        val current = state.value
        val file = song.localPath?.let { File(it) }

        file?.delete()
        runCatching { metaFile(context, song.videoId).delete() }

        val updatedSong = song.copy(localPath = null, isDownloaded = false)

        state.value = current.copy(
            allSongs = current.allSongs.map {
                if (it.videoId == song.videoId) updatedSong else it
            },
            downloadedSongs = current.downloadedSongs.filter { it.videoId != song.videoId },
            downloadProgress = current.downloadProgress - song.videoId
        )
    }

    fun isDownloaded(song: Song?): Boolean = state.value.isDownloaded(song)

    // ====================== Private ======================

    private fun writeDownloadMeta(song: Song) {
        val ctx = appContext ?: return
        try {
            val json = JSONObject().apply {
                put("videoId", song.videoId)
                put("title", song.title)
                put("artist", song.artist)
                put("thumbnail", song.thumbnail)
                put("artworkUrl", song.artworkUrl ?: "")
                put("duration", song.duration ?: "")
                put("album", song.album ?: "")
            }
            metaFile(ctx, song.videoId).writeText(json.toString())
        } catch (_: Exception) {
        }
    }

    private fun readDownloadMeta(context: Context, videoId: String): Song? {
        val f = metaFile(context, videoId)
        if (!f.exists() || f.length() <= 0L) return null
        return try {
            val json = JSONObject(f.readText())
            Song(
                videoId = json.optString("videoId", videoId),
                title = json.optString("title").ifBlank { "Offline track" },
                artist = json.optString("artist").ifBlank { "Unknown artist" },
                thumbnail = json.optString("thumbnail"),
                duration = json.optString("duration").takeIf { it.isNotBlank() },
                album = json.optString("album").takeIf { it.isNotBlank() },
                localPath = null,
                isDownloaded = true,
                artworkUrl = json.optString("artworkUrl").takeIf { it.isNotBlank() }
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun songFromDownloadedFile(context: Context, file: File): Song? {
        if (!file.isFile || file.length() <= 0L) return null
        val name = file.name
        if (name.endsWith(".foxy-meta.json")) return null
        val ext = file.extension.lowercase()
        if (ext !in mediaExtensions) return null
        val videoId = file.nameWithoutExtension
        if (videoId.isBlank()) return null

        val fromMeta = readDownloadMeta(context, videoId)?.copy(
            localPath = file.absolutePath,
            isDownloaded = true
        )
        if (fromMeta != null) return fromMeta

        val thumb = "https://img.youtube.com/vi/$videoId/hqdefault.jpg"
        return Song(
            videoId = videoId,
            title = "Offline track",
            artist = "YouTube Music",
            thumbnail = thumb,
            artworkUrl = "https://img.youtube.com/vi/$videoId/maxresdefault.jpg",
            localPath = file.absolutePath,
            isDownloaded = true
        )
    }

    private suspend fun loadDownloadedSongs(context: Context) {
        state.value = state.value.copy(isLoading = true)
        delay(300) // small delay for smooth UX

        val downloadsDir = downloadsRoot(context)
        if (!downloadsDir.exists()) {
            state.value = state.value.copy(isLoading = false)
            return
        }

        val downloaded = downloadsDir.listFiles()
            ?.mapNotNull { file -> songFromDownloadedFile(context, file) }
            ?.distinctBy { it.videoId }
            ?: emptyList()

        state.value = state.value.copy(
            downloadedSongs = downloaded,
            isLoading = false
        )
    }

    // Helper to get local file path
    fun getLocalPath(context: Context, videoId: String): String {
        val dir = downloadsRoot(context)
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "$videoId.mp3").absolutePath
    }
}
