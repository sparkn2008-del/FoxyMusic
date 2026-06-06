package com.foxymusic



import org.json.JSONArray

import org.json.JSONObject

import java.util.Locale



/**

 * Foxy-style queue filtering: songs only, skip videos / podcasts / playlists,

 * and cap track length for autoplay / queue advance (10 minutes).

 */

object YtmMusicFilter {



    /** Max length for tracks in the player queue and autoplay suggestions. */

    const val MAX_QUEUE_TRACK_MS = 10 * 60 * 1000L



    private val DURATION_TEXT = Regex("""^\d{1,3}:\d{2}(:\d{2})?$""")



    private val NON_MUSIC_CATEGORY_LABELS = setOf(

        "video",

        "podcast",

        "episode",

        "full episode",

        "audiobook",

        "live",

        "concert",

        "interview",

        "documentary",

        "trailer",

        "album",

        "playlist",

        "artist",

        "compilation",

        "mixtape",

        "station",

    )



    /** Innertube [musicVideoType] values that are not normal playable songs. */

    private val NON_MUSIC_VIDEO_TYPES = setOf(

        "MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_VIDEO",

        "MUSIC_VIDEO_TYPE_OMV",

        "MUSIC_VIDEO_TYPE_PODCAST_EPISODE",

        "MUSIC_VIDEO_TYPE_PODCAST",

    )



    private val LONG_FORM_TITLE_HINTS = listOf(

        "podcast",

        "playlist",

        "full album",

        "full episode",

        "audiobook",

        "24/7",

        "24 7",

        "live stream",

        "livestream",

        "continuous",

        "marathon",

        "documentary",

        "interview",

        "megamix",

        "hour mix",

        "hours mix",

        "mixtape",

    )



    fun parseDurationToMs(raw: String?): Long? {

        val s = raw?.trim().orEmpty()

        if (s.isEmpty()) return null

        if (s.all { it.isDigit() }) {

            val n = s.toLongOrNull() ?: return null

            return if (n >= 10_000L) n else n * 1000L

        }

        if (!DURATION_TEXT.matches(s)) return null

        val parts = s.split(":").mapNotNull { it.trim().toIntOrNull() }

        return when (parts.size) {

            2 -> (parts[0] * 60L + parts[1]) * 1000L

            3 -> (parts[0] * 3600L + parts[1] * 60L + parts[2]) * 1000L

            else -> null

        }

    }



    fun isQueueEligibleDuration(duration: String?, title: String, artist: String): Boolean {

        val ms = parseDurationToMs(duration)

        if (ms != null) return ms in 1..MAX_QUEUE_TRACK_MS

        return isUnknownDurationQueueEligible(title, artist)

    }



    fun isUnknownDurationQueueEligible(title: String, artist: String): Boolean {

        val blob = "${title.trim().lowercase(Locale.US)} ${artist.trim().lowercase(Locale.US)}"

        if (blob.isBlank()) return false

        if (LONG_FORM_TITLE_HINTS.any { blob.contains(it) }) return false

        if (Regex("""\bep\.?\s*\d+""", RegexOption.IGNORE_CASE).containsMatchIn(blob)) return false

        if (Regex("""\bepisode\s+\d+""", RegexOption.IGNORE_CASE).containsMatchIn(blob)) return false

        if (title.trim().endsWith("radio", ignoreCase = true)) return false

        if (blob.contains(" radio") && !blob.contains("video")) return false

        if (artist.equals("YouTube Music", ignoreCase = true) &&

            (blob.contains("radio") || blob.contains("mix") || blob.contains("live"))

        ) {

            return false

        }

        return true

    }



    /**
     * Relaxed filter for home, search, and library browsing — shows normal tracks even when
     * duration is missing or the title contains "mix"/"radio". Queue/autoplay still uses
     * [isMusicQueueTrack].
     */
    /** Hard rejects for browse/search parsing (podcasts, audiobooks, etc.). */
    fun isObviouslyNonPlayable(title: String, artist: String): Boolean {
        val blob = "${title.trim().lowercase(Locale.US)} ${artist.trim().lowercase(Locale.US)}"
        if (blob.isBlank()) return true
        if (blob.contains("podcast")) return true
        if (blob.contains("audiobook")) return true
        if (blob.contains("full episode")) return true
        return false
    }

    fun isCatalogTrack(title: String, artist: String, duration: String? = null): Boolean {
        val t = title.trim()
        if (t.isBlank()) return false
        val blob = "${t.lowercase(Locale.US)} ${artist.trim().lowercase(Locale.US)}"
        if (blob.contains("podcast")) return false
        if (blob.contains("audiobook")) return false
        if (blob.contains("full episode")) return false
        if (Regex("""\bepisode\s+\d+""", RegexOption.IGNORE_CASE).containsMatchIn(blob)) {
            return false
        }
        if (blob.contains(" full album")) return false
        // Drop obvious non-song tiles (playlist hub rows), not every "mix" search result.
        if (blob.contains("playlist") && artist.equals("YouTube Music", ignoreCase = true) &&
            !blob.contains("song")
        ) {
            return false
        }
        val ms = parseDurationToMs(duration)
        if (ms != null && ms > MAX_QUEUE_TRACK_MS * 6) return false
        return true
    }

    fun isMusicQueueTrack(title: String, artist: String, duration: String? = null): Boolean {

        val t = title.trim()

        if (t.isBlank()) return false

        val blob = "${t.lowercase(Locale.US)} ${artist.trim().lowercase(Locale.US)}"

        if (blob.contains("podcast")) return false

        if (blob.contains("audiobook")) return false

        if (Regex("""\bep\.?\s*\d+""", RegexOption.IGNORE_CASE).containsMatchIn(blob)) {

            return false

        }

        if (Regex("""\bepisode\s+\d+""", RegexOption.IGNORE_CASE).containsMatchIn(blob)) {

            return false

        }

        if (blob.contains("full episode")) return false

        if (blob.contains("playlist") && !blob.contains("song")) return false

        if (blob.contains(" full album")) return false

        return isQueueEligibleDuration(duration, title, artist)

    }



    /** True when a browse/next renderer row is a normal song (not video/podcast/album tile). */

    fun isMusicInnertubeRenderer(renderer: JSONObject): Boolean {

        if (!isSongWatchRenderer(renderer)) return false

        val videoType = renderer.findMusicVideoType()

        if (videoType.isNotBlank() && NON_MUSIC_VIDEO_TYPES.any { videoType.equals(it, true) }) {

            return false

        }

        if (renderer.has("musicTwoRowItemRenderer")) {

            val runs = renderer.collectTextRuns()

            val tail = runs.drop(2).joinToString(" ").lowercase(Locale.US)

            if (tail.contains("album") || tail.contains("playlist") || tail.contains("artist")) {

                return false

            }

        }

        for (run in renderer.collectTextRuns()) {

            val label = run.trim().lowercase(Locale.US)

            if (label in NON_MUSIC_CATEGORY_LABELS) return false

            if (label.contains("podcast")) return false

            if (label.contains("playlist")) return false

        }

        return true

    }



    /** Album/playlist tiles use browse or playlist endpoints — not playable queue songs. */

    fun isSongWatchRenderer(renderer: JSONObject): Boolean {

        val nav = renderer.optJSONObject("navigationEndpoint") ?: return true

        if (nav.has("browseEndpoint")) return false

        val playlistNav = nav.optJSONObject("watchPlaylistEndpoint")

        if (playlistNav != null && playlistNav.optString("playlistId").isNotBlank()) {
            val vid = nav.optJSONObject("watchEndpoint")?.optString("videoId").orEmpty()
            if (vid.isBlank()) return false
        }
        return true

    }



    fun isDurationLike(text: String): Boolean = DURATION_TEXT.matches(text.trim())



    private fun JSONObject.findMusicVideoType(): String {

        var type = ""

        walk(this) { obj ->

            if (type.isNotBlank()) return@walk

            type = obj.optJSONObject("watchEndpoint")

                ?.optString("musicVideoType")

                .orEmpty()

                .ifBlank { obj.optString("musicVideoType") }

        }

        return type

    }



    private fun JSONObject.collectTextRuns(): List<String> {

        val runs = mutableListOf<String>()

        walk(this) { obj ->

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



fun Song.isMusicQueueTrack(): Boolean =

    !localPath.isNullOrBlank() || YtmMusicFilter.isMusicQueueTrack(title, artist, duration)



fun Song.isCatalogTrack(): Boolean =

    YtmMusicFilter.isCatalogTrack(title, artist, duration)



fun List<Song>.musicQueueTracksOnly(): List<Song> = filter { it.isMusicQueueTrack() }



/** Home / search / library lists — not the autoplay queue. */
fun List<Song>.catalogTracksOnly(): List<Song> = filter { it.isCatalogTrack() }

/** True when catalog metadata shows a track longer than the queue cap. */
fun Song.exceedsQueueDurationCap(): Boolean {
    val ms = YtmMusicFilter.parseDurationToMs(duration) ?: return false
    return ms > YtmMusicFilter.MAX_QUEUE_TRACK_MS
}


