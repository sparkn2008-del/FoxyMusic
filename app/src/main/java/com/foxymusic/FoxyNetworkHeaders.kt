package com.foxymusic

/**
 * Shared request headers for YouTube Music requests.
 */
fun buildFoxyStreamHeaders(): Map<String, String> {
    return mutableMapOf(
        "Origin" to "https://music.youtube.com",
        "Referer" to "https://music.youtube.com/",
        "Accept" to "*/*",
        "Accept-Language" to "en-US,en;q=0.9"
    )
}

