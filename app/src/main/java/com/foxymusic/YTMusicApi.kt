package com.foxymusic

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

data class Song(
    val videoId: String,
    val title: String,
    val artist: String,
    val thumbnail: String
)

data class RecommendationSection(
    val title: String,
    val songs: List<Song>
)

data class AccountProfile(
    val name: String,
    val email: String,
    val avatarUrl: String
)

object YTMusicApi {

    private val client = OkHttpClient()
    private const val BASE_URL = "https://music.youtube.com/youtubei/v1"
    private const val API_KEY = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-KOIS0TpYA"

    private fun getContext(): JSONObject {
        val context = JSONObject()
        val clientObj = JSONObject()
        clientObj.put("clientName", "WEB_REMIX")
        clientObj.put("clientVersion", "1.20231101.01.00")
        context.put("client", clientObj)
        return JSONObject().put("context", context)
    }

    fun search(query: String): List<Song> {
        val body = getContext()
        body.put("query", query)

        val request = Request.Builder()
            .url("$BASE_URL/search?key=$API_KEY")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addFoxyHeaders()
            .build()

        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: return emptyList()
        val json = JSONObject(responseBody)

        val songs = mutableListOf<Song>()

        try {
            val contents = json
                .getJSONObject("contents")
                .getJSONObject("tabbedSearchResultsRenderer")
                .getJSONArray("tabs")
                .getJSONObject(0)
                .getJSONObject("tabRenderer")
                .getJSONObject("content")
                .getJSONObject("sectionListRenderer")
                .getJSONArray("contents")

            for (i in 0 until contents.length()) {
                try {
                    val items = contents.getJSONObject(i)
                        .getJSONObject("musicShelfRenderer")
                        .getJSONArray("contents")

                    for (j in 0 until items.length()) {
                        try {
                            val item = items.getJSONObject(j)
                                .getJSONObject("musicResponsiveListItemRenderer")

                            val videoId = item
                                .getJSONObject("playlistItemData")
                                .getString("videoId")

                            val cols: JSONArray = item.getJSONArray("flexColumns")

                            val title = cols.getJSONObject(0)
                                .getJSONObject("musicResponsiveListItemFlexColumnRenderer")
                                .getJSONObject("text")
                                .getJSONArray("runs")
                                .getJSONObject(0)
                                .getString("text")

                            val artist = try {
                                cols.getJSONObject(1)
                                    .getJSONObject("musicResponsiveListItemFlexColumnRenderer")
                                    .getJSONObject("text")
                                    .getJSONArray("runs")
                                    .getJSONObject(0)
                                    .getString("text")
                            } catch (e: Exception) { "Unknown Artist" }

                            val thumbnail = item.bestThumbnail().ifBlank { videoId.youtubeThumbnailUrl() }

                            songs.add(
                                Song(
                                    videoId = videoId,
                                    title = title.cleanMusicText(),
                                    artist = artist.cleanSubtitle().ifBlank { "YouTube Music" },
                                    thumbnail = thumbnail
                                )
                            )
                        } catch (e: Exception) { continue }
                    }
                } catch (e: Exception) { continue }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        json.walkObjects { obj ->
            obj.optJSONObject("musicResponsiveListItemRenderer")?.toSong()?.let { songs += it }
            obj.optJSONObject("musicTwoRowItemRenderer")?.toSong()?.let { songs += it }
            obj.optJSONObject("musicCardShelfRenderer")?.toSong()?.let { songs += it }
        }

        return songs
            .filter { it.videoId.isNotBlank() && it.title.isNotBlank() }
            .distinctBy { it.videoId }
            .take(50)
    }

    fun homeRecommendations(): List<RecommendationSection> {
        val body = getContext()
        body.put("browseId", "FEmusic_home")

        val request = Request.Builder()
            .url("$BASE_URL/browse?key=$API_KEY")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addFoxyHeaders()
            .build()

        val response = client.newCall(request).execute()
        val json = JSONObject(response.body?.string().orEmpty())
        val sections = mutableListOf<RecommendationSection>()
        json.walkObjects { obj ->
            when {
                obj.has("musicCarouselShelfRenderer") -> {
                    val shelf = obj.getJSONObject("musicCarouselShelfRenderer")
                    val title = shelf.extractHeaderTitle().ifBlank { "Recommended for you" }
                    val songs = shelf.optJSONArray("contents").songsFromArray()
                    if (songs.isNotEmpty()) sections += RecommendationSection(title, songs.distinctBy { it.videoId }.take(12))
                }
                obj.has("musicShelfRenderer") -> {
                    val shelf = obj.getJSONObject("musicShelfRenderer")
                    val title = shelf.extractHeaderTitle().ifBlank { "Fresh picks" }
                    val songs = shelf.optJSONArray("contents").songsFromArray()
                    if (songs.isNotEmpty()) sections += RecommendationSection(title, songs.distinctBy { it.videoId }.take(12))
                }
            }
        }
        return sections.distinctBy { it.title }.take(8)
    }

    fun accountInfo(): AccountProfile? {
        val request = Request.Builder()
            .url("$BASE_URL/account/account_menu?key=$API_KEY")
            .post(getContext().toString().toRequestBody("application/json".toMediaType()))
            .addFoxyHeaders()
            .build()
        val response = client.newCall(request).execute()
        val json = JSONObject(response.body?.string().orEmpty())
        var profile: AccountProfile? = null
        json.walkObjects { obj ->
            if (profile == null && obj.has("activeAccountHeaderRenderer")) {
                val account = obj.optJSONObject("activeAccountHeaderRenderer") ?: return@walkObjects
                profile = AccountProfile(
                    name = account.optJSONObject("accountName")?.runsText()
                        ?: account.optJSONObject("title")?.runsText()
                        ?: account.optString("accountName"),
                    email = account.optJSONObject("email")?.runsText()
                        ?: account.optJSONObject("accountEmail")?.runsText()
                        ?: account.optString("email"),
                    avatarUrl = account.optJSONObject("accountPhoto")?.bestThumbnailFromThumbnails()
                        ?: account.optJSONObject("avatar")?.bestThumbnailFromThumbnails()
                        ?: account.bestThumbnail()
                )
            }
            if (profile == null && obj.has("accountItem")) {
                val account = obj.optJSONObject("accountItem") ?: return@walkObjects
                profile = AccountProfile(
                    name = account.optJSONObject("accountName")?.runsText().orEmpty(),
                    email = account.optJSONObject("accountEmail")?.runsText().orEmpty(),
                    avatarUrl = account.optJSONObject("accountPhoto")?.bestThumbnailFromThumbnails().orEmpty()
                )
            }
        }
        return profile
    }

    private fun Request.Builder.addFoxyHeaders(): Request.Builder {
        val account = FoxyAccount.state.value
        addHeader("User-Agent", "Mozilla/5.0")
        addHeader("Origin", "https://music.youtube.com")
        addHeader("Referer", "https://music.youtube.com/")
        if (account.cookie.isNotBlank()) {
            addHeader("Cookie", account.cookie)
            account.cookie.sapisidHashHeader()?.let { addHeader("Authorization", it) }
            addHeader("X-Origin", "https://music.youtube.com")
        }
        return this
    }

    private fun JSONArray?.songsFromArray(): List<Song> {
        if (this == null) return emptyList()
        val songs = mutableListOf<Song>()
        for (i in 0 until length()) {
            getJSONObject(i).walkObjects { obj ->
                obj.optJSONObject("musicResponsiveListItemRenderer")?.toSong()?.let { songs += it }
                obj.optJSONObject("musicTwoRowItemRenderer")?.toSong()?.let { songs += it }
                obj.optJSONObject("musicCardShelfRenderer")?.toSong()?.let { songs += it }
            }
        }
        return songs
    }

    private fun JSONObject.toSong(): Song? {
        val videoId = findVideoId()
        if (videoId.isNullOrBlank()) return null
        val title = optJSONArray("flexColumns")?.optJSONObject(0)
            ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
            ?.optJSONObject("text")
            ?.runsText()
            ?: optJSONObject("title")?.runsText()
            ?: "Untitled"
        val artist = optJSONArray("flexColumns")?.optJSONObject(1)
            ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
            ?.optJSONObject("text")
            ?.runsText()
            ?: optJSONObject("subtitle")?.runsText()
            ?: "YouTube Music"
        return Song(
            videoId = videoId,
            title = title.cleanMusicText().ifBlank { "Untitled" },
            artist = artist.cleanSubtitle().ifBlank { "YouTube Music" },
            thumbnail = bestThumbnail().ifBlank { videoId.youtubeThumbnailUrl() }
        )
    }

    private fun JSONObject.findVideoId(): String? {
        optJSONObject("playlistItemData")?.optString("videoId")?.takeIf { it.isNotBlank() }?.let { return it }
        optJSONObject("navigationEndpoint")?.optJSONObject("watchEndpoint")?.optString("videoId")?.takeIf { it.isNotBlank() }?.let { return it }
        optJSONObject("overlay")
            ?.optJSONObject("musicItemThumbnailOverlayRenderer")
            ?.optJSONObject("content")
            ?.optJSONObject("musicPlayButtonRenderer")
            ?.optJSONObject("playNavigationEndpoint")
            ?.optJSONObject("watchEndpoint")
            ?.optString("videoId")
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }
        var found: String? = null
        walkObjects { obj ->
            if (found == null) {
                found = obj.optJSONObject("watchEndpoint")?.optString("videoId")?.takeIf { it.isNotBlank() }
            }
        }
        return found
    }

    private fun JSONObject.extractHeaderTitle(): String {
        val header = optJSONObject("header")
        val runs = header
            ?.optJSONObject("musicCarouselShelfBasicHeaderRenderer")
            ?.optJSONObject("title")
            ?: optJSONObject("title")
        return runs?.runsText().orEmpty()
    }

    private fun JSONObject.runsText(): String {
        val runs = optJSONArray("runs") ?: return optString("text", "")
        val parts = mutableListOf<String>()
        for (i in 0 until runs.length()) {
            runs.optJSONObject(i)?.optString("text")?.takeIf { it.isNotBlank() }?.let(parts::add)
        }
        return parts.joinToString("").trim()
    }

    private fun String.cleanMusicText(): String =
        replace(Regex("\\s+"), " ").trim(' ', '•', '-', '|', '·')

    private fun String.cleanSubtitle(): String {
        val parts = split("•", "·", "|").map { it.cleanMusicText() }.filter { it.isNotBlank() }
        val cleaned = parts.filterNot {
            it.equals("Song", true) ||
                it.equals("Video", true) ||
                it.equals("Album", true) ||
                it.equals("Playlist", true) ||
                it.equals("Single", true)
        }
        return cleaned.joinToString(", ").ifBlank {
            cleanMusicText().takeUnless { it.equals("Song", true) }.orEmpty()
        }
    }

    private fun JSONObject.bestThumbnail(): String {
        val direct = optJSONObject("thumbnail")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?.bestThumbnailFromThumbnails()
        if (!direct.isNullOrBlank()) return direct
        val rendered = optJSONObject("thumbnailRenderer")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?.bestThumbnailFromThumbnails()
        if (!rendered.isNullOrBlank()) return rendered
        var best = ""
        walkObjects { obj ->
            if (best.isBlank() && obj.has("thumbnails")) {
                best = obj.bestThumbnailFromThumbnails()
            }
        }
        return best
    }

    private fun JSONObject.bestThumbnailFromThumbnails(): String {
        val thumbnails = optJSONArray("thumbnails") ?: return ""
        var bestUrl = ""
        var bestWidth = -1
        for (i in 0 until thumbnails.length()) {
            val item = thumbnails.optJSONObject(i) ?: continue
            val width = item.optInt("width", i)
            if (width >= bestWidth) {
                bestWidth = width
                bestUrl = item.optString("url").normalizeThumbnailUrl()
            }
        }
        return bestUrl
    }

    private fun String.normalizeThumbnailUrl(): String = when {
        startsWith("//") -> "https:$this"
        startsWith("http://") -> replaceFirst("http://", "https://")
        else -> this
    }

    private fun String.youtubeThumbnailUrl(): String =
        if (isBlank()) "" else "https://i.ytimg.com/vi/$this/hqdefault.jpg"

    private fun JSONObject.walkObjects(onObject: (JSONObject) -> Unit) {
        walkJsonValue(this, onObject)
    }

    private fun walkJsonValue(value: Any?, onObject: (JSONObject) -> Unit) {
        when (value) {
            is JSONObject -> {
                onObject(value)
                value.keys().forEach { key -> walkJsonValue(value.opt(key), onObject) }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) walkJsonValue(value.opt(i), onObject)
            }
        }
    }
}
