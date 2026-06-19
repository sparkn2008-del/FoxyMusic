package com.foxymusic

import org.json.JSONArray
import org.json.JSONObject

/**
 * Parses Innertube `next` responses the way Foxy does: official
 * [musicQueueRenderer] / [playlistPanelRenderer] order (not random tree walks).
 */
internal object YtmQueueParser {

    data class ParsedNextQueue(
        val songs: List<Song>,
        val continuation: String?,
        val relatedBrowseId: String?,
        val relatedBrowseParams: String?,
        val watchVideoId: String,
        val watchPlaylistId: String?,
        val currentIndex: Int,
        /** RDAMVM-style automix playlist id from [automixPreviewVideoRenderer], if any. */
        val automixPlaylistId: String?,
    )

    fun parseNextResponse(
        root: JSONObject,
        fallbackVideoId: String,
        fallbackPlaylistId: String?,
    ): ParsedNextQueue {
        val panel = findPlaylistPanelRenderer(root)
        val songs = mutableListOf<Song>()
        var currentIndex = 0
        var automixPlaylistId: String? = null

        if (panel != null) {
            val contents = panel.optJSONArray("contents")
            if (contents != null) {
                for (i in 0 until contents.length()) {
                    val content = contents.optJSONObject(i) ?: continue
                    content.optJSONObject("playlistPanelVideoRenderer")?.let { renderer ->
                        val song = songFromPlaylistPanelVideo(renderer) ?: return@let
                        if (renderer.optBoolean("selected", false)) {
                            currentIndex = songs.size
                        }
                        songs += song
                        return@let
                    }
                    val automix = content.optJSONObject("automixPreviewVideoRenderer")
                        ?.optJSONObject("content")
                        ?.optJSONObject("automixPlaylistVideoRenderer")
                        ?.optJSONObject("navigationEndpoint")
                        ?.optJSONObject("watchPlaylistEndpoint")
                    automixPlaylistId = automix?.optString("playlistId")?.takeIf { it.isNotBlank() }
                        ?: automixPlaylistId
                }
            }
        }

        val continuation = panel?.let { findPlaylistPanelContinuation(it) }
            ?: findNextContinuation(root)

        val (relatedId, relatedParams) = findRelatedBrowseEndpoint(root)

        val watchVideoId = fallbackVideoId.ifBlank { songs.firstOrNull()?.videoId.orEmpty() }
        val watchPlaylistId = fallbackPlaylistId?.takeIf { it.isNotBlank() }
            ?: automixPlaylistId
            ?: YtmRadioSession.radioPlaylistId(watchVideoId).takeIf { watchVideoId.isNotBlank() }

        return ParsedNextQueue(
            songs = songs,
            continuation = continuation,
            relatedBrowseId = relatedId,
            relatedBrowseParams = relatedParams,
            watchVideoId = watchVideoId,
            watchPlaylistId = watchPlaylistId,
            currentIndex = currentIndex.coerceIn(0, (songs.size - 1).coerceAtLeast(0)),
            automixPlaylistId = automixPlaylistId,
        )
    }

    private fun findPlaylistPanelRenderer(root: JSONObject): JSONObject? {
        root.optJSONObject("continuationContents")
            ?.optJSONObject("playlistPanelContinuation")
            ?.let { return it }

        return root.optJSONObject("contents")
            ?.optJSONObject("singleColumnMusicWatchNextResultsRenderer")
            ?.optJSONObject("tabbedRenderer")
            ?.optJSONObject("watchNextTabbedResultsRenderer")
            ?.optJSONArray("tabs")
            ?.optJSONObject(0)
            ?.optJSONObject("tabRenderer")
            ?.optJSONObject("content")
            ?.optJSONObject("musicQueueRenderer")
            ?.optJSONObject("content")
            ?.optJSONObject("playlistPanelRenderer")
    }

    private fun findPlaylistPanelContinuation(panel: JSONObject): String? {
        panel.optJSONArray("continuations")?.let { arr ->
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.optJSONObject("nextContinuationData")
                    ?.optString("continuation")
                    ?.takeIf { it.isNotBlank() }
                    ?.let { return it }
                arr.optJSONObject(i)?.optJSONObject("nextRadioContinuationData")
                    ?.optString("continuation")
                    ?.takeIf { it.isNotBlank() }
                    ?.let { return it }
            }
        }
        return null
    }

    private fun songFromPlaylistPanelVideo(renderer: JSONObject): Song? {
        val videoId = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("watchEndpoint")
            ?.optString("videoId")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: renderer.optString("videoId").trim().takeIf { it.isNotBlank() }
            ?: return null

        val title = renderer.optJSONObject("title")?.runsText()?.trim().orEmpty()
        if (title.isBlank()) return null

        val artist = parseLongBylineArtist(renderer) ?: "Unknown artist"
        val duration = renderer.optJSONObject("lengthText")?.runsText()?.trim()
            ?.takeIf { YtmMusicFilter.isDurationLike(it) }
        val album = parseLongBylineAlbum(renderer)
        val thumbnail = findThumbnailInRenderer(renderer)
        val fallbackPoster = "https://img.youtube.com/vi/$videoId/hqdefault.jpg"
        val artwork = thumbnail.ifBlank { fallbackPoster }

        return Song(
            videoId = videoId,
            title = title,
            artist = artist,
            thumbnail = artwork,
            duration = duration,
            album = album,
            artworkUrl = artwork,
        )
    }

    private fun parseLongBylineArtist(renderer: JSONObject): String? {
        val runs = renderer.optJSONObject("longBylineText")?.collectRuns().orEmpty()
        if (runs.isEmpty()) return null
        val segments = splitRunsBySeparator(runs)
        val artistRuns = segments.firstOrNull().orEmpty()
        return artistRuns.firstOrNull { it.isNotBlank() && it != " • " }?.trim()
    }

    private fun parseLongBylineAlbum(renderer: JSONObject): String? {
        val runs = renderer.optJSONObject("longBylineText")?.collectRuns().orEmpty()
        if (runs.size < 2) return null
        val segments = splitRunsBySeparator(runs)
        return segments.getOrNull(1)?.firstOrNull { it.isNotBlank() && it != " • " }?.trim()
    }

    private fun splitRunsBySeparator(runs: List<String>): List<List<String>> {
        val segments = mutableListOf<MutableList<String>>()
        var current = mutableListOf<String>()
        for (run in runs) {
            if (run == " • " || run == " · ") {
                if (current.isNotEmpty()) segments += current
                current = mutableListOf()
            } else {
                current += run
            }
        }
        if (current.isNotEmpty()) segments += current
        return segments
    }

    private fun JSONObject.collectRuns(): List<String> {
        val runs = mutableListOf<String>()
        optJSONArray("runs")?.let { array ->
            for (i in 0 until array.length()) {
                array.optJSONObject(i)?.optString("text")
                    ?.takeIf { it.isNotBlank() }
                    ?.let { runs += it }
            }
        }
        return runs
    }

    private fun JSONObject.runsText(): String = collectRuns().joinToString("")

    private fun findThumbnailInRenderer(renderer: JSONObject): String {
        var bestUrl = ""
        var bestArea = 0
        walk(renderer) { obj ->
            obj.optJSONArray("thumbnails")?.let { thumbnails ->
                for (i in 0 until thumbnails.length()) {
                    val t = thumbnails.optJSONObject(i) ?: continue
                    val w = t.optInt("width", 0)
                    val h = t.optInt("height", 0)
                    val area = if (w > 0 && h > 0) w * h else 0
                    val url = t.optString("url")
                    if (url.isBlank()) continue
                    if (area > bestArea) {
                        bestArea = area
                        bestUrl = url
                    }
                }
            }
        }
        return bestUrl
    }

    private fun findNextContinuation(root: JSONObject): String? {
        var found: String? = null
        walk(root) { obj ->
            if (found != null) return@walk
            obj.optJSONArray("continuations")?.let { arr ->
                for (i in 0 until arr.length()) {
                    arr.optJSONObject(i)
                        ?.optJSONObject("nextContinuationData")
                        ?.optString("continuation")
                        ?.takeIf { it.isNotBlank() }
                        ?.let {
                            found = it
                            return@walk
                        }
                }
            }
        }
        return found
    }

    private fun findRelatedBrowseEndpoint(root: JSONObject): Pair<String?, String?> {
        val tabs = root.optJSONObject("contents")
            ?.optJSONObject("singleColumnMusicWatchNextResultsRenderer")
            ?.optJSONObject("tabbedRenderer")
            ?.optJSONObject("watchNextTabbedResultsRenderer")
            ?.optJSONArray("tabs")
            ?: return null to null
        if (tabs.length() < 3) return null to null
        val endpoint = tabs.optJSONObject(2)
            ?.optJSONObject("tabRenderer")
            ?.optJSONObject("endpoint")
            ?.optJSONObject("browseEndpoint")
        val id = endpoint?.optString("browseId")?.takeIf { it.isNotBlank() } ?: return null to null
        val params = endpoint.optString("params").takeIf { it.isNotBlank() }
        return id to params
    }

    private fun walk(value: Any?, visit: (JSONObject) -> Unit) {
        when (value) {
            is JSONObject -> {
                visit(value)
                val keys = value.keys()
                while (keys.hasNext()) {
                    walk(value.opt(keys.next()), visit)
                }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    walk(value.opt(i), visit)
                }
            }
        }
    }
}
