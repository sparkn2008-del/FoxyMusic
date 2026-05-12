package com.foxymusic

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Environment
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class FoxyLibraryState(
    val likedSongs: List<Song> = emptyList(),
    val savedSongs: List<Song> = emptyList(),
    val downloadedSongs: List<Song> = emptyList(),
    val history: List<Song> = emptyList(),
    val downloadProgress: Map<String, Float> = emptyMap()
) {
    fun isLiked(song: Song?): Boolean = song != null && likedSongs.any { it.videoId == song.videoId }
    fun isSaved(song: Song?): Boolean = song != null && savedSongs.any { it.videoId == song.videoId }
    fun isDownloaded(song: Song?): Boolean = song != null && downloadedSongs.any { it.videoId == song.videoId }
}

object FoxyLibraryStore {
    private const val PREFS = "foxy_library"
    private const val LIKED = "liked"
    private const val SAVED = "saved"
    private const val DOWNLOADED = "downloaded"
    private const val HISTORY = "history"

    private var context: Context? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state = MutableStateFlow(FoxyLibraryState())
    val state: StateFlow<FoxyLibraryState> = _state

    fun init(appContext: Context) {
        context = appContext.applicationContext
        val prefs = context!!.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        _state.value = FoxyLibraryState(
            likedSongs = prefs.getString(LIKED, "[]").orEmpty().toSongs(),
            savedSongs = prefs.getString(SAVED, "[]").orEmpty().toSongs(),
            downloadedSongs = prefs.getString(DOWNLOADED, "[]").orEmpty().toSongs(),
            history = prefs.getString(HISTORY, "[]").orEmpty().toSongs()
        )

        // Register download complete receiver
        ContextCompat.registerReceiver(
            context!!,
            object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {}
            },
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    // ====================== DOWNLOAD SYSTEM ======================

    fun downloadSong(context: Context, song: Song) {
        if (isDownloaded(song)) return

        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

        val safeTitle = song.title.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val fileName = "$safeTitle.mp3"

        val downloadsDir = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "FoxyMusic")
        if (!downloadsDir.exists()) downloadsDir.mkdirs()

        val destinationFile = File(downloadsDir, fileName)

        val uri = Uri.parse(song.streamUrl ?: return)

        val request = DownloadManager.Request(uri)
            .setTitle(song.title)
            .setDescription("Downloading • ${song.artist}")
            .setDestinationUri(Uri.fromFile(destinationFile))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI or DownloadManager.Request.NETWORK_MOBILE)

        downloadManager.enqueue(request)

        // Show progress
        _state.update { it.copy(downloadProgress = it.downloadProgress + (song.videoId to 0f)) }

        // Fake smooth progress
        scope.launch {
            for (progress in 10..100 step 12) {
                delay(160)
                _state.update {
                    it.copy(downloadProgress = it.downloadProgress + (song.videoId to progress / 100f))
                }
            }

            val downloadedSong = song.copy(localPath = destinationFile.absolutePath)
            val current = _state.value
            val updatedDownloads = listOf(downloadedSong) + current.downloadedSongs.filterNot { it.videoId == song.videoId }

            update(current.copy(
                downloadedSongs = updatedDownloads,
                downloadProgress = current.downloadProgress - song.videoId
            ))
        }
    }

    fun removeDownload(song: Song) {
        song.localPath?.let { path ->
            File(path).delete()
        }
        val current = _state.value
        val updated = current.downloadedSongs.filterNot { it.videoId == song.videoId }
        update(current.copy(downloadedSongs = updated))
    }

    // ====================== LIBRARY FUNCTIONS ======================

    fun toggleLike(song: Song) {
        val current = _state.value
        val newList = if (current.isLiked(song)) {
            current.likedSongs.filterNot { it.videoId == song.videoId }
        } else {
            listOf(song) + current.likedSongs.filterNot { it.videoId == song.videoId }
        }
        update(current.copy(likedSongs = newList))
    }

    fun toggleSaved(song: Song) {
        val current = _state.value
        val newList = if (current.isSaved(song)) {
            current.savedSongs.filterNot { it.videoId == song.videoId }
        } else {
            listOf(song) + current.savedSongs.filterNot { it.videoId == song.videoId }
        }
        update(current.copy(savedSongs = newList))
    }

    fun addHistory(song: Song) {
        val current = _state.value
        val newHistory = (listOf(song) + current.history.filterNot { it.videoId == song.videoId }).take(80)
        update(current.copy(history = newHistory))
    }

    // ====================== PRIVATE HELPERS ======================

    private fun update(next: FoxyLibraryState) {
        _state.value = next
        context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()?.apply {
            putString(LIKED, next.likedSongs.toJson())
            putString(SAVED, next.savedSongs.toJson())
            putString(DOWNLOADED, next.downloadedSongs.toJson())
            putString(HISTORY, next.history.toJson())
            apply()
        }
    }

    private fun String.toSongs(): List<Song> = runCatching {
        val array = JSONArray(this)
        buildList {
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                add(
                    Song(
                        videoId = item.optString("videoId"),
                        title = item.optString("title"),
                        artist = item.optString("artist"),
                        thumbnail = item.optString("thumbnail"),
                        localPath = item.optString("localPath").takeIf { it.isNotBlank() }
                    )
                )
            }
        }.filter { it.videoId.isNotBlank() }
    }.getOrDefault(emptyList())

    private fun List<Song>.toJson(): String {
        val array = JSONArray()
        forEach { song ->
            array.put(
                JSONObject().apply {
                    put("videoId", song.videoId)
                    put("title", song.title)
                    put("artist", song.artist)
                    put("thumbnail", song.thumbnail)
                    if (!song.localPath.isNullOrBlank()) put("localPath", song.localPath)
                }
            )
        }
        return array.toString()
    }
}