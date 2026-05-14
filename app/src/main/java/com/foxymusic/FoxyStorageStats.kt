package com.foxymusic

import android.content.Context
import java.io.File

object FoxyStorageStats {

    fun snapshot(context: Context): Map<String, Any> {
        val app = context.applicationContext
        val downloadsDir = File(app.getExternalFilesDir(null), "downloads")
        val mediaCacheDir = File(app.cacheDir, "media_cache")
        return mapOf(
            "downloadBytes" to directorySize(downloadsDir),
            "cacheBytes" to directorySize(mediaCacheDir)
        )
    }

    private fun directorySize(root: File?): Long {
        if (root == null || !root.exists()) return 0L
        var total = 0L
        root.walkTopDown().forEach { f ->
            if (f.isFile) total += f.length()
        }
        return total
    }
}
