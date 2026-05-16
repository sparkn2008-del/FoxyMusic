package com.foxymusic

import android.content.Context

/** Throttle for background GitHub release checks (SimpMusic-style updater). */
object FoxyUpdatePrefs {
    private const val PREFS = "foxy_update"
    private const val LAST_CHECK_MS = "last_check_ms"
    private const val LAST_NOTIFIED_TAG = "last_notified_tag"

    /** Minimum interval between automatic checks (24 hours). */
    const val AUTO_CHECK_INTERVAL_MS = 24L * 60L * 60L * 1000L

    fun lastCheckMs(context: Context): Long =
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(LAST_CHECK_MS, 0L)

    fun setLastCheckMs(context: Context, ms: Long) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_CHECK_MS, ms)
            .apply()
    }

    fun lastNotifiedTag(context: Context): String =
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(LAST_NOTIFIED_TAG, "").orEmpty()

    fun setLastNotifiedTag(context: Context, tag: String) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(LAST_NOTIFIED_TAG, tag.trim())
            .apply()
    }
}
