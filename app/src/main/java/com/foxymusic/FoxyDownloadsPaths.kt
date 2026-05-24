package com.foxymusic

import android.content.Context
import java.io.File

/**
 * Canonical offline downloads folder and legacy fallbacks.
 *
 * New files are always written to [dir] (`getExternalFilesDir(null)/downloads`).
 * [legacyDir] (`filesDir/downloads`) is still scanned so older installs keep their library.
 */
object FoxyDownloadsPaths {
    private const val DIR_NAME = "downloads"

    val mediaExtensions = setOf(
        "webm", "mp4", "m4a", "opus", "mp3", "media", "mkv", "aac", "ogg",
    )

    fun dir(context: Context): File =
        File(context.getExternalFilesDir(null), DIR_NAME).apply { mkdirs() }

    fun legacyDir(context: Context): File =
        File(context.filesDir, DIR_NAME)

    fun allDirs(context: Context): List<File> = buildList {
        add(dir(context))
        val legacy = legacyDir(context)
        if (legacy.absolutePath != first().absolutePath) add(legacy)
    }

    fun metaFile(context: Context, videoId: String): File {
        for (d in allDirs(context)) {
            val f = File(d, "$videoId.foxy-meta.json")
            if (f.isFile && f.length() > 0L) return f
        }
        return File(dir(context), "$videoId.foxy-meta.json")
    }

    fun artFile(context: Context, videoId: String): File {
        for (d in allDirs(context)) {
            val f = File(d, "$videoId.art.jpg")
            if (f.isFile && f.length() > 0L) return f
        }
        return File(dir(context), "$videoId.art.jpg")
    }

    fun lyricsFile(context: Context, videoId: String): File {
        for (d in allDirs(context)) {
            val f = File(d, "$videoId.lyrics.json")
            if (f.isFile && f.length() > 0L) return f
        }
        return File(dir(context), "$videoId.lyrics.json")
    }

    fun findMediaFile(context: Context, videoId: String): File? {
        for (d in allDirs(context)) {
            if (!d.isDirectory) continue
            d.listFiles()?.firstOrNull { f ->
                f.isFile &&
                    f.nameWithoutExtension == videoId &&
                    f.extension.lowercase() in mediaExtensions &&
                    f.length() > 0L
            }?.let { return it }
        }
        return null
    }

    fun listDownloadFiles(context: Context): List<File> =
        allDirs(context).flatMap { d ->
            if (!d.isDirectory) emptyList() else d.listFiles()?.filter { it.isFile }.orEmpty()
        }

    fun deleteArtifactsForVideo(context: Context, videoId: String) {
        for (d in allDirs(context)) {
            if (!d.isDirectory) continue
            d.listFiles()?.forEach { file ->
                if (!file.isFile) return@forEach
                if (file.name == "$videoId.foxy-meta.json" ||
                    file.name == "$videoId.art.jpg" ||
                    file.name == "$videoId.lyrics.json"
                ) {
                    file.delete()
                    return@forEach
                }
                val ext = file.extension.lowercase()
                if (file.nameWithoutExtension == videoId && ext in mediaExtensions) {
                    file.delete()
                }
            }
        }
    }
}
