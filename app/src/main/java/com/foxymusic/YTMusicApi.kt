package com.foxymusic

import android.util.Log
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

    private const val TAG = "YTMusicApi"
    private const val apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private const val baseUrl = "https://music.youtube.com/youtubei/v1"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    private fun requestHeaders(): Headers {
        val builder = Headers.Builder()
            .add("Accept", "application/json")
            .add("Content-Type", "application/json")
            .add("Origin", "https://music.youtube.com")
            .add("Referer", "https://music.youtube.com/")
            .add("User-Agent", StreamExtractor.STREAM_USER_AGENT)
            .add("X-YouTube-Client-Name", "67")
            .add("X-YouTube-Client-Version", "1.20250401.01.00")
        val cookie = FoxyAccount.state.value.cookie.trim()
        if (cookie.isNotBlank()) {
            builder.add("Cookie", cookie)
            FoxyAccount.state.value.cookie.sapisidHashHeader()?.let { builder.add("Authorization", it) }
        }
        return builder.build()
    }

    private const val filterSongs = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
    private const val filterVideos = "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
    private const val filterAlbums = "EgWKAQIYAwodChADEAQQCRA%3D%3D"
    private const val filterArtists = "EgWKAQIgAggKAghBcmNoZXN0"

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
        val query = when (mood.lowercase(Locale.US)) {
            "energize", "workout" -> "energizing workout music mix"
            "focus" -> "focus concentration music mix"
            "late night" -> "late night chill lofi mix"
            "romance" -> "romantic love songs mix"
            "chill", "relax" -> "chill relaxing music mix"
            "sleep" -> "sleep ambient calm music"
            "sad" -> "sad emotional songs playlist"
            "phonk" -> "phonk drift dark mix slowed"
            "bollywood" -> "bollywood hits mix 2024"
            "hindi" -> "hindi songs mix popular"
            "punjabi" -> "punjabi hits mix bhangra"
            "drift" -> "drift phonk car music mix"
            "lofi" -> "lofi hip hop beats mix"
            "jazz" -> "jazz cafe background music"
            "rock" -> "rock hits mix"
            "pop" -> "pop hits mix 2024"
            "edm" -> "edm festival drops mix"
            "k-pop", "kpop" -> "k-pop hits mix"
            else -> "$mood music mix"
        }
        return search(query).take(40)
    }

    suspend fun videos(query: String): List<Song> =
        search(query, filterVideos)

    /** SimpMusic-style categorized search (songs / videos / albums / artists). */
    suspend fun searchAll(query: String, limitPerCategory: Int = 28): Map<String, List<Song>> {
        if (query.isBlank()) {
            return mapOf(
                "songs" to emptyList(),
                "videos" to emptyList(),
                "albums" to emptyList(),
                "artists" to emptyList(),
            )
        }
        val cap = limitPerCategory.coerceIn(8, 40)
        return mapOf(
            "songs" to search(query, filterSongs).take(cap),
            "videos" to search(query, filterVideos).take(cap),
            "albums" to search(query, filterAlbums).take(cap),
            "artists" to search(query, filterArtists).take(cap),
        )
    }

    /**
     * Foxy-style radio: Innertube `next` with `RDAMVM{videoId}` + continuation pages.
     * Returns the first page only (for callers that do not paginate).
     */
    suspend fun radio(seed: Song): List<Song> =
        fetchRadioPage(seed, null).second

    /**
     * Loads the next slice of the official YT Music radio queue for [seed].
     * Reuses [session] when continuing; creates a new [YtmRadioSession] when null.
     */
    suspend fun fetchRadioPage(
        seed: Song,
        session: YtmRadioSession?,
    ): Pair<YtmRadioSession, List<Song>> {
        var state = session?.takeIf { it.seedVideoId == seed.videoId }
            ?: YtmRadioSession.forSeed(seed.videoId)

        if (state.exhausted && state.continuation == null) return state to emptyList()

        val isFirstPage = state.continuation == null
        var parsed = requestNextRadioPage(
            videoId = state.watchVideoId,
            playlistId = state.playlistId,
            continuation = state.continuation,
            loadAutomix = isFirstPage,
        )

        state.watchVideoId = parsed.watchVideoId.ifBlank { state.watchVideoId }
        state.playlistId = parsed.watchPlaylistId ?: state.playlistId

        var songs = filterRadioCandidates(parsed.songs, seed)

        // Foxy: empty RDAMVM → retry with video id only (no playlist id).
        if (isFirstPage && songs.size <= 1 && state.playlistId?.startsWith("RDAMVM") == true) {
            state.playlistId = null
            parsed = requestNextRadioPage(
                videoId = state.seedVideoId,
                playlistId = null,
                continuation = null,
                loadAutomix = true,
            )
            state.watchVideoId = parsed.watchVideoId.ifBlank { state.seedVideoId }
            state.playlistId = parsed.watchPlaylistId
            songs = filterRadioCandidates(parsed.songs, seed)
        }

        val relatedId = parsed.relatedBrowseId ?: state.relatedBrowseId
        val relatedParams = parsed.relatedBrowseParams ?: state.relatedBrowseParams
        if (relatedId != null) {
            state.relatedBrowseId = relatedId
            state.relatedBrowseParams = relatedParams
        }

        if (isFirstPage && songs.size <= 3 && relatedId != null) {
            val relatedSongs = filterRadioCandidates(related(relatedId, relatedParams), seed)
            songs = (songs + relatedSongs).distinctBy { it.videoId }
        }

        state.continuation = parsed.continuation
        state.exhausted = parsed.continuation.isNullOrBlank()

        if (songs.isEmpty() && isFirstPage) {
            songs = legacySearchRadioFallback(seed)
        }

        if (isFirstPage) {
            val panelIndex = parsed.currentIndex.coerceIn(0, songs.lastIndex.coerceAtLeast(0))
            state.queueStartIndex = songs.indexOfFirst { it.videoId == seed.videoId }
                .takeIf { it >= 0 } ?: panelIndex.coerceIn(0, songs.lastIndex.coerceAtLeast(0))
        }

        return state to songs
    }

    /** Keep the seed in panel order; drop dup uploads and non-songs only. */
    private fun filterRadioCandidates(raw: List<Song>, seed: Song): List<Song> =
        raw.filter { song ->
            song.videoId == seed.videoId || !isLikelySameTrackDifferentUpload(song, seed)
        }
            .distinctBy { it.videoId }
            .filter { it.isMusicQueueTrack() }

    /** Simple up-next panel (no RDAMVM playlist) — used for one-off suggestions. */
    suspend fun next(videoId: String): List<Song> {
        val page = requestNextRadioPage(videoId, playlistId = null, continuation = null)
        return page.songs.distinctBy { it.videoId }.filter { it.isMusicQueueTrack() }
    }

    suspend fun related(browseId: String, params: String? = null): List<Song> {
        if (browseId.isBlank()) return emptyList()
        val json = post("browse", JSONObject().apply {
            put("context", clientContext())
            put("browseId", browseId)
            params?.takeIf { it.isNotBlank() }?.let { put("params", it) }
        }) ?: return emptyList()
        return parseSongs(json).distinctBy { it.videoId }.filter { it.isMusicQueueTrack() }
    }

    private suspend fun requestNextRadioPage(
        videoId: String,
        playlistId: String?,
        continuation: String?,
        loadAutomix: Boolean = false,
    ): YtmNextRadioPage {
        val body = JSONObject().apply {
            put("context", clientContext())
            put("enablePersistentPlaylistPanel", true)
            put("isAudioOnly", true)
            put("tunerSettingValue", "AUTOMIX_SETTING_NORMAL")
            continuation?.takeIf { it.isNotBlank() }?.let { put("continuation", it) }
            put(
                "watchEndpoint",
                JSONObject().apply {
                    put("videoId", videoId)
                    playlistId?.takeIf { it.isNotBlank() }?.let { put("playlistId", it) }
                },
            )
        }
        val json = post("next", body) ?: return YtmNextRadioPage(emptyList(), null, null, null, videoId, playlistId)
        var parsed = YtmQueueParser.parseNextResponse(json, videoId, playlistId)

        // Foxy: merge automix playlist tracks after the official radio panel queue.
        if (loadAutomix && continuation.isNullOrBlank() && !parsed.automixPlaylistId.isNullOrBlank()) {
            val automixId = parsed.automixPlaylistId!!
            val automixPage = requestNextRadioPage(
                videoId = parsed.watchVideoId,
                playlistId = automixId,
                continuation = null,
                loadAutomix = false,
            )
            parsed = parsed.copy(
                songs = (parsed.songs + automixPage.songs).distinctBy { it.videoId },
                watchPlaylistId = automixPage.watchPlaylistId ?: automixId,
                continuation = automixPage.continuation ?: parsed.continuation,
                relatedBrowseId = automixPage.relatedBrowseId ?: parsed.relatedBrowseId,
                relatedBrowseParams = automixPage.relatedBrowseParams ?: parsed.relatedBrowseParams,
            )
        }

        if (parsed.songs.isEmpty()) {
            val fallback = parseSongs(json).distinctBy { it.videoId }
            if (fallback.isNotEmpty()) {
                parsed = parsed.copy(songs = fallback)
            }
        }

        return YtmNextRadioPage(
            songs = parsed.songs,
            continuation = parsed.continuation,
            relatedBrowseId = parsed.relatedBrowseId,
            relatedBrowseParams = parsed.relatedBrowseParams,
            watchVideoId = parsed.watchVideoId,
            watchPlaylistId = parsed.watchPlaylistId,
            currentIndex = parsed.currentIndex,
        )
    }

    private suspend fun legacySearchRadioFallback(seed: Song): List<Song> {
        val out = LinkedHashMap<String, Song>()
        fun put(s: Song) {
            if (s.videoId == seed.videoId) return
            if (!s.isMusicQueueTrack()) return
            if (isLikelySameTrackDifferentUpload(s, seed)) return
            out.putIfAbsent(s.videoId, s)
        }
        for (q in stationSearchQueries(seed).take(3)) {
            if (out.size >= 24) break
            search(q).forEach(::put)
        }
        return out.values.toList()
    }

    private fun findNextContinuation(root: JSONObject): String? {
        var found: String? = null
        walkObjects(root) { obj ->
            if (found != null) return@walkObjects
            obj.optJSONArray("continuations")?.let { arr ->
                for (i in 0 until arr.length()) {
                    arr.optJSONObject(i)
                        ?.optJSONObject("nextContinuationData")
                        ?.optString("continuation")
                        ?.takeIf { it.isNotBlank() }
                        ?.let {
                            found = it
                            return@walkObjects
                        }
                }
            }
        }
        return found
    }

    private fun findRelatedBrowseEndpoint(root: JSONObject): Pair<String?, String?> {
        var browseId: String? = null
        var params: String? = null
        walkObjects(root) { obj ->
            if (browseId != null) return@walkObjects
            val tabs = obj.optJSONObject("watchNextTabbedResultsRenderer")?.optJSONArray("tabs")
                ?: obj.optJSONObject("tabbedRenderer")
                    ?.optJSONObject("watchNextTabbedResultsRenderer")
                    ?.optJSONArray("tabs")
            if (tabs == null || tabs.length() < 3) return@walkObjects
            val endpoint = tabs.optJSONObject(2)
                ?.optJSONObject("tabRenderer")
                ?.optJSONObject("endpoint")
                ?.optJSONObject("browseEndpoint")
            val id = endpoint?.optString("browseId")?.takeIf { it.isNotBlank() } ?: return@walkObjects
            browseId = id
            params = endpoint.optString("params").takeIf { it.isNotBlank() }
        }
        return browseId to params
    }

    suspend fun lyrics(videoId: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url("https://video.google.com/timedtext?fmt=srv3&lang=en&v=$videoId")
                .headers(requestHeaders())
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
                .headers(requestHeaders())
                .post(body)
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "$endpoint HTTP ${response.code}")
                    return@withContext null
                }
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
            val filtered = parseSongs(renderer).distinctBy { it.videoId }
            if (filtered.isNotEmpty()) {
                sections += RecommendationSection(title, filtered)
            }
        }
        return sections.distinctBy { it.title }.take(12)
    }

    /** Quick picks when live Innertube browse/search returns nothing. */
    fun fallbackRecommendationSections(): List<RecommendationSection> = fallbackSections()

    private fun parseSongs(root: JSONObject): List<Song> {
        val songs = mutableListOf<Song>()
        val seen = HashSet<String>()
        walkObjects(root) { obj ->
            val renderer = obj.optJSONObject("musicResponsiveListItemRenderer")
                ?: obj.optJSONObject("musicTwoRowItemRenderer")
                ?: obj.optJSONObject("playlistPanelVideoRenderer")
                ?: return@walkObjects

            val song = parseRendererToSong(renderer) ?: return@walkObjects
            if (!seen.add(song.videoId)) return@walkObjects
            songs += song
        }
        return songs
    }

    private fun parseRendererToSong(renderer: JSONObject): Song? {
        val videoId = renderer.extractVideoId()
        if (videoId.isBlank()) return null

        val meta = renderer.extractTitleArtistDuration()
        val title = meta.title
        val artist = meta.artist
        if (title.isBlank()) return null
        if (YtmMusicFilter.isObviouslyNonPlayable(title, artist)) return null

        val thumbnail = renderer.findThumbnail()
        val playlistId = renderer.findPlaylistId().takeIf {
            renderer.optJSONObject("navigationEndpoint")?.has("watchPlaylistEndpoint") != true
        }
        val poster = "https://img.youtube.com/vi/$videoId/maxresdefault.jpg"
        return Song(
            videoId = videoId,
            title = title,
            artist = artist,
            thumbnail = thumbnail.ifBlank { poster },
            duration = meta.duration,
            album = meta.album,
            playlistId = playlistId,
            artworkUrl = poster,
        )
    }

    private data class ItemMeta(
        val title: String,
        val artist: String,
        val duration: String?,
        val album: String?,
    )

    private fun JSONObject.extractVideoId(): String {
        optJSONObject("playlistItemData")?.optString("videoId")?.trim()
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }
        return findVideoId().trim()
    }

    private fun JSONObject.extractTitleArtistDuration(): ItemMeta {
        optJSONArray("flexColumns")?.let { columns ->
            if (columns.length() > 0) {
                val title = columns.optJSONObject(0)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.runsText()
                    ?.trim()
                    .orEmpty()
                val subtitleRuns = columns.optJSONObject(1)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.collectRuns()
                    .orEmpty()
                val artist = subtitleRuns.firstOrNull {
                    it.isNotBlank() && it != " • " && !YtmMusicFilter.isDurationLike(it)
                } ?: "YouTube Music"
                val duration = subtitleRuns.firstOrNull { YtmMusicFilter.isDurationLike(it) }
                val album = subtitleRuns.drop(1).firstOrNull {
                    it.isNotBlank() && it != " • " && !YtmMusicFilter.isDurationLike(it) && it != artist
                }
                if (title.isNotBlank()) {
                    return ItemMeta(title, artist, duration, album)
                }
            }
        }

        val runs = findTextRuns()
        val title = runs.firstOrNull { it.isNotBlank() && !YtmMusicFilter.isDurationLike(it) }.orEmpty()
        val artist = runs.drop(1).firstOrNull {
            it.isNotBlank() &&
                it != title &&
                it != "Song" &&
                it != "Video" &&
                it != " • " &&
                !YtmMusicFilter.isDurationLike(it)
        } ?: "YouTube Music"
        return ItemMeta(
            title = title.ifBlank { "Unknown Title" },
            artist = artist,
            duration = findDurationText(),
            album = null,
        )
    }

    private fun JSONObject.collectRuns(): List<String> =
        optJSONArray("runs")?.let { array ->
            buildList {
                for (i in 0 until array.length()) {
                    array.optJSONObject(i)?.optString("text")
                        ?.takeIf { it.isNotBlank() }
                        ?.let { add(it) }
                }
            }
        }.orEmpty()

    private fun JSONObject.findDurationText(): String? {
        listOf("lengthText", "length", "durationText", "formattedDuration").forEach { key ->
            optJSONObject(key)?.runsText()?.trim()?.takeIf { YtmMusicFilter.isDurationLike(it) }?.let { return it }
        }
        findTextRuns().forEach { run ->
            if (YtmMusicFilter.isDurationLike(run)) return run.trim()
        }
        return null
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

        val titleKey = normalizeTrackTitleKey(seed.title)
        if (titleKey.isNotBlank() && q.size < 5) {
            add("songs like ${seed.title.take(48)}")
        }

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