package com.foxymusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.LinkedHashMap
import java.util.concurrent.TimeUnit

data class YtmRemotePlaylistSummary(
    val id: String,
    val title: String,
    val songCount: Int,
)

data class YtmAccountProfile(
    val name: String,
    val email: String,
    val avatarUrl: String,
    val pageId: String = "",
)

/**
 * Authenticated YouTube Music Innertube calls (cookies + SAPISIDHASH).
 * Used for account playlists: list, create, add tracks, rename, delete.
 */
object YTMusicAuthApi {

    private const val apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private const val baseUrl = "https://music.youtube.com/youtubei/v1"

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(40, TimeUnit.SECONDS)
        .build()

    private fun clientContext(): JSONObject = JSONObject().apply {
        put("client", JSONObject().apply {
            put("clientName", "WEB_REMIX")
            put("clientVersion", "1.20250401.01.00")
            put("hl", "en")
            put("gl", "US")
        })
    }

    private fun authOrNull(): Pair<String, String>? {
        val st = FoxyAccount.state.value
        if (!st.isSignedIn) return null
        val auth = st.cookie.sapisidHashHeader() ?: return null
        return st.cookie to auth
    }

    private fun authForCookieOrNull(cookie: String): Pair<String, String>? {
        val clean = cookie.trim()
        if (clean.isBlank() || !clean.parseCookies().containsKey("SAPISID")) return null
        val auth = clean.sapisidHashHeader() ?: return null
        return clean to auth
    }

    private suspend fun postAuthed(endpoint: String, inner: JSONObject): JSONObject? =
        postAuthedWithCookie(authOrNull(), endpoint, inner)

    private suspend fun postAuthedWithCookie(
        authPair: Pair<String, String>?,
        endpoint: String,
        inner: JSONObject,
    ): JSONObject? =
        withContext(Dispatchers.IO) {
            val (cookie, authorization) = authPair ?: return@withContext null
            runCatching {
                val payload = JSONObject().apply {
                    put("context", clientContext())
                    val keys = inner.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        put(k, inner.get(k))
                    }
                }
                val body = payload.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder()
                    .url("$baseUrl/$endpoint?key=$apiKey&prettyPrint=false")
                    .addHeader("Accept", "application/json")
                    .addHeader("Content-Type", "application/json")
                    .addHeader("Origin", "https://music.youtube.com")
                    .addHeader("Referer", "https://music.youtube.com/")
                    .addHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    .addHeader("X-YouTube-Client-Name", "67")
                    .addHeader("X-YouTube-Client-Version", "1.20250401.01.00")
                    .addHeader("Cookie", cookie)
                    .addHeader("Authorization", authorization)
                    .post(body)
                    .build()
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@withContext null
                    JSONObject(response.body?.string().orEmpty())
                }
            }.getOrNull()
        }

    fun playlistIdForApi(id: String): String = id.removePrefix("VL")

    suspend fun fetchAccountProfiles(cookie: String = FoxyAccount.state.value.cookie): List<YtmAccountProfile> {
        val json = postAuthedWithCookie(
            authForCookieOrNull(cookie),
            "account/account_menu",
            JSONObject(),
        ) ?: return emptyList()
        return parseAccountProfiles(json)
    }

    suspend fun fetchLibraryPlaylists(limit: Int = 80): List<YtmRemotePlaylistSummary> {
        val json = postAuthed(
            "browse",
            JSONObject().put("browseId", "FEmusic_liked_playlists"),
        ) ?: return emptyList()
        return parsePlaylistSummaries(json, limit)
    }

    suspend fun browsePlaylistTracks(playlistId: String): List<Song> {
        val bare = playlistIdForApi(playlistId)
        val browseId = "VL$bare"
        val json = postAuthed("browse", JSONObject().put("browseId", browseId)) ?: return emptyList()
        return YTMusicApi.songsFromBrowseJson(json).distinctBy { it.videoId }
    }

    suspend fun createPlaylist(title: String, description: String = "", privacy: String = "PRIVATE"): String? {
        val safeTitle = title.replace("<", "").replace(">", "").trim().ifBlank { "New playlist" }
        val body = JSONObject().apply {
            put("title", safeTitle)
            put("description", description)
            put("privacyStatus", privacy)
        }
        val json = postAuthed("playlist/create", body) ?: return null
        return json.optString("playlistId").trim().takeIf { it.isNotBlank() }
    }

    suspend fun addVideoToPlaylist(playlistId: String, videoId: String): Boolean {
        val pid = playlistIdForApi(playlistId)
        val body = JSONObject().apply {
            put("playlistId", pid)
            put(
                "actions",
                JSONArray().put(
                    JSONObject().apply {
                        put("action", "ACTION_ADD_VIDEO")
                        put("addedVideoId", videoId)
                    },
                ),
            )
        }
        val json = postAuthed("browse/edit_playlist", body) ?: return false
        return json.optString("status").contains("SUCCEEDED", ignoreCase = true)
    }

    suspend fun renamePlaylist(playlistId: String, newTitle: String): Boolean {
        val name = newTitle.trim().ifBlank { return false }
        val body = JSONObject().apply {
            put("playlistId", playlistIdForApi(playlistId))
            put(
                "actions",
                JSONArray().put(
                    JSONObject().apply {
                        put("action", "ACTION_SET_PLAYLIST_NAME")
                        put("playlistName", name)
                    },
                ),
            )
        }
        val json = postAuthed("browse/edit_playlist", body) ?: return false
        return json.optString("status").contains("SUCCEEDED", ignoreCase = true)
    }

    suspend fun deletePlaylist(playlistId: String): Boolean {
        val body = JSONObject().put("playlistId", playlistIdForApi(playlistId))
        val json = postAuthed("playlist/delete", body) ?: return false
        return json.optString("status").contains("SUCCEEDED", ignoreCase = true)
    }

    // --- parsing ---

    private fun parseAccountProfiles(root: JSONObject): List<YtmAccountProfile> {
        val profiles = LinkedHashMap<String, YtmAccountProfile>()
        walkJson(root) { obj ->
            val email = textCandidate(obj, "email")
                .ifBlank { obj.optString("email").trim() }
                .ifBlank { findEmailInObject(obj) }
            if (email.isBlank()) return@walkJson
            val name = textCandidate(obj, "accountName")
                .ifBlank { textCandidate(obj, "name") }
                .ifBlank { obj.optString("name").trim() }
                .ifBlank { email.substringBefore("@") }
            val avatar = thumbnailCandidate(obj)
            val pageId = browseIdCandidate(obj)
            profiles[email] = YtmAccountProfile(
                name = name,
                email = email,
                avatarUrl = avatar,
                pageId = pageId,
            )
        }
        if (profiles.isNotEmpty()) return profiles.values.toList()
        val fallbackEmail = findEmailInObject(root)
        if (fallbackEmail.isBlank()) return emptyList()
        return listOf(
            YtmAccountProfile(
                name = findLikelyName(root).ifBlank { fallbackEmail.substringBefore("@") },
                email = fallbackEmail,
                avatarUrl = thumbnailCandidate(root),
                pageId = browseIdCandidate(root),
            ),
        )
    }

    private fun textCandidate(obj: JSONObject, key: String): String {
        val raw = obj.opt(key) ?: return ""
        return when (raw) {
            is String -> raw.trim()
            is JSONObject -> raw.runsText().ifBlank { raw.optString("simpleText").trim() }
            else -> ""
        }
    }

    private fun findEmailInObject(obj: Any?): String {
        val emailRegex = Regex("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", RegexOption.IGNORE_CASE)
        var found = ""
        fun walk(value: Any?) {
            if (found.isNotBlank()) return
            when (value) {
                is JSONObject -> {
                    val keys = value.keys()
                    while (keys.hasNext()) walk(value.opt(keys.next()))
                }
                is JSONArray -> for (i in 0 until value.length()) walk(value.opt(i))
                is String -> found = emailRegex.find(value)?.value.orEmpty()
            }
        }
        walk(obj)
        return found
    }

    private fun findLikelyName(root: JSONObject): String {
        var found = ""
        walkJson(root) { obj ->
            if (found.isNotBlank()) return@walkJson
            found = textCandidate(obj, "accountName")
                .ifBlank { textCandidate(obj, "name") }
                .ifBlank { obj.optString("name").trim() }
        }
        return found
    }

    private fun thumbnailCandidate(obj: JSONObject): String {
        fun fromThumbObject(thumb: JSONObject?): String {
            val arr = thumb?.optJSONArray("thumbnails") ?: return ""
            var best = ""
            var bestWidth = -1
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val url = item.optString("url").trim()
                val width = item.optInt("width", 0)
                if (url.isNotBlank() && width >= bestWidth) {
                    best = url
                    bestWidth = width
                }
            }
            return best
        }
        return fromThumbObject(obj.optJSONObject("accountPhoto"))
            .ifBlank { fromThumbObject(obj.optJSONObject("avatar")) }
            .ifBlank { fromThumbObject(obj.optJSONObject("thumbnail")) }
    }

    private fun browseIdCandidate(obj: JSONObject): String {
        obj.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optString("browseId")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }
        obj.optString("browseId").trim().takeIf { it.isNotBlank() }?.let { return it }
        obj.optString("pageId").trim().takeIf { it.isNotBlank() }?.let { return it }
        return ""
    }

    private fun parsePlaylistSummaries(root: JSONObject, limit: Int): List<YtmRemotePlaylistSummary> {
        val map = LinkedHashMap<String, YtmRemotePlaylistSummary>()
        walkJson(root) { obj ->
            if (map.size >= limit) return@walkJson
            obj.optJSONObject("musicTwoRowItemRenderer")?.let { tryAddRenderer(it, map) }
            obj.optJSONObject("musicResponsiveListItemRenderer")?.let { tryAddRenderer(it, map) }
        }
        return map.values.toList()
    }

    private fun tryAddRenderer(renderer: JSONObject, into: LinkedHashMap<String, YtmRemotePlaylistSummary>) {
        val nav = renderer.optJSONObject("navigationEndpoint") ?: return
        val wp = nav.optJSONObject("watchPlaylistEndpoint") ?: return
        val pid = wp.optString("playlistId").trim()
        if (pid.isBlank()) return
        val title = renderer.optJSONObject("title")?.runsText().orEmpty()
            .ifBlank { flexColumnPrimaryTitle(renderer) }
            .ifBlank { "Playlist" }
        val subtitle = renderer.optJSONObject("subtitle")?.runsText().orEmpty()
        val count = extractLeadingInt(subtitle)
        into.putIfAbsent(pid, YtmRemotePlaylistSummary(pid, title, count))
    }

    private fun flexColumnPrimaryTitle(renderer: JSONObject): String {
        val cols = renderer.optJSONArray("flexColumns") ?: return ""
        if (cols.length() == 0) return ""
        val col0 = cols.optJSONObject(0) ?: return ""
        val flex = col0.optJSONObject("musicResponsiveListItemFlexColumnRenderer") ?: return ""
        return flex.optJSONObject("text")?.runsText().orEmpty()
    }

    private fun extractLeadingInt(text: String): Int {
        if (text.isBlank()) return 0
        return Regex("\\d+").find(text.replace(",", ""))?.value?.toIntOrNull() ?: 0
    }

    private fun JSONObject.runsText(): String =
        optJSONArray("runs")?.let { array ->
            buildString {
                for (i in 0 until array.length()) {
                    array.optJSONObject(i)?.optString("text")?.let { append(it) }
                }
            }
        }.orEmpty()

    private fun walkJson(value: Any?, visit: (JSONObject) -> Unit) {
        when (value) {
            is JSONObject -> {
                visit(value)
                val keys = value.keys()
                while (keys.hasNext()) {
                    walkJson(value.opt(keys.next()), visit)
                }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    walkJson(value.opt(i), visit)
                }
            }
        }
    }
}
