package com.foxymusic

import android.content.Context
import android.net.Uri
import java.io.File

object FoxyHomeBackground {
    private const val PREFS = "foxy_home_background"
    private const val KEY_PATH = "custom_path"
    private const val FILE_NAME = "home_background.jpg"

    fun getPath(context: Context): String? {
        val stored = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PATH, null)
            ?.trim()
            .orEmpty()
        if (stored.isEmpty()) return null
        val file = File(stored)
        return if (file.exists() && file.length() > 0L) file.absolutePath else null
    }

    fun saveFromUri(context: Context, uri: Uri): String? {
        val out = File(context.applicationContext.filesDir, FILE_NAME)
        return runCatching {
            context.applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PATH, out.absolutePath)
                .apply()
            out.absolutePath
        }.getOrNull()
    }

    fun clear(context: Context) {
        val path = getPath(context)
        if (path != null) {
            runCatching { File(path).delete() }
        }
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_PATH)
            .apply()
    }
}
