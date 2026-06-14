package com.foxymusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

data class LyricLine(val timeMs: Long, val text: String)

object LyricsRepository {

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .build()
    private val memoryCache = ConcurrentHashMap<String, List<LyricLine>>()

    suspend fun fetchSyncedLines(song: Song): List<LyricLine> = withContext(Dispatchers.IO) {
        val preferLrclib = FoxySettings.state.value.lyricsPreferLrclib
        val key = "${song.videoId}|${song.title}|${song.artist}|$preferLrclib".lowercase()
        memoryCache[key]?.let { return@withContext it }
        val lines = if (preferLrclib) {
            fetchSimpMusic(song).takeIf { it.isNotEmpty() }
                ?: fetchLrclib(song).takeIf { it.isNotEmpty() }
                ?: fetchYoutubeTranscript(song.videoId)
        } else {
            fetchYoutubeTranscript(song.videoId).takeIf { it.isNotEmpty() }
                ?: fetchSimpMusic(song).takeIf { it.isNotEmpty() }
                ?: fetchLrclib(song)
        }
        if (lines.isNotEmpty()) {
            if (memoryCache.size > 64) memoryCache.clear()
            memoryCache[key] = lines
        }
        lines
    }

    private fun fetchLrclib(song: Song): List<LyricLine> = runCatching {
        val dur = song.parsedDurationSeconds()
        val artistEnc = URLEncoder.encode(song.artist, Charsets.UTF_8.name())
        val trackEnc = URLEncoder.encode(song.title, Charsets.UTF_8.name())
        val urlStr = buildString {
            append("https://lrclib.net/api/get?artist_name=").append(artistEnc)
            append("&track_name=").append(trackEnc)
            dur?.let { append("&duration=").append(it) }
        }
        get(urlStr)?.let { body ->
            val json = JSONObject(body)
            json.optString("syncedLyrics").takeIf { it.isNotBlank() }?.let { return@runCatching parseLrc(it) }
        }
        val q = URLEncoder.encode("${song.artist} ${song.title}".trim(), Charsets.UTF_8.name())
        get("https://lrclib.net/api/search?q=$q")?.let { body ->
            val arr = JSONArray(body)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val synced = o.optString("syncedLyrics")
                if (synced.isNotBlank()) return@runCatching parseLrc(synced)
            }
        }
        emptyList()
    }.getOrDefault(emptyList())

    private fun fetchYoutubeTranscript(videoId: String): List<LyricLine> = runCatching {
        val url = "https://video.google.com/timedtext?fmt=srv3&lang=en&v=$videoId"
        val body = get(url) ?: return@runCatching emptyList()
        parseSrv3Xml(body)
    }.getOrDefault(emptyList())

    private fun fetchSimpMusic(song: Song): List<LyricLine> = runCatching {
        val videoId = song.videoId.trim()
        if (videoId.isBlank()) return@runCatching emptyList()
        val body = get("https://api-lyrics.simpmusic.org/v1/$videoId")
            ?: return@runCatching emptyList()
        val root = JSONObject(body)
        if (!root.optBoolean("success", false)) return@runCatching emptyList()
        val data = root.optJSONArray("data") ?: return@runCatching emptyList()
        val duration = song.parsedDurationSeconds()
        var bestLines = emptyList<LyricLine>()
        var bestScore = Int.MAX_VALUE
        for (i in 0 until data.length()) {
            val item = data.optJSONObject(i) ?: continue
            val synced = item.optString("syncedLyrics").trim()
            if (synced.isBlank()) continue
            val lines = parseLrc(synced)
            if (lines.isEmpty()) continue
            val itemDuration = item.optInt("duration", -1)
            val score = if (duration != null && itemDuration > 0) {
                kotlin.math.abs(itemDuration - duration)
            } else {
                i
            }
            if (score < bestScore) {
                bestScore = score
                bestLines = lines
            }
        }
        bestLines
    }.getOrDefault(emptyList())

    private fun get(url: String): String? {
        val httpUrl = url.toHttpUrlOrNull() ?: return null
        val req = Request.Builder().url(httpUrl).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return null
            return resp.body?.string()
        }
    }

    private val lrcLine = Pattern.compile("^\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{2,3}))?]\\s*(.*)$")

    fun parseLrc(raw: String): List<LyricLine> {
        val out = mutableListOf<LyricLine>()
        raw.lineSequence().forEach { line ->
            val m = lrcLine.matcher(line.trim())
            if (!m.matches()) return@forEach
            val min = m.group(1)?.toLongOrNull() ?: return@forEach
            val sec = m.group(2)?.toLongOrNull() ?: return@forEach
            val frac = m.group(3)?.let { f ->
                when (f.length) {
                    2 -> f.toLong() * 10
                    3 -> f.toLong()
                    else -> f.toLong() * 10
                }
            } ?: 0L
            val text = m.group(4)?.trim().orEmpty()
            if (text.isBlank()) return@forEach
            val ms = min * 60_000 + sec * 1000 + frac.coerceAtMost(999)
            out += LyricLine(ms, text)
        }
        return out.sortedBy { it.timeMs }
    }

    private fun parseSrv3Xml(xml: String): List<LyricLine> {
        val re = Regex("""<text\s+start="([\d.]+)"(?:\s+dur="([\d.]+)")?[^>]*>([^<]*)</text>""")
        return re.findAll(xml).mapNotNull { match ->
            val start = match.groupValues[1].toDoubleOrNull() ?: return@mapNotNull null
            val raw = match.groupValues.getOrNull(3).orEmpty()
            val clean = android.text.Html.fromHtml(raw, android.text.Html.FROM_HTML_MODE_LEGACY).toString().trim()
            if (clean.isBlank()) return@mapNotNull null
            LyricLine((start * 1000).toLong(), clean)
        }.sortedBy { it.timeMs }.toList()
    }
}

internal fun Song.parsedDurationSeconds(): Int? {
    val d = duration ?: return null
    val parts = d.split(":").mapNotNull { it.trim().toIntOrNull() }
    return when (parts.size) {
        1 -> parts[0]
        2 -> parts[0] * 60 + parts[1]
        3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
        else -> null
    }
}
