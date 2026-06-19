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

data class FoxySpotifyResolvedTrack(
    val song: Song,
    val score: Double,
    val label: String,
    val sourceTitle: String,
    val sourceArtist: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "song" to song.toBridgeMap(),
        "score" to score,
        "matchLabel" to label,
        "sourceTitle" to sourceTitle,
        "sourceArtist" to sourceArtist,
    )
}

/**
 * Spotify-like bridge using Foxy-owned public metadata matching.
 *
 * FoxyMusic remains YouTube/SoundCloud playback-first: Spotify data is treated
 * as metadata, then lazily resolved to the closest playable YT Music song.
 */
object FoxySpotifyResolver {
    private const val CACHE_MAX = 512
    private const val MIN_SCORE = 0.34

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(14, TimeUnit.SECONDS)
        .build()

    private val cache = object : LinkedHashMap<String, FoxySpotifyResolvedTrack>(CACHE_MAX, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, FoxySpotifyResolvedTrack>?): Boolean =
            size > CACHE_MAX
    }

    suspend fun resolve(
        spotifyUrl: String?,
        title: String?,
        artist: String?,
        durationMs: Long?,
    ): FoxySpotifyResolvedTrack? = withContext(Dispatchers.IO) {
        val metadata = resolveSourceMetadata(spotifyUrl, title, artist) ?: return@withContext null
        val key = "${metadata.title}|${metadata.artist}|${durationMs ?: 0}".lowercase(Locale.US)
        synchronized(cache) {
            cache[key]?.let { return@withContext it }
        }

        val query = listOf(metadata.title, metadata.artist)
            .filter { it.isNotBlank() }
            .joinToString(" ")
        val candidates = YTMusicApi.search(query).distinctBy { it.videoId }.take(24)
        val best = candidates
            .map { song -> song to matchScore(metadata.title, metadata.artist, durationMs, song) }
            .maxByOrNull { it.second }
            ?: return@withContext null

        if (best.second < MIN_SCORE) return@withContext null
        val resolved = FoxySpotifyResolvedTrack(
            song = best.first,
            score = best.second,
            label = when {
                best.second >= 0.78 -> "Strong match"
                best.second >= 0.54 -> "Good match"
                else -> "Best match"
            },
            sourceTitle = metadata.title,
            sourceArtist = metadata.artist,
        )
        synchronized(cache) {
            cache[key] = resolved
        }
        resolved
    }

    private data class SourceMetadata(val title: String, val artist: String)

    private fun resolveSourceMetadata(
        spotifyUrl: String?,
        title: String?,
        artist: String?,
    ): SourceMetadata? {
        val directTitle = title.orEmpty().trim()
        val directArtist = artist.orEmpty().trim()
        if (directTitle.isNotBlank() && directArtist.isNotBlank()) {
            return SourceMetadata(directTitle, directArtist)
        }

        val url = spotifyUrl.orEmpty().trim()
        if (!url.contains("open.spotify.com", ignoreCase = true)) return null
        val encoded = URLEncoder.encode(url, "UTF-8")
        val request = Request.Builder()
            .url("https://open.spotify.com/oembed?url=$encoded".toHttpUrl())
            .header("Accept", "application/json")
            .header("User-Agent", StreamExtractor.STREAM_USER_AGENT)
            .build()
        val body = client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return null
            response.body?.string().orEmpty()
        }
        val oembedTitle = JSONObject(body).optString("title").trim()
        return parseOembedTitle(oembedTitle)
    }

    private fun parseOembedTitle(raw: String): SourceMetadata? {
        if (raw.isBlank()) return null
        val normalized = raw
            .replace(" | Spotify", "", ignoreCase = true)
            .replace(Regex("\\s+"), " ")
            .trim()
        val bySplit = normalized.split(" by ", limit = 2)
        if (bySplit.size == 2) {
            return SourceMetadata(bySplit[0].trim(), bySplit[1].trim())
        }
        val dashSplit = normalized.split(" - ", limit = 2)
        if (dashSplit.size == 2) {
            return SourceMetadata(dashSplit[0].trim(), dashSplit[1].trim())
        }
        return SourceMetadata(normalized, "")
    }

    private fun matchScore(
        title: String,
        artist: String,
        durationMs: Long?,
        song: Song,
    ): Double {
        val targetTitle = normalize(title)
        val targetArtist = normalizeArtist(artist)
        val candidateTitle = normalize(song.title)
        val candidateArtist = normalizeArtist(song.artist)
        var score = 0.0

        if (candidateTitle == targetTitle) score += 0.42
        else if (candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle)) score += 0.24
        score += tokenOverlap(targetTitle, candidateTitle) * 0.24

        if (targetArtist.isNotBlank()) {
            if (candidateArtist == targetArtist) score += 0.25
            else if (candidateArtist.contains(targetArtist) || targetArtist.contains(candidateArtist)) score += 0.14
            score += tokenOverlap(targetArtist, candidateArtist) * 0.12
        }

        durationMs?.takeIf { it > 0 }?.let { target ->
            val candidateMs = parseDurationMs(song.duration)
            if (candidateMs != null) {
                val diff = abs(candidateMs - target)
                score += when {
                    diff <= 1500 -> 0.12
                    diff <= 5000 -> 0.08
                    diff <= 12000 -> 0.04
                    else -> -0.05
                }
            }
        }

        val blob = "${song.title} ${song.artist}".lowercase(Locale.US)
        if (blob.contains("karaoke") || blob.contains("cover")) score -= 0.12
        if (blob.contains("slowed") || blob.contains("sped up")) score -= 0.08
        if (blob.contains("lyrics") || blob.contains("visualizer")) score -= 0.04
        return score.coerceIn(0.0, 1.0)
    }

    private fun normalize(value: String): String =
        value
            .lowercase(Locale.US)
            .replace(Regex("\\[[^]]*]"), " ")
            .replace(Regex("\\([^)]*(official|video|lyrics?|audio|visualizer|remaster|remix|live)[^)]*\\)"), " ")
            .replace(Regex("[^a-z0-9]+"), " ")
            .trim()

    private fun normalizeArtist(value: String): String =
        normalize(value)
            .split(Regex("\\s+(feat|ft|featuring|with|x)\\s+"))
            .firstOrNull()
            .orEmpty()
            .trim()

    private fun tokenOverlap(left: String, right: String): Double {
        val a = left.split(' ').filter { it.length > 1 }.toSet()
        val b = right.split(' ').filter { it.length > 1 }.toSet()
        if (a.isEmpty() || b.isEmpty()) return 0.0
        return a.intersect(b).size.toDouble() / a.union(b).size.toDouble()
    }

    private fun parseDurationMs(raw: String?): Long? {
        val parts = raw?.split(':')?.mapNotNull { it.toLongOrNull() } ?: return null
        if (parts.isEmpty()) return null
        val seconds = when (parts.size) {
            1 -> parts[0]
            2 -> parts[0] * 60 + parts[1]
            else -> parts.takeLast(3).let { it[0] * 3600 + it[1] * 60 + it[2] }
        }
        return seconds * 1000
    }
}

private fun Song.toBridgeMap(): Map<String, Any?> = mapOf(
    "videoId" to videoId,
    "title" to title,
    "artist" to artist,
    "thumbnail" to highQualityArtworkUrl(),
    "artworkUrl" to highQualityArtworkUrl(),
    "duration" to duration,
    "album" to album,
)
