package com.foxymusic

/**
 * Paginated YouTube Music radio feed (Metrolist [YouTubeQueue]).
 * Uses Innertube `next` with playlist id `RDAMVM{videoId}` and continuation tokens.
 */
data class YtmRadioSession(
    val seedVideoId: String,
    var playlistId: String? = YtmRadioSession.radioPlaylistId(seedVideoId),
    var continuation: String? = null,
    var relatedBrowseId: String? = null,
    var relatedBrowseParams: String? = null,
    var exhausted: Boolean = false,
) {
    fun hasMorePages(): Boolean = !exhausted && continuation != null

    companion object {
        fun radioPlaylistId(videoId: String): String = "RDAMVM$videoId"

        fun forSeed(videoId: String): YtmRadioSession =
            YtmRadioSession(seedVideoId = videoId, playlistId = radioPlaylistId(videoId))
    }
}

data class YtmNextRadioPage(
    val songs: List<Song>,
    val continuation: String?,
    val relatedBrowseId: String?,
    val relatedBrowseParams: String?,
)
