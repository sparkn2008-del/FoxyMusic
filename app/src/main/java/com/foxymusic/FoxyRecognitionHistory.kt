package com.foxymusic

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class FoxyRecognitionHistoryItem(
    val id: Long,
    val recognizedAt: Long,
    val result: FoxyRecognitionResult,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "recognizedAt" to recognizedAt,
        "result" to result.toMap(),
    )
}

object FoxyRecognitionHistory {
    private var context: Context? = null
    private val items = mutableListOf<FoxyRecognitionHistoryItem>()

    fun init(ctx: Context) {
        context = ctx.applicationContext
        loadLocked()
    }

    @Synchronized
    fun all(): List<FoxyRecognitionHistoryItem> = items.toList()

    @Synchronized
    fun add(result: FoxyRecognitionResult) {
        val now = System.currentTimeMillis()
        val top = items.firstOrNull()
        if (
            top != null &&
            top.result.title.equals(result.title, ignoreCase = true) &&
            top.result.artist.equals(result.artist, ignoreCase = true) &&
            now - top.recognizedAt < 15_000L
        ) {
            items[0] = top.copy(recognizedAt = now, result = result)
        } else {
            items.add(
                0,
                FoxyRecognitionHistoryItem(
                    id = now,
                    recognizedAt = now,
                    result = result,
                ),
            )
        }
        if (items.size > 100) items.subList(100, items.size).clear()
        saveLocked()
    }

    @Synchronized
    fun clear() {
        items.clear()
        saveLocked()
    }

    private fun file(): File {
        val dir = context!!.filesDir
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "recognition_history_v1.json")
    }

    @Synchronized
    private fun loadLocked() {
        items.clear()
        val ctx = context ?: return
        runCatching {
            val f = file()
            if (!f.exists() || f.length() <= 0L) return@runCatching
            val root = JSONArray(f.readText())
            for (i in 0 until root.length()) {
                val obj = root.optJSONObject(i) ?: continue
                val result = obj.optJSONObject("result")?.toRecognitionResult() ?: continue
                items.add(
                    FoxyRecognitionHistoryItem(
                        id = obj.optLong("id", System.currentTimeMillis() + i),
                        recognizedAt = obj.optLong("recognizedAt", System.currentTimeMillis()),
                        result = result,
                    ),
                )
            }
        }
    }

    @Synchronized
    private fun saveLocked() {
        context ?: return
        runCatching {
            val arr = JSONArray()
            for (item in items) {
                arr.put(
                    JSONObject().apply {
                        put("id", item.id)
                        put("recognizedAt", item.recognizedAt)
                        put("result", JSONObject(item.result.toMap()))
                    },
                )
            }
            file().writeText(arr.toString())
        }
    }
}

private fun JSONObject.toRecognitionResult(): FoxyRecognitionResult? {
    val title = optString("title").trim()
    if (title.isEmpty()) return null
    val lyrics = buildList {
        val arr = optJSONArray("lyrics")
        for (i in 0 until (arr?.length() ?: 0)) {
            arr?.optString(i)?.trim()?.takeIf { it.isNotEmpty() }?.let(::add)
        }
    }
    return FoxyRecognitionResult(
        trackId = optString("trackId").trim().ifEmpty { title },
        title = title,
        artist = optString("artist").trim(),
        album = optString("album").trim().ifEmpty { null },
        coverArtUrl = optString("coverArtUrl").trim().ifEmpty { null },
        coverArtHqUrl = optString("coverArtHqUrl").trim().ifEmpty { null },
        genre = optString("genre").trim().ifEmpty { null },
        releaseDate = optString("releaseDate").trim().ifEmpty { null },
        label = optString("label").trim().ifEmpty { null },
        lyrics = lyrics,
        shazamUrl = optString("shazamUrl").trim().ifEmpty { null },
        appleMusicUrl = optString("appleMusicUrl").trim().ifEmpty { null },
        spotifyUrl = optString("spotifyUrl").trim().ifEmpty { null },
        isrc = optString("isrc").trim().ifEmpty { null },
        youtubeVideoId = optString("youtubeVideoId").trim().ifEmpty { null },
    )
}
