package com.foxymusic

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

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
    }

    fun toggleLike(song: Song) {
        val current = _state.value
        val liked = if (current.isLiked(song)) {
            current.likedSongs.filterNot { it.videoId == song.videoId }
        } else {
            listOf(song) + current.likedSongs.filterNot { it.videoId == song.videoId }
        }
        update(current.copy(likedSongs = liked))
    }

    fun toggleSaved(song: Song) {
        val current = _state.value
        val saved = if (current.isSaved(song)) {
            current.savedSongs.filterNot { it.videoId == song.videoId }
        } else {
            listOf(song) + current.savedSongs.filterNot { it.videoId == song.videoId }
        }
        update(current.copy(savedSongs = saved))
    }

    fun addHistory(song: Song) {
        val current = _state.value
        update(current.copy(history = (listOf(song) + current.history.filterNot { it.videoId == song.videoId }).take(80)))
    }

    fun download(song: Song) {
        val current = _state.value
        if (current.isDownloaded(song)) return
        _state.update { it.copy(downloadProgress = it.downloadProgress + (song.videoId to 0f)) }
        scope.launch {
            for (step in 1..10) {
                delay(180)
                _state.update { it.copy(downloadProgress = it.downloadProgress + (song.videoId to (step / 10f))) }
            }
            val next = _state.value.copy(
                downloadedSongs = listOf(song) + _state.value.downloadedSongs.filterNot { it.videoId == song.videoId },
                downloadProgress = _state.value.downloadProgress - song.videoId
            )
            update(next)
        }
    }

    fun removeDownload(song: Song) {
        val current = _state.value
        update(current.copy(downloadedSongs = current.downloadedSongs.filterNot { it.videoId == song.videoId }))
    }

    private fun update(next: FoxyLibraryState) {
        _state.value = next
        context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()
            ?.putString(LIKED, next.likedSongs.toJson())
            ?.putString(SAVED, next.savedSongs.toJson())
            ?.putString(DOWNLOADED, next.downloadedSongs.toJson())
            ?.putString(HISTORY, next.history.toJson())
            ?.apply()
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
                        thumbnail = item.optString("thumbnail").ifBlank {
                            item.optString("videoId").takeIf { id -> id.isNotBlank() }?.let { id ->
                                "https://i.ytimg.com/vi/$id/hqdefault.jpg"
                            }.orEmpty()
                        }
                    )
                )
            }
        }.filter { it.videoId.isNotBlank() }
    }.getOrDefault(emptyList())

    private fun List<Song>.toJson(): String {
        val array = JSONArray()
        forEach { song ->
            array.put(
                JSONObject()
                    .put("videoId", song.videoId)
                    .put("title", song.title)
                    .put("artist", song.artist)
                    .put("thumbnail", song.thumbnail)
            )
        }
        return array.toString()
    }
}
