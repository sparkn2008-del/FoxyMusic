package com.foxymusic

import android.media.MediaMetadataRetriever
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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

    /**
     * Increments on every [publish] so non-Compose consumers (e.g. [FoxyFlutterBridge]) can
     * observe library changes without [androidx.compose.runtime.snapshotFlow], which is not
     * safe when no Compose composition is active (Flutter-only host).
     */
    private val _notifyEpoch = MutableStateFlow(0L)
    val notifyEpoch: StateFlow<Long> = _notifyEpoch.asStateFlow()

    private var appContext: Context? = null

    /** All mutations hop to the main thread so Compose + Flutter reads stay consistent. */
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun publish(reducer: (FoxyLibraryState) -> FoxyLibraryState) {
        fun apply() {
            state.value = reducer(state.value)
            _notifyEpoch.value = _notifyEpoch.value + 1L
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            apply()
        } else {
            mainHandler.post { apply() }
        }
    }

    private fun downloadsRoot(context: Context) =
        File(context.getExternalFilesDir(null), "downloads")

    /**
     * Deletes progressive download files and sidecar meta for [videoId].
     * Flutter often omits [Song.localPath] in method maps, so we must not rely on it alone.
     */
    private fun deleteAllDownloadArtifactsOnDisk(context: Context, videoId: String) {
        val dir = downloadsRoot(context)
        if (!dir.isDirectory) return
        dir.listFiles()?.forEach { file ->
            if (!file.isFile) return@forEach
            if (file.name == "$videoId.foxy-meta.json") {
                file.delete()
                return@forEach
            }
            val ext = file.extension.lowercase()
            if (file.nameWithoutExtension == videoId && ext in mediaExtensions) {
                file.delete()
            }
        }
    }

    private fun metaFile(context: Context, videoId: String) =
        File(downloadsRoot(context), "$videoId.foxy-meta.json")

    private val mediaExtensions = setOf(
        "webm", "mp4", "m4a", "opus", "mp3", "media", "mkv", "aac", "ogg"
    )

    // ====================== Public API ======================

    fun setDownloadProgress(videoId: String, progress: Float) {
        val p = progress.coerceIn(0f, 1f)
        publish {
            it.copy(downloadProgress = it.downloadProgress + (videoId to p))
        }
    }

    fun clearDownloadProgress(videoId: String) {
        publish {
            it.copy(downloadProgress = it.downloadProgress - videoId)
        }
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        scope.launch {
            delay(80)
            refreshDownloadsFromDisk(context.applicationContext)
        }
    }

    /**
     * Rescan the downloads directory and replace [FoxyLibraryState.downloadedSongs].
     * Safe to call from any thread; disk IO runs on [Dispatchers.IO].
     */
    suspend fun refreshDownloadsFromDisk(context: Context) {
        publish { it.copy(isLoading = true) }
        val downloaded = withContext(Dispatchers.IO) {
            val downloadsDir = downloadsRoot(context)
            if (!downloadsDir.exists()) {
                emptyList()
            } else {
                downloadsDir.listFiles()
                    ?.mapNotNull { file -> songFromDownloadedFile(context, file) }
                    ?.distinctBy { it.videoId }
                    ?: emptyList()
            }
        }
        publish {
            it.copy(
                downloadedSongs = downloaded,
                isLoading = false
            )
        }
    }

    fun toggleLiked(song: Song) {
        publish { current ->
            val liked = current.likedSongs.any { it.videoId == song.videoId }
            val nextLiked =
                if (liked) current.likedSongs.filterNot { it.videoId == song.videoId }
                else current.likedSongs + song
            current.copy(likedSongs = nextLiked.distinctBy { it.videoId })
        }
    }

    fun isLiked(song: Song?): Boolean =
        song != null && state.value.likedSongs.any { it.videoId == song.videoId }

    fun addSong(song: Song) {
        publish { current ->
            val updatedList = current.allSongs + song.copy(isDownloaded = false)
            current.copy(allSongs = updatedList.distinctBy { it.videoId })
        }
    }

    fun addHistory(song: Song) {
        publish { current ->
            val nextHistory = (listOf(song) + current.historySongs)
                .distinctBy { it.videoId }
                .take(200)
            current.copy(historySongs = nextHistory)
        }
    }

    fun markAsDownloaded(song: Song, localPath: String) {
        val updatedSong = song.copy(
            localPath = localPath,
            isDownloaded = true,
            streamUrl = null
        )
        publish { current ->
            val newAllSongs = current.allSongs.map {
                if (it.videoId == song.videoId) updatedSong else it
            }
            val newDownloaded = (current.downloadedSongs + updatedSong)
                .distinctBy { it.videoId }
            current.copy(
                allSongs = newAllSongs,
                downloadedSongs = newDownloaded,
                downloadProgress = current.downloadProgress - song.videoId
            )
        }
        writeDownloadMeta(updatedSong)
    }

    fun removeDownload(song: Song, context: Context) {
        val videoId = song.videoId.trim()
        if (videoId.isNotBlank()) {
            deleteAllDownloadArtifactsOnDisk(context, videoId)
        }
        song.localPath?.let { path ->
            if (path.isNotBlank()) runCatching { File(path).delete() }
        }
        val updatedSong = song.copy(localPath = null, isDownloaded = false)
        publish { current ->
            current.copy(
                allSongs = current.allSongs.map {
                    if (it.videoId == song.videoId) updatedSong else it
                },
                downloadedSongs = current.downloadedSongs.filter { it.videoId != song.videoId },
                downloadProgress = current.downloadProgress - song.videoId
            )
        }
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

    private fun songFromEmbeddedTagsOrNull(file: File, videoId: String): Song? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(file.absolutePath)
            val title =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.trim().orEmpty()
            val artist =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)?.trim().orEmpty()
            val album =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)?.trim().orEmpty()
            val rawDur =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.trim().orEmpty()
            if (title.isBlank() && artist.isBlank()) {
                null
            } else {
                val thumb = "https://img.youtube.com/vi/$videoId/hqdefault.jpg"
                val song = Song(
                    videoId = videoId,
                    title = title.ifBlank { "Offline track" },
                    artist = artist.ifBlank { "Unknown artist" },
                    thumbnail = thumb,
                    duration = rawDur.takeIf { it.isNotBlank() },
                    album = album.takeIf { it.isNotBlank() },
                    localPath = file.absolutePath,
                    isDownloaded = true,
                    artworkUrl = "https://img.youtube.com/vi/$videoId/maxresdefault.jpg",
                    streamUrl = null
                )
                runCatching { writeDownloadMeta(song.copy(localPath = null)) }
                song
            }
        } catch (_: Exception) {
            null
        } finally {
            runCatching { r.release() }
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

        val fromTags = songFromEmbeddedTagsOrNull(file, videoId)
        if (fromTags != null) return fromTags

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

    // Helper to get local file path
    fun getLocalPath(context: Context, videoId: String): String {
        val dir = downloadsRoot(context)
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "$videoId.mp3").absolutePath
    }
}
