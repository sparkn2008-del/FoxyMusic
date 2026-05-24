package com.foxymusic

import android.media.MediaMetadataRetriever
import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
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

    private val _state = MutableStateFlow(FoxyLibraryState())
    val state: StateFlow<FoxyLibraryState> = _state.asStateFlow()

    /** Increments on every [publish] for Flutter bridge observers. */
    private val _notifyEpoch = MutableStateFlow(0L)
    val notifyEpoch: StateFlow<Long> = _notifyEpoch.asStateFlow()

    private var appContext: Context? = null

    /** All mutations hop to the main thread so Flutter reads stay consistent. */
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun publish(reducer: (FoxyLibraryState) -> FoxyLibraryState) {
        fun apply() {
            _state.value = reducer(_state.value)
            _notifyEpoch.value = _notifyEpoch.value + 1L
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            apply()
        } else {
            mainHandler.post { apply() }
        }
    }

    private fun downloadsRoot(context: Context) = FoxyDownloadsPaths.dir(context)

    /**
     * Deletes progressive download files and sidecar meta for [videoId].
     * Flutter often omits [Song.localPath] in method maps, so we must not rely on it alone.
     */
    private fun deleteAllDownloadArtifactsOnDisk(context: Context, videoId: String) {
        FoxyDownloadsPaths.deleteArtifactsForVideo(context, videoId)
    }

    private fun metaFile(context: Context, videoId: String) =
        FoxyDownloadsPaths.metaFile(context, videoId)

    private val mediaExtensions = FoxyDownloadsPaths.mediaExtensions

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
        val previous = state.value.downloadedSongs
        val downloaded = withContext(Dispatchers.IO) {
            val allFiles = FoxyDownloadsPaths.listDownloadFiles(context)
            val fromMedia = allFiles
                .mapNotNull { file -> songFromDownloadedFile(context, file) }
                .distinctBy { it.videoId }
            val fromMetaOnly = allFiles
                .filter { it.name.endsWith(".foxy-meta.json") }
                .mapNotNull { file ->
                    val videoId = file.name.removeSuffix(".foxy-meta.json")
                    if (videoId.isBlank()) return@mapNotNull null
                    val meta = FoxyOfflineBundle.readMeta(context, videoId)
                        ?: return@mapNotNull null
                    if (!meta.optBoolean("hlsOffline", false)) return@mapNotNull null
                    if (meta.optBoolean("downloadPending", false)) return@mapNotNull null
                    if (fromMedia.any { it.videoId == videoId }) return@mapNotNull null
                    FoxyOfflineBundle.songFromMetaJson(context, meta)
                }
            (fromMedia + fromMetaOnly + previous.filter { prev ->
                prev.isDownloaded && fromMedia.none { it.videoId == prev.videoId }
            }).distinctBy { it.videoId }
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
        appContext?.let { FoxyBackup.requestAutoBackup(it) }
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
        appContext?.let { FoxyBackup.requestAutoBackup(it) }
    }

    fun markAsDownloaded(song: Song, localPath: String?) {
        val updatedSong = song.copy(
            localPath = localPath?.takeIf { it.isNotBlank() },
            isDownloaded = true,
            streamUrl = song.streamUrl,
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
        // Disk metadata is owned by [FoxyOfflineBundle] — do not write a stripped meta file here.
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

    fun snapshotJson(): JSONObject {
        val current = state.value
        fun songsJson(songs: List<Song>): JSONArray {
            val arr = JSONArray()
            for (song in songs) arr.put(song.toBackupJson())
            return arr
        }
        return JSONObject().apply {
            put("liked", songsJson(current.likedSongs))
            put("history", songsJson(current.historySongs))
        }
    }

    fun restoreFromJson(root: JSONObject) {
        val liked = root.optJSONArray("liked").songsFromBackupJson()
        val history = root.optJSONArray("history").songsFromBackupJson().take(200)
        publish { current ->
            current.copy(
                likedSongs = liked.distinctBy { it.videoId },
                historySongs = history.distinctBy { it.videoId },
            )
        }
    }

    // ====================== Private ======================

    private fun readDownloadMeta(context: Context, videoId: String): Song? =
        FoxyOfflineBundle.songFromStoredMeta(context, videoId)

    private fun songFromEmbeddedTagsOrNull(context: Context, file: File, videoId: String): Song? {
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
                runCatching {
                    FoxyOfflineBundle.writeSongMeta(
                        context = context.applicationContext,
                        song = song,
                        localPath = file.absolutePath,
                        fileSizeBytes = file.length(),
                    )
                }
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

        val fromTags = songFromEmbeddedTagsOrNull(context, file, videoId)
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
