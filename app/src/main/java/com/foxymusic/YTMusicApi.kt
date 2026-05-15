package com.foxymusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.TimeUnit

data class RecommendationSection(
    val title: String,
    val songs: List<Song>
)

data class AccountInfo(
    val name: String,
    val email: String,
    val avatarUrl: String
)

object YTMusicApi {

    private const val apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private const val baseUrl = "https://music.youtube.com/youtubei/v1"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    private val headers = Headers.Builder()
        .add("Accept", "application/json")
        .add("Content-Type", "application/json")
        .add("Origin", "https://music.youtube.com")
        .add("Referer", "https://music.youtube.com/")
        .add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        .add("X-YouTube-Client-Name", "67")
        .add("X-YouTube-Client-Version", "1.20250401.01.00")
        .build()

    private const val filterSongs = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
    private const val filterVideos = "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"

    // ====================== PUBLIC API ======================

    suspend fun homeRecommendations(): List<RecommendationSection> {
        val json = post("browse", JSONObject().apply {
            put("context", clientContext())
            put("browseId", "FEmusic_home")
        }) ?: return fallbackSections()

        return parseSections(json).ifEmpty { fallbackSections() }
    }

    /** YouTube Music charts browse + text fallbacks for richer Home. */
    suspend fun chartsSections(): List<RecommendationSection> {
        val json = post("browse", JSONObject().apply {
            put("context", clientContext())
            put("browseId", "FEmusic_charts")
        })
        if (json != null) {
            val parsed = parseSections(json)
            if (parsed.isNotEmpty()) return parsed.take(8)
        }
        return listOf(
            RecommendationSection("Charting now", search("billboard hot 100 songs").take(14)),
            RecommendationSection("Trending worldwide", search("trending songs global").take(14))
        ).filter { it.songs.isNotEmpty() }
    }

    suspend fun search(query: String, filter: String? = filterSongs): List<Song> {
        if (query.isBlank()) return emptyList()

        val json = post("search", JSONObject().apply {
            put("context", clientContext())
            put("query", query)
            filter?.takeIf { it.isNotBlank() }?.let { put("params", it) }
        }) ?: return emptyList()

        return parseSongs(json)
            .distinctBy { it.videoId }
            .take(60)
    }

    suspend fun getMoodMix(mood: String): List<Song> {
        val query = when (mood.lowercase()) {
            "energize", "workout" -> "energizing workout music"
            "focus" -> "focus music"
            "late night" -> "late night chill music"
            "romance" -> "romantic songs"
            "chill" -> "chill hits"
            else -> "$mood music"
        }
        return search(query).take(40)
    }

    suspend fun videos(query: String): List<Song> = search(query, filterVideos)

    /**
     * YouTube Music–style station: prefer **genre / mood** discovery over the literal
     * `"title artist radio"` search (which floods the queue with the same upload under many names).
     * Uses [next] for official “up next” suggestions, but filters near-duplicate titles and blends
     * broad station queries (phonk, slowed, artist radio, etc.).
     */
    suspend fun radio(seed: Song): List<Song> {
        val out = LinkedHashMap<String, Song>()
        fun put(s: Song) {
            if (s.videoId == seed.videoId) return
            if (isLikelySameTrackDifferentUpload(s, seed)) return
            out.putIfAbsent(s.videoId, s)
        }

        // 1) Broad station searches first so the queue is not 40× the same keyword hit.
        for (q in stationSearchQueries(seed)) {
            if (out.size >= 56) break
            search(q).forEach(::put)
        }

        // 2) Innertube “next” panel — often good, but can be remix-heavy; filter + merge.
        next(seed.videoId).forEach(::put)

        // 3) Last-resort: artist-scoped radio (still not the literal full title string).
        if (out.size < 14) {
            val a = seed.artist.substringBefore("feat.").substringBefore("ft.").trim()
            if (a.isNotBlank() &&
                !a.equals("YouTube Music", ignoreCase = true) &&
                !a.equals("Unknown artist", ignoreCase = true)
            ) {
                search("$a music mix").forEach(::put)
            }
        }

        return out.values.take(50)
    }

    suspend fun next(videoId: String): List<Song> {
        val json = post("next", JSONObject().apply {
            put("context", clientContext())
            put("enablePersistentPlaylistPanel", true)
            put("isAudioOnly", true)
            put("tunerSettingValue", "AUTOMIX_SETTING_NORMAL")
            put("watchEndpoint", JSONObject().put("videoId", videoId))
        }) ?: return emptyList()

        return parseSongs(json).distinctBy { it.videoId }
    }

    suspend fun lyrics(videoId: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url("https://video.google.com/timedtext?fmt=srv3&lang=en&v=$videoId")
                .headers(headers)
                .get()
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null

                response.body?.string()
                    ?.replace(Regex("<[^>]+>"), "\n")
                    ?.replace("&amp;", "&")
                    ?.replace("&quot;", "\"")
                    ?.replace("&#39;", "'")
                    ?.let { URLDecoder.decode(it, "UTF-8") }
                    ?.lines()
                    ?.map { it.trim() }
                    ?.filter { it.isNotBlank() }
                    ?.distinct()
                    ?.joinToString("\n")
                    ?.takeIf { it.isNotBlank() }
            }
        }.getOrNull()
    }

    suspend fun accountInfo(): AccountInfo = AccountInfo(
        name = FoxyAccount.state.value.displayName,
        email = FoxyAccount.state.value.email,
        avatarUrl = FoxyAccount.state.value.avatarUrl
    )

    // ====================== PRIVATE HELPERS ======================

    private suspend fun post(endpoint: String, payload: JSONObject): JSONObject? = withContext(Dispatchers.IO) {
        runCatching {
            val body = payload.toString().toRequestBody("application/json".toMediaType())

            val request = Request.Builder()
                .url("$baseUrl/$endpoint?key=$apiKey&prettyPrint=false")
                .headers(headers)
                .post(body)
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                JSONObject(response.body?.string().orEmpty())
            }
        }.getOrNull()
    }

    private fun clientContext(): JSONObject = JSONObject().apply {
        put("client", JSONObject().apply {
            put("clientName", "WEB_REMIX")
            put("clientVersion", "1.20250401.01.00")
            put("hl", "en")
            put("gl", "US")
        })
    }

    private fun parseSections(root: JSONObject): List<RecommendationSection> {
        val sections = mutableListOf<RecommendationSection>()
        walkObjects(root) { obj ->
            val renderer = obj.optJSONObject("musicCarouselShelfRenderer")
                ?: obj.optJSONObject("musicShelfRenderer")
                ?: return@walkObjects

            val title = renderer.titleText().ifBlank { "Recommended" }
            val songs = parseSongs(renderer)

            if (songs.isNotEmpty()) {
                sections += RecommendationSection(title, songs)
            }
        }
        return sections.distinctBy { it.title }.take(12)
    }

    private fun parseSongs(root: JSONObject): List<Song> {
        val songs = mutableListOf<Song>()
        walkObjects(root) { obj ->
            val renderer = obj.optJSONObject("musicResponsiveListItemRenderer")
                ?: obj.optJSONObject("musicTwoRowItemRenderer")
                ?: obj.optJSONObject("playlistPanelVideoRenderer")
                ?: return@walkObjects

            val videoId = renderer.findVideoId()
            if (videoId.isBlank()) return@walkObjects

            val runs = renderer.findTextRuns()
            val title = runs.firstOrNull { it.isNotBlank() } ?: "Unknown Title"
            val artist = runs.drop(1).firstOrNull { 
                it.isNotBlank() && it != title && it != "Song" && it != "Video"
            } ?: "YouTube Music"

            val thumbnail = renderer.findThumbnail()
            val playlistId = renderer.findPlaylistId()

            val poster = "https://img.youtube.com/vi/$videoId/maxresdefault.jpg"
            songs += Song(
                videoId = videoId,
                title = title,
                artist = artist,
                thumbnail = thumbnail.ifBlank { poster },
                album = null,
                playlistId = playlistId,
                artworkUrl = poster
            )
        }
        return songs
    }

    private fun fallbackSections(): List<RecommendationSection> = listOf(
        RecommendationSection(
            "Quick picks",
            listOf(
                Song("jfKfPfyJRdk", "lofi hip hop radio", "Lofi Girl", artworkUrl = "https://img.youtube.com/vi/jfKfPfyJRdk/maxresdefault.jpg"),
                Song("5qap5aO4i9A", "chill beats", "YouTube Music", artworkUrl = "https://img.youtube.com/vi/5qap5aO4i9A/maxresdefault.jpg"),
                Song("DWcJFNfaw9c", "focus radio", "YouTube Music", artworkUrl = "https://img.youtube.com/vi/DWcJFNfaw9c/maxresdefault.jpg")
            )
        )
    )

    // ====================== JSON EXTENSIONS ======================

    private fun JSONObject.titleText(): String = /* ... same as before ... */
        optJSONObject("header")
            ?.optJSONObject("musicCarouselShelfBasicHeaderRenderer")
            ?.optJSONObject("title")
            ?.runsText()
            .orEmpty()
            .ifBlank { optJSONObject("title")?.runsText().orEmpty() }

    private fun JSONObject.findVideoId(): String {
        var id = ""
        walkObjects(this) { obj ->
            if (id.isBlank()) {
                id = obj.optJSONObject("watchEndpoint")?.optString("videoId").orEmpty()
                    .ifBlank { obj.optString("videoId") }
            }
        }
        return id
    }

    private fun JSONObject.findPlaylistId(): String? {
        var id = ""
        walkObjects(this) { obj ->
            if (id.isBlank()) {
                id = obj.optJSONObject("watchEndpoint")?.optString("playlistId").orEmpty()
                    .ifBlank { obj.optJSONObject("watchPlaylistEndpoint")?.optString("playlistId").orEmpty() }
            }
        }
        return id.takeIf { it.isNotBlank() }
    }

    private fun JSONObject.findThumbnail(): String {
        var bestUrl = ""
        var bestArea = 0
        var fallbackUrl = ""
        walkObjects(this) { obj ->
            val thumbnails = obj.optJSONArray("thumbnails") ?: return@walkObjects
            for (i in 0 until thumbnails.length()) {
                val t = thumbnails.optJSONObject(i) ?: continue
                val w = t.optInt("width", 0)
                val h = t.optInt("height", 0)
                val area = if (w > 0 && h > 0) w * h else 0
                val url = t.optString("url")
                if (url.isBlank()) continue
                if (fallbackUrl.isBlank()) fallbackUrl = url
                if (area > bestArea) {
                    bestArea = area
                    bestUrl = url
                }
            }
        }
        return bestUrl.ifBlank { fallbackUrl }
    }

    private fun JSONObject.findTextRuns(): List<String> {
        val runs = mutableListOf<String>()
        walkObjects(this) { obj ->
            obj.optJSONArray("runs")?.let { array ->
                for (i in 0 until array.length()) {
                    array.optJSONObject(i)?.optString("text")
                        ?.takeIf { it.isNotBlank() && it != " • " && it != " - " }
                        ?.let { runs += it }
                }
            }
        }
        return runs
    }

    private fun JSONObject.runsText(): String =
        optJSONArray("runs")?.let { array ->
            buildList {
                for (i in 0 until array.length()) {
                    array.optJSONObject(i)?.optString("text")?.let(::add)
                }
            }.joinToString("")
        }.orEmpty()

    private fun walkObjects(value: Any?, visit: (JSONObject) -> Unit) {
        when (value) {
            is JSONObject -> {
                visit(value)
                val keys = value.keys()
                while (keys.hasNext()) {
                    walkObjects(value.opt(keys.next()), visit)
                }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    walkObjects(value.opt(i), visit)
                }
            }
        }
    }

    // --- Smart radio / station (genre + dedupe) ---

    private fun stationSearchQueries(seed: Song): List<String> {
        val title = seed.title
        val artist = seed.artist.trim()
        val blob = "${title.lowercase(Locale.US)} ${artist.lowercase(Locale.US)}"
        val q = ArrayList<String>()

        fun add(s: String) {
            val t = s.trim()
            if (t.isNotBlank() && !q.contains(t)) q.add(t)
        }

        val hasPhonk = blob.contains("phonk")
        val hasDrift = blob.contains("drift") || blob.contains("drift phonk")
        val hasBrazilFunk = blob.contains("brazilian") && blob.contains("funk") ||
            blob.contains("brazil funk") || blob.contains("funk brasileiro")
        val slowedOrReverb = blob.contains("slowed") || blob.contains("reverb") ||
            blob.contains("nightcore") || blob.contains("bass boosted")
        val lofi = blob.contains("lofi") || blob.contains("lo-fi") || blob.contains("chill hop")
        val bollywood = blob.contains("bollywood") || blob.contains("hindi") ||
            blob.contains("desi") || blob.contains("punjabi")

        when {
            hasPhonk || hasDrift -> {
                add("phonk drift mix")
                add("dark phonk slowed reverb")
                add("phonk type beat mix")
            }
            hasBrazilFunk -> {
                add("brazilian funk mix 2024")
                add("funk brasileiro hits")
            }
            bollywood -> {
                add("bollywood hits mix 2024")
                add("hindi romantic songs mix")
            }
            lofi -> {
                add("chill lofi beats mix")
                add("lofi hip hop radio beats")
            }
            slowedOrReverb && !lofi -> {
                // Short “LUZ ROJA (Slowed)”-style edits are usually drift / phonk adjacent on YTM.
                add("phonk slowed mix")
                add("slowed reverb drift mix")
                add("dark slowed songs mix")
            }
        }

        val shortArtist = artist
            .substringBefore("feat.")
            .substringBefore("ft.")
            .trim()
            .removeSuffix(",")
            .trim()
        if (shortArtist.isNotBlank() &&
            shortArtist.length > 1 &&
            !shortArtist.equals("YouTube Music", ignoreCase = true) &&
            !shortArtist.equals("Unknown artist", ignoreCase = true)
        ) {
            add("$shortArtist best songs")
            add("$shortArtist mix")
        }

        // Broad tail so the station never collapses to one keyword.
        add("trending songs mix")

        return q
    }

    private fun normalizeTrackTitleKey(raw: String): String {
        var t = raw.lowercase(Locale.US)
        t = t.replace(Regex("\\(.*?\\)|\\[.*?\\]"), " ")
        val noise = listOf(
            "slowed", "reverb", "speed", "sped", "tiktok", "version", "remix", "edit",
            "official", "video", "audio", "full", "hd", "4k", "visualizer", "lyrics",
            "music video", "mv", "hq", "clean", "explicit"
        )
        for (w in noise) {
            t = t.replace(w, " ")
        }
        t = t.replace(Regex("[^a-z0-9áéíóúñü]+"), " ")
            .trim()
            .replace(Regex("\\s+"), " ")
        return t
    }

    /** Drops uploads that are obviously the same track / stem with a suffix tweak. */
    private fun isLikelySameTrackDifferentUpload(candidate: Song, seed: Song): Boolean {
        val a = normalizeTrackTitleKey(candidate.title)
        val b = normalizeTrackTitleKey(seed.title)
        if (a.isBlank() || b.isBlank()) return false
        if (a == b) return true
        if (a.length > 10 && b.length > 10) {
            if (a.contains(b) || b.contains(a)) {
                val ratio = minOf(a.length, b.length).toDouble() / maxOf(a.length, b.length)
                if (ratio > 0.72) return true
            }
        }
        val ta = a.split(' ').filter { it.length > 2 }.toSet()
        val tb = b.split(' ').filter { it.length > 2 }.toSet()
        if (ta.isEmpty() || tb.isEmpty()) return false
        val inter = ta.intersect(tb).size
        val union = ta.union(tb).size
        return inter.toDouble() / union > 0.82
    }

    /** Exposed for authenticated browse responses that share the same renderer tree shape. */
    internal fun songsFromBrowseJson(root: JSONObject): List<Song> = parseSongs(root)
}