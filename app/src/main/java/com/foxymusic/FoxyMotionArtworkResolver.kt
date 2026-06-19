package com.foxymusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.math.abs

data class FoxyMotionArtwork(
    val staticUrl: String,
    val animatedUrl: String? = null,
    val animatedVerticalUrl: String? = null,
    val source: String,
    val confidence: Double,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "staticUrl" to staticUrl,
        "animatedUrl" to animatedUrl,
        "animatedVerticalUrl" to animatedVerticalUrl,
        "source" to source,
        "confidence" to confidence,
    )
}

/**
 * Foxy-native motion artwork resolver.
 *
 * This resolver keeps Foxy-owned artwork motion logic:
 * normalize the currently playing metadata, ask a catalog for richer artwork,
 * cache the answer, and always return a cheap static fallback when motion art
 * is unavailable.
 */
object FoxyMotionArtworkResolver {
    private const val CACHE_MAX = 256
    private const val CACHE_TTL_MS = 24 * 60 * 60 * 1000L

    private data class CacheEntry(
        val value: FoxyMotionArtwork?,
        val expiresAt: Long,
    )

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(14, TimeUnit.SECONDS)
        .build()

    private val cache = object : LinkedHashMap<String, CacheEntry>(CACHE_MAX, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CacheEntry>?): Boolean =
            size > CACHE_MAX
    }

    suspend fun resolve(song: Song): FoxyMotionArtwork? = withContext(Dispatchers.IO) {
        val title = cleanTitle(song.title)
        val artist = cleanArtist(song.artist)
        val fallback = song.highQualityArtworkUrl().takeIf { it.isNotBlank() }
        if (title.isBlank() || artist.isBlank()) {
            return@withContext fallback?.let {
                FoxyMotionArtwork(staticUrl = it, source = "Foxy fallback", confidence = 0.2)
            }
        }

        val key = "$title|$artist".lowercase(Locale.US)
        synchronized(cache) {
            cache[key]?.takeIf { it.expiresAt > System.currentTimeMillis() }?.let {
                return@withContext it.value ?: fallback?.let { url ->
                    FoxyMotionArtwork(staticUrl = url, source = "Foxy fallback", confidence = 0.2)
                }
            }
        }

        val resolved = resolveAppleCatalog(title, artist, song.album)
            ?: fallback?.let {
                FoxyMotionArtwork(staticUrl = it, source = "Foxy fallback", confidence = 0.2)
            }

        synchronized(cache) {
            cache[key] = CacheEntry(resolved, System.currentTimeMillis() + CACHE_TTL_MS)
        }
        resolved
    }

    private fun resolveAppleCatalog(
        title: String,
        artist: String,
        album: String?,
    ): FoxyMotionArtwork? {
        val term = URLEncoder.encode("$artist $title", "UTF-8")
        val url = "https://itunes.apple.com/search?term=$term&entity=song&limit=12"
        val request = Request.Builder()
            .url(url.toHttpUrl())
            .header("Accept", "application/json")
            .header("User-Agent", StreamExtractor.STREAM_USER_AGENT)
            .build()

        val body = client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return null
            response.body?.string().orEmpty()
        }
        val results = JSONObject(body).optJSONArray("results") ?: return null
        var bestScore = 0.0
        var bestUrl: String? = null
        for (i in 0 until results.length()) {
            val item = results.optJSONObject(i) ?: continue
            val track = item.optString("trackName")
            val itemArtist = item.optString("artistName")
            val collection = item.optString("collectionName")
            val artwork = item.optString("artworkUrl100").trim()
            if (artwork.isBlank()) continue
            val score = artworkScore(
                wantedTitle = title,
                wantedArtist = artist,
                wantedAlbum = album.orEmpty(),
                track = track,
                artist = itemArtist,
                album = collection,
            )
            if (score > bestScore) {
                bestScore = score
                bestUrl = upgradeAppleArtwork(artwork)
            }
        }
        val urlOut = bestUrl ?: return null
        if (bestScore < 0.62) return null
        return FoxyMotionArtwork(
            staticUrl = urlOut,
            animatedUrl = null,
            animatedVerticalUrl = null,
            source = "Apple catalog",
            confidence = bestScore.coerceIn(0.0, 1.0),
        )
    }

    private fun artworkScore(
        wantedTitle: String,
        wantedArtist: String,
        wantedAlbum: String,
        track: String,
        artist: String,
        album: String,
    ): Double {
        var score = 0.0
        val t = cleanTitle(track)
        val a = cleanArtist(artist)
        val al = cleanTitle(album)
        if (t == wantedTitle) score += 0.48
        else if (t.contains(wantedTitle) || wantedTitle.contains(t)) score += 0.26
        score += tokenOverlap(wantedTitle, t) * 0.22
        if (a == wantedArtist) score += 0.32
        else if (a.contains(wantedArtist) || wantedArtist.contains(a)) score += 0.18
        score += tokenOverlap(wantedArtist, a) * 0.14
        if (wantedAlbum.isNotBlank()) score += tokenOverlap(cleanTitle(wantedAlbum), al) * 0.08
        score -= abs(wantedTitle.length - t.length).coerceAtMost(24) / 300.0
        return score
    }

    private fun cleanTitle(value: String): String =
        value
            .lowercase(Locale.US)
            .replace(Regex("\\[[^]]*]"), " ")
            .replace(Regex("\\([^)]*(official|video|lyrics?|audio|visualizer|remaster|remix|live)[^)]*\\)"), " ")
            .replace(Regex("\\b(feat\\.?|ft\\.?|featuring)\\b.*$", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("[^a-z0-9]+"), " ")
            .trim()

    private fun cleanArtist(value: String): String =
        value
            .lowercase(Locale.US)
            .split(Regex("\\s*(,|&| x | feat\\.? | ft\\.? | featuring | with )\\s*", RegexOption.IGNORE_CASE))
            .firstOrNull()
            .orEmpty()
            .replace(Regex("[^a-z0-9]+"), " ")
            .trim()

    private fun tokenOverlap(left: String, right: String): Double {
        val a = left.split(' ').filter { it.length > 1 }.toSet()
        val b = right.split(' ').filter { it.length > 1 }.toSet()
        if (a.isEmpty() || b.isEmpty()) return 0.0
        return a.intersect(b).size.toDouble() / a.union(b).size.toDouble()
    }

    private fun upgradeAppleArtwork(url: String): String =
        url.replace(Regex("/\\d+x\\d+bb\\.(jpg|png|webp)$"), "/1200x1200bb.$1")
}
