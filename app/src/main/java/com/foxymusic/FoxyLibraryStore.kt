package com.foxymusic

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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

    // ====================== Public API ======================

    fun init(context: Context) {
        scope.launch {
            loadDownloadedSongs(context)
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
            downloadedSongs = newDownloaded
        )
    }

    fun removeDownload(song: Song, context: Context) {
        val current = state.value
        val file = song.localPath?.let { File(it) }

        file?.delete()

        val updatedSong = song.copy(localPath = null, isDownloaded = false)

        state.value = current.copy(
            allSongs = current.allSongs.map { 
                if (it.videoId == song.videoId) updatedSong else it 
            },
            downloadedSongs = current.downloadedSongs.filter { it.videoId != song.videoId }
        )
    }

    fun isDownloaded(song: Song?): Boolean = state.value.isDownloaded(song)

    // ====================== Private ======================

    private suspend fun loadDownloadedSongs(context: Context) {
        state.value = state.value.copy(isLoading = true)
        delay(300) // small delay for smooth UX

        val downloadsDir = File(context.getExternalFilesDir(null), "downloads")
        if (!downloadsDir.exists()) {
            state.value = state.value.copy(isLoading = false)
            return
        }

        val downloaded = downloadsDir.listFiles()?.mapNotNull { file ->
            val videoId = file.nameWithoutExtension
            if (file.length() > 0) {
                Song(
                    videoId = videoId,
                    title = "Downloaded Song",
                    artist = "Local",
                    localPath = file.absolutePath,
                    isDownloaded = true
                )
            } else null
        } ?: emptyList()

        state.value = state.value.copy(
            downloadedSongs = downloaded,
            isLoading = false
        )
    }

    // Helper to get local file path
    fun getLocalPath(context: Context, videoId: String): String {
        val dir = File(context.getExternalFilesDir(null), "downloads")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "$videoId.mp3").absolutePath
    }
}