package com.foxymusic

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists queue and transport flags locally so sessions can survive process death.
 */
object PlaybackPersistence {

    private const val PREFS = "foxy_playback_state"
    private const val KEY_QUEUE = "queue_json"
    private const val KEY_INDEX = "queue_index"
    private const val KEY_SHUFFLE = "shuffle"
    private const val KEY_REPEAT = "repeat"
    private const val KEY_POSITION_MS = "position_ms"
    private const val KEY_HAS_SESSION = "has_session"

    fun saveSession(
        context: Context,
        queue: List<Song>,
        queueIndex: Int,
        shuffle: Boolean,
        repeatOrdinal: Int,
        positionMs: Long
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray()
        queue.forEach { arr.put(it.toPersistJson()) }
        prefs.edit()
            .putString(KEY_QUEUE, arr.toString())
            .putInt(KEY_INDEX, queueIndex.coerceAtLeast(0))
            .putBoolean(KEY_SHUFFLE, shuffle)
            .putInt(KEY_REPEAT, repeatOrdinal)
            .putLong(KEY_POSITION_MS, positionMs.coerceAtLeast(0))
            .putBoolean(KEY_HAS_SESSION, queue.isNotEmpty())
            .apply()
    }

    fun loadSession(context: Context): RestoredPlaybackSession? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_HAS_SESSION, false)) return null
        val raw = prefs.getString(KEY_QUEUE, null) ?: return null
        val arr = JSONArray(raw)
        val songs = buildList {
            for (i in 0 until arr.length()) {
                runCatching { add(arr.getJSONObject(i).toSong()) }
            }
        }
        if (songs.isEmpty()) return null
        val idx = prefs.getInt(KEY_INDEX, 0).coerceIn(0, songs.lastIndex)
        return RestoredPlaybackSession(
            queue = songs,
            queueIndex = idx,
            shuffle = prefs.getBoolean(KEY_SHUFFLE, false),
            repeatOrdinal = prefs.getInt(KEY_REPEAT, 0).coerceIn(0, 2),
            positionMs = prefs.getLong(KEY_POSITION_MS, 0L)
        )
    }

    fun clearSession(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}

data class RestoredPlaybackSession(
    val queue: List<Song>,
    val queueIndex: Int,
    val shuffle: Boolean,
    val repeatOrdinal: Int,
    val positionMs: Long
)

private fun Song.toPersistJson(): JSONObject = JSONObject().apply {
    put("videoId", videoId)
    put("title", title)
    put("artist", artist)
    put("thumbnail", thumbnail)
    put("duration", duration ?: JSONObject.NULL)
    put("album", album ?: JSONObject.NULL)
    put("artworkUrl", artworkUrl ?: JSONObject.NULL)
}

private fun JSONObject.toSong(): Song {
    fun optStr(key: String): String? =
        if (isNull(key)) null else optString(key).trim().takeIf { it.isNotEmpty() }
    return Song(
        videoId = getString("videoId"),
        title = optString("title"),
        artist = optString("artist"),
        thumbnail = optString("thumbnail"),
        duration = optStr("duration"),
        album = optStr("album"),
        artworkUrl = optStr("artworkUrl")
    )
}
