package com.foxymusic

import android.net.Uri
import java.io.Serializable

/**
 * Main data class representing a song in FoxyMusic
 */
data class Song(
    val videoId: String,                    // YouTube video ID (primary key)
    val title: String,
    val artist: String,
    val thumbnail: String = "",             // Small thumbnail
    val duration: String? = null,           // e.g. "3:45"
    val album: String? = null,
    val playlistId: String? = null,

    // Local storage & caching
    val localPath: String? = null,          // Path to downloaded file
    val streamUrl: String? = null,          // Cached streaming URL
    val expiresAt: Long? = null,            // When streamUrl expires (Unix timestamp)

    // Additional metadata
    val isDownloaded: Boolean = false,
    val fileSize: Long? = null,
    val bitrate: Int? = null,
    val artworkUrl: String? = null,         // High quality artwork

    // For future use
    val lyrics: String? = null,
    val genre: String? = null,
    val year: Int? = null
) : Serializable {

    // Computed properties
    val isLocal: Boolean
        get() = !localPath.isNullOrBlank()

    val isStreamable: Boolean
        get() = !streamUrl.isNullOrBlank()

    /** Best artwork URL with fallbacks */
    fun bestArtworkUrl(): String {
        return when {
            !artworkUrl.isNullOrBlank() -> artworkUrl
            !thumbnail.isNullOrBlank() -> thumbnail
            else -> ""
        }
    }

    /** Multiple artwork candidates for better quality selection */
    fun artworkCandidates(): List<String> {
        return listOfNotNull(
            artworkUrl,
            thumbnail,
            "https://img.youtube.com/vi/$videoId/maxresdefault.jpg",
            "https://img.youtube.com/vi/$videoId/hqdefault.jpg"
        ).filter { it.isNotBlank() }
    }

    /** Best poster / cover image */
    fun bestPosterUrl(): String = bestArtworkUrl()

    companion object {
        fun fromYTMusic(
            videoId: String,
            title: String,
            artist: String,
            thumbnail: String,
            duration: String? = null,
            album: String? = null
        ): Song {
            return Song(
                videoId = videoId,
                title = title,
                artist = artist,
                thumbnail = thumbnail,
                duration = duration,
                album = album
            )
        }
    }
}