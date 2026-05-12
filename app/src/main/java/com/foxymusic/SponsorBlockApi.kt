package com.foxymusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.util.concurrent.TimeUnit

/**
 * Fetches SponsorBlock skip segments (seconds). Categories align with common music clients.
 */
object SponsorBlockApi {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val categoriesJson = "[\"sponsor\",\"selfpromo\",\"interaction\",\"intro\",\"outro\",\"preview\",\"music_offtopic\"]"

    suspend fun fetchSkipRangesSeconds(videoId: String): List<Pair<Double, Double>> = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) return@withContext emptyList()
        runCatching {
            val url = "https://sponsor.ajay.app/api/skipSegments/$videoId".toHttpUrlOrNull()!!.newBuilder()
                .addQueryParameter("categories", categoriesJson)
                .build()
            val req = Request.Builder().url(url).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@runCatching emptyList()
                val body = resp.body?.string().orEmpty()
                val arr = JSONArray(body)
                val out = mutableListOf<Pair<Double, Double>>()
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val seg = o.optJSONArray("segment") ?: continue
                    if (seg.length() < 2) continue
                    val start = seg.optDouble(0, Double.NaN)
                    val end = seg.optDouble(1, Double.NaN)
                    if (!start.isNaN() && !end.isNaN() && end > start + 0.2) out += start to end
                }
                out.sortedBy { it.first }
            }
        }.getOrDefault(emptyList())
    }
}
