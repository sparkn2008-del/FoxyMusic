package com.foxymusic

import android.content.Context
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class FoxyCustomization(
    val themeMode: Int = 0,
    val blurEffects: Boolean = true,
    val compactPlayer: Boolean = false,
    val gestureControls: Boolean = true,
    val dynamicSongColors: Boolean = true,
    val saveHistory: Boolean = true,
    val iconScale: Int = 1,
    val bottomNavScale: Int = 0,
    val gridColumns: Int = 2,
    val showBottomLabels: Boolean = true,
    /** Restore last queue and transport state after the app restarts. */
    val persistentQueue: Boolean = true,
    /** Default accent: YouTube Music–style red. */
    val accentArgb: Int = 0xFFFF1744.toInt(),
    /** Auto-skip sponsor / promo segments via SponsorBlock. */
    val sponsorBlockEnabled: Boolean = true,
    /** Crossfade at track boundaries (volume ramp, single player). 0 = off. */
    val crossfadeMs: Int = 0,
    /** Prefer LRCLIB synced lyrics; otherwise try YouTube transcript first. */
    val lyricsPreferLrclib: Boolean = true
) {
    val accent: Color
        get() = Color(accentArgb)
}

object FoxySettings {
    private const val PREFS = "foxy_customization"
    private const val AMOLED = "amoled"
    private const val THEME_MODE = "theme_mode"
    private const val BLUR = "blur"
    private const val COMPACT_PLAYER = "compact_player"
    private const val GESTURES = "gestures"
    private const val DYNAMIC_SONG_COLORS = "dynamic_song_colors"
    private const val SAVE_HISTORY = "save_history"
    private const val ICON_SCALE = "icon_scale"
    private const val BOTTOM_NAV_SCALE = "bottom_nav_scale"
    private const val GRID_COLUMNS = "grid_columns"
    private const val BOTTOM_LABELS = "bottom_labels"
    private const val PERSISTENT_QUEUE = "persistent_queue"
    private const val ACCENT = "accent"
    private const val SPONSOR_BLOCK = "sponsor_block"
    private const val CROSSFADE_MS = "crossfade_ms"
    private const val LYRICS_LRCLIB = "lyrics_lrclib_first"

    private val _state = MutableStateFlow(FoxyCustomization())
    val state: StateFlow<FoxyCustomization> = _state
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _state.value = FoxyCustomization(
            themeMode = prefs.getInt(THEME_MODE, if (prefs.getBoolean(AMOLED, true)) 1 else 2).coerceIn(0, 2),
            blurEffects = prefs.getBoolean(BLUR, true),
            compactPlayer = prefs.getBoolean(COMPACT_PLAYER, false),
            gestureControls = prefs.getBoolean(GESTURES, true),
            dynamicSongColors = prefs.getBoolean(DYNAMIC_SONG_COLORS, true),
            saveHistory = prefs.getBoolean(SAVE_HISTORY, true),
            iconScale = prefs.getInt(ICON_SCALE, 1).coerceIn(0, 2),
            bottomNavScale = prefs.getInt(BOTTOM_NAV_SCALE, 0).coerceIn(0, 2),
            gridColumns = prefs.getInt(GRID_COLUMNS, 2).coerceIn(2, 4),
            showBottomLabels = prefs.getBoolean(BOTTOM_LABELS, true),
            persistentQueue = prefs.getBoolean(PERSISTENT_QUEUE, true),
            accentArgb = prefs.getInt(ACCENT, 0xFFFF1744.toInt()),
            sponsorBlockEnabled = prefs.getBoolean(SPONSOR_BLOCK, true),
            crossfadeMs = prefs.getInt(CROSSFADE_MS, 0).let { v ->
                when (v) {
                    3000, 5000, 8000, 12000 -> v
                    else -> 0
                }
            },
            lyricsPreferLrclib = prefs.getBoolean(LYRICS_LRCLIB, true)
        )
    }

    fun update(transform: (FoxyCustomization) -> FoxyCustomization) {
        val next = transform(_state.value)
        _state.value = next
        if (!next.persistentQueue) {
            appContext?.let { PlaybackPersistence.clearSession(it) }
        }
        appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()
            ?.putInt(THEME_MODE, next.themeMode)
            ?.putBoolean(BLUR, next.blurEffects)
            ?.putBoolean(COMPACT_PLAYER, next.compactPlayer)
            ?.putBoolean(GESTURES, next.gestureControls)
            ?.putBoolean(DYNAMIC_SONG_COLORS, next.dynamicSongColors)
            ?.putBoolean(SAVE_HISTORY, next.saveHistory)
            ?.putInt(ICON_SCALE, next.iconScale)
            ?.putInt(BOTTOM_NAV_SCALE, next.bottomNavScale)
            ?.putInt(GRID_COLUMNS, next.gridColumns)
            ?.putBoolean(BOTTOM_LABELS, next.showBottomLabels)
            ?.putBoolean(PERSISTENT_QUEUE, next.persistentQueue)
            ?.putInt(ACCENT, next.accentArgb)
            ?.putBoolean(SPONSOR_BLOCK, next.sponsorBlockEnabled)
            ?.putInt(CROSSFADE_MS, next.crossfadeMs)
            ?.putBoolean(LYRICS_LRCLIB, next.lyricsPreferLrclib)
            ?.apply()
    }
}

data class FoxyPalette(
    val background: Color,
    val surface: Color,
    val surfaceHigh: Color,
    val pill: Color,
    val accent: Color,
    val muted: Color
)

fun FoxyCustomization.palette(dynamicAccent: Color? = null, systemDark: Boolean = true): FoxyPalette {
    val accent = if (dynamicSongColors) dynamicAccent ?: accent else accent
    val dark = when (themeMode) {
        1 -> true
        2 -> false
        else -> systemDark
    }
    return if (dark) {
        // Dark neutrals: deep black base with clearly separated elevated surfaces.
        FoxyPalette(
            background = Color(0xFF000000),
            surface = Color(0xFF1E1E1E),
            surfaceHigh = Color(0xFF2C2C2C),
            pill = Color(0xFF383838),
            accent = accent,
            muted = Color(0xFFA8A8A8)
        )
    } else {
        FoxyPalette(
            background = Color(0xFFF7FAF8),
            surface = Color(0xFFFFFFFF),
            surfaceHigh = Color(0xFFEAF1EE),
            pill = Color(0xFFDDE8E3),
            accent = accent,
            muted = Color(0xFF54625E)
        )
    }
}
