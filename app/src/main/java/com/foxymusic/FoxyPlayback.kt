package com.foxymusic

import android.content.Context

/**
 * Unified playback entry points so Home, Search, Library, and Queue all use the same
 * Metrolist-style radio feed ([YTMusicApi.fetchRadioPage]) when starting from a single track.
 */
object FoxyPlayback {

    /** Seed + official YT Music radio (`RDAMVM` + continuation pages). */
    fun playWithRadio(context: Context, seed: Song) {
        MusicPlayer.playQueue(
            context,
            listOf(seed),
            startIndex = 0,
            radioTail = true,
        )
    }

    /** Explicit queue (playlist, play-all, full search results, player queue). */
    fun playQueue(
        context: Context,
        songs: List<Song>,
        startIndex: Int = 0,
    ) {
        val filtered = songs.distinctBy { it.videoId }.musicQueueTracksOnly()
        if (filtered.isEmpty()) return
        val index = startIndex.coerceIn(0, filtered.lastIndex)
        MusicPlayer.playQueue(context, filtered, index, radioTail = false)
    }

    fun playFromList(
        context: Context,
        song: Song,
        contextQueue: List<Song>,
        useRadio: Boolean = contextQueue.musicQueueTracksOnly().size <= 1,
    ) {
        if (useRadio) {
            playWithRadio(context, song)
        } else {
            val queue = contextQueue.musicQueueTracksOnly().distinctBy { it.videoId }
            val idx = queue.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0)
            playQueue(context, queue.ifEmpty { listOf(song) }, idx)
        }
    }
}
