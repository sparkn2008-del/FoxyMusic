package com.foxymusic

/**
 * In-memory cache for Innertube stream URLs so search/queue taps don't re-resolve
 * through every YouTube client on every play.
 */
object StreamUrlCache {
    private const val TTL_MS = 4L * 60L * 60L * 1000L // 4 hours
    private const val MAX_ENTRIES = 160

    private data class Entry(val result: StreamResult, val expiresAtMs: Long)

    private val lock = Any()
    private val entries = LinkedHashMap<String, Entry>(MAX_ENTRIES, 0.75f, true)

    private fun key(videoId: String, qualityTier: Int): String = "$videoId|$qualityTier"

    fun peek(videoId: String, qualityTier: Int): String? {
        if (videoId.isBlank()) return null
        val k = key(videoId, qualityTier)
        synchronized(lock) {
            val entry = entries[k] ?: return null
            if (System.currentTimeMillis() >= entry.expiresAtMs) {
                entries.remove(k)
                return null
            }
            return entry.result.url
        }
    }

    fun put(videoId: String, qualityTier: Int, url: String) {
        put(videoId, qualityTier, StreamResult(url, source = "cache"))
    }

    fun peekResult(videoId: String, qualityTier: Int): StreamResult? {
        if (videoId.isBlank()) return null
        val k = key(videoId, qualityTier)
        synchronized(lock) {
            val entry = entries[k] ?: return null
            if (System.currentTimeMillis() >= entry.expiresAtMs) {
                entries.remove(k)
                return null
            }
            return entry.result
        }
    }

    fun put(videoId: String, qualityTier: Int, result: StreamResult) {
        val url = result.url ?: return
        if (videoId.isBlank() || url.isBlank()) return
        val k = key(videoId, qualityTier)
        synchronized(lock) {
            while (entries.size >= MAX_ENTRIES) {
                val oldest = entries.keys.firstOrNull() ?: break
                entries.remove(oldest)
            }
            entries[k] = Entry(result, System.currentTimeMillis() + TTL_MS)
        }
    }

    fun invalidate(videoId: String) {
        if (videoId.isBlank()) return
        synchronized(lock) {
            entries.keys.removeAll { it.startsWith("$videoId|") }
        }
    }

    fun clear() {
        synchronized(lock) {
            entries.clear()
        }
    }
}
