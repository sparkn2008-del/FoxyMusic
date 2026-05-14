package com.foxymusic

/**
 * Shared request headers for YouTube Music requests.
 */
fun buildFoxyStreamHeaders(): Map<String, String> {
    val headers = mutableMapOf(
        "Origin" to "https://music.youtube.com",
        "Referer" to "https://music.youtube.com/"
    )
    val account = FoxyAccount.state.value
    if (account.cookie.isNotBlank()) {
        headers["Cookie"] = account.cookie
        account.cookie.sapisidHashHeader()?.let { headers["Authorization"] = it }
    }
    return headers
}

