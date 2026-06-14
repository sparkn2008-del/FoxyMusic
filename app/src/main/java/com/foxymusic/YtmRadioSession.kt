package com.foxymusic

/**
 * Paginated YouTube Music radio feed (Foxy [YouTubeQueue]).
 * Uses Innertube `next` with playlist id `RDAMVM{videoId}` and continuation tokens.
 */
data class YtmRadioSession(
    val seedVideoId: String,
    /** Current watch endpoint video id (updates after automix / continuation). */
    var watchVideoId: String = seedVideoId,
    var playlistId: String? = YtmRadioSession.radioPlaylistId(seedVideoId),
    var continuation: String? = null,
    var relatedBrowseId: String? = null,
    var relatedBrowseParams: String? = null,
    var exhausted: Boolean = false,
    /** Index of the seed track inside the first Innertube playlist panel (Foxy currentIndex). */
    var queueStartIndex: Int = 0,
) {
    fun hasMorePages(): Boolean = !exhausted && continuation != null

    companion object {
        fun radioPlaylistId(videoId: String): String = "RDAMVM$videoId"

        fun forSeed(videoId: String): YtmRadioSession =
            YtmRadioSession(
                seedVideoId = videoId,
                watchVideoId = videoId,
                playlistId = radioPlaylistId(videoId),
            )
    }
}

data class YtmNextRadioPage(
    val songs: List<Song>,
    val continuation: String?,
    val relatedBrowseId: String?,
    val relatedBrowseParams: String?,
    val watchVideoId: String = "",
    val watchPlaylistId: String? = null,
    val currentIndex: Int = 0,
)
