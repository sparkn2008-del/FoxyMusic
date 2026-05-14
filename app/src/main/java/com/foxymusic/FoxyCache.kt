package com.foxymusic

import android.content.Context
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

object FoxyCache {
    @Volatile
    private var cache: SimpleCache? = null

    fun get(context: Context): SimpleCache {
        val existing = cache
        if (existing != null) return existing

        synchronized(this) {
            val again = cache
            if (again != null) return again

            val maxBytes = 512L * 1024L * 1024L // 512MB default for now
            val evictor = LeastRecentlyUsedCacheEvictor(maxBytes)
            val dir = File(context.applicationContext.cacheDir, "media_cache").apply { mkdirs() }
            val db = StandaloneDatabaseProvider(context.applicationContext)
            val created = SimpleCache(dir, evictor, db)
            cache = created
            return created
        }
    }
}

