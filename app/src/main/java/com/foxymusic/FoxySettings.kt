package com.foxymusic

import android.content.Context
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class FoxyCustomization(
    val themeMode: Int = 0,
    val themePalette: Int = 0,
    val blurEffects: Boolean = true,
    val compactPlayer: Boolean = false,
    val gestureControls: Boolean = true,
    val dynamicSongColors: Boolean = true,
    val saveHistory: Boolean = true,
    val iconScale: Int = 1,
    val bottomNavScale: Int = 0,
    val gridColumns: Int = 2,
    val showBottomLabels: Boolean = true,
    /** Legacy: unused (Flutter uses default Material slider). */
    val playerProgressStyle: Int = 0,
    /** Legacy: unused. */
    val playerSeekMotion: Int = 0,
    /** Restore last queue and transport state after the app restarts. */
    val persistentQueue: Boolean = true,
    /** Keep playing when the app is swiped away from recent tasks. */
    val continuePlaybackWhenDismissed: Boolean = false,
    /** Default accent: YouTube Music–style red. */
    val accentArgb: Int = 0xFFFF1744.toInt(),
    /** Auto-skip sponsor / promo segments via SponsorBlock. */
    val sponsorBlockEnabled: Boolean = true,
    /** Crossfade at track boundaries (volume ramp, single player). 0 = off. */
    val crossfadeMs: Int = 0,
    /** Prefer LRCLIB synced lyrics; otherwise try YouTube transcript first. */
    val lyricsPreferLrclib: Boolean = true,
    /** Show synced lyrics in Latin / English letters (romanization). */
    val lyricsRomanize: Boolean = false,
    /** 0 = low, 1 = balanced, 2 = high, 3 = ultra aggressive. */
    val streamQualityTier: Int = 2,
    /** Separate preference for offline downloads. */
    val downloadQualityTier: Int = 2,
    /** BCP-47 tag for catalogue / search bias (stored for future API use). */
    val contentLanguageTag: String = "en-US",
    /** App UI language tag; blank = follow system. */
    val appLanguageTag: String = "",
    /** HTTP proxy for stream extraction and playback (host:port). */
    val proxyEnabled: Boolean = false,
    val proxyEndpoint: String = "",
    /** Lower peak output so loud masters sit closer to quieter tracks ([MusicPlayer] applies ~78% gain). */
    val normalizeVolume: Boolean = false,
    /** Reserved: skip silent segments (UI + persistence; Exo wiring later). */
    val skipSilence: Boolean = false,
    /** Reserved: auto backup (UI only for now). */
    val autoBackupEnabled: Boolean = false,
    /** Check GitHub releases on launch (throttled). */
    val autoCheckUpdates: Boolean = true,
    /** Post a notification when a newer APK is published. */
    val updateNotifications: Boolean = true,
) {
    val accent: Color
        get() = Color(accentArgb)
}

data class FoxyThemePreset(
    val name: String,
    val description: String,
    val background: Color,
    val surface: Color,
    val surfaceHigh: Color,
    val pill: Color,
    val accent: Color,
    val muted: Color
)

val FoxyThemePresets = listOf(
    FoxyThemePreset("Foxy Pop", "YT Music energy with clean AMOLED contrast", Color(0xFF000000), Color(0xFF1E1E1E), Color(0xFF2C2C2C), Color(0xFF383838), Color(0xFFFF1744), Color(0xFFA8A8A8)),
    FoxyThemePreset("Aurora", "Teal, violet, and soft night surfaces", Color(0xFF061211), Color(0xFF10201F), Color(0xFF1D3432), Color(0xFF294642), Color(0xFF54E0C1), Color(0xFFAFCBC7)),
    FoxyThemePreset("Midnight Gold", "Black glass with warm premium highlights", Color(0xFF050505), Color(0xFF181612), Color(0xFF272116), Color(0xFF3A3020), Color(0xFFFFC857), Color(0xFFC8BFAE)),
    FoxyThemePreset("Rosewave", "Deep rose, coral, and soft pink accents", Color(0xFF12070B), Color(0xFF241017), Color(0xFF371B25), Color(0xFF4B2533), Color(0xFFFF6F91), Color(0xFFD9B2BE))
)

object FoxySettings {
    private const val PREFS = "foxy_customization"
    private const val AMOLED = "amoled"
    private const val THEME_MODE = "theme_mode"
    private const val THEME_PALETTE = "theme_palette"
    private const val BLUR = "blur"
    private const val COMPACT_PLAYER = "compact_player"
    private const val GESTURES = "gestures"
    private const val DYNAMIC_SONG_COLORS = "dynamic_song_colors"
    private const val SAVE_HISTORY = "save_history"
    private const val ICON_SCALE = "icon_scale"
    private const val BOTTOM_NAV_SCALE = "bottom_nav_scale"
    private const val GRID_COLUMNS = "grid_columns"
    private const val BOTTOM_LABELS = "bottom_labels"
    private const val PLAYER_PROGRESS_STYLE = "player_progress_style"
    private const val PLAYER_SEEK_MOTION = "player_seek_motion"
    private const val PERSISTENT_QUEUE = "persistent_queue"
    private const val CONTINUE_PLAYBACK_DISMISSED = "continue_playback_when_dismissed"
    private const val ACCENT = "accent"
    private const val SPONSOR_BLOCK = "sponsor_block"
    private const val CROSSFADE_MS = "crossfade_ms"
    private const val LYRICS_LRCLIB = "lyrics_lrclib_first"
    private const val LYRICS_ROMANIZE = "lyrics_romanize"
    private const val STREAM_QUALITY = "stream_quality_tier"
    private const val DOWNLOAD_QUALITY = "download_quality_tier"
    private const val CONTENT_LANG = "content_language_tag"
    private const val APP_LANG = "app_language_tag"
    private const val PROXY_ON = "proxy_enabled"
    private const val PROXY_EP = "proxy_endpoint"
    private const val NORM_VOL = "normalize_volume"
    private const val SKIP_SIL = "skip_silence"
    private const val AUTO_BACKUP = "auto_backup"
    private const val AUTO_CHECK_UPDATES = "auto_check_updates"
    private const val UPDATE_NOTIFICATIONS = "update_notifications"

    private val _state = MutableStateFlow(FoxyCustomization())
    val state: StateFlow<FoxyCustomization> = _state
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _state.value = FoxyCustomization(
            themeMode = prefs.getInt(THEME_MODE, if (prefs.getBoolean(AMOLED, true)) 1 else 2).coerceIn(0, 2),
            themePalette = prefs.getInt(THEME_PALETTE, 0).coerceIn(0, FoxyThemePresets.lastIndex),
            blurEffects = prefs.getBoolean(BLUR, true),
            compactPlayer = prefs.getBoolean(COMPACT_PLAYER, false),
            gestureControls = prefs.getBoolean(GESTURES, true),
            dynamicSongColors = prefs.getBoolean(DYNAMIC_SONG_COLORS, true),
            saveHistory = prefs.getBoolean(SAVE_HISTORY, true),
            iconScale = prefs.getInt(ICON_SCALE, 1).coerceIn(0, 2),
            bottomNavScale = prefs.getInt(BOTTOM_NAV_SCALE, 0).coerceIn(0, 2),
            gridColumns = prefs.getInt(GRID_COLUMNS, 2).coerceIn(2, 4),
            showBottomLabels = prefs.getBoolean(BOTTOM_LABELS, true),
            playerProgressStyle = prefs.getInt(PLAYER_PROGRESS_STYLE, 0).coerceIn(0, 3),
            playerSeekMotion = prefs.getInt(PLAYER_SEEK_MOTION, 0).coerceIn(0, 2),
            persistentQueue = prefs.getBoolean(PERSISTENT_QUEUE, true),
            continuePlaybackWhenDismissed = prefs.getBoolean(CONTINUE_PLAYBACK_DISMISSED, false),
            accentArgb = prefs.getInt(ACCENT, 0xFFFF1744.toInt()),
            sponsorBlockEnabled = prefs.getBoolean(SPONSOR_BLOCK, true),
            crossfadeMs = prefs.getInt(CROSSFADE_MS, 0).let { v ->
                when (v) {
                    3000, 5000, 8000, 12000 -> v
                    else -> 0
                }
            },
            lyricsPreferLrclib = prefs.getBoolean(LYRICS_LRCLIB, true),
            lyricsRomanize = prefs.getBoolean(LYRICS_ROMANIZE, false),
            streamQualityTier = prefs.getInt(STREAM_QUALITY, 2).coerceIn(0, 3),
            downloadQualityTier = prefs.getInt(DOWNLOAD_QUALITY, 2).coerceIn(0, 3),
            contentLanguageTag = prefs.getString(CONTENT_LANG, "en-US") ?: "en-US",
            appLanguageTag = prefs.getString(APP_LANG, "").orEmpty(),
            proxyEnabled = prefs.getBoolean(PROXY_ON, false),
            proxyEndpoint = prefs.getString(PROXY_EP, "").orEmpty(),
            normalizeVolume = prefs.getBoolean(NORM_VOL, false),
            skipSilence = prefs.getBoolean(SKIP_SIL, false),
            autoBackupEnabled = prefs.getBoolean(AUTO_BACKUP, false),
            autoCheckUpdates = prefs.getBoolean(AUTO_CHECK_UPDATES, true),
            updateNotifications = prefs.getBoolean(UPDATE_NOTIFICATIONS, true),
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
            ?.putInt(THEME_PALETTE, next.themePalette.coerceIn(0, FoxyThemePresets.lastIndex))
            ?.putBoolean(BLUR, next.blurEffects)
            ?.putBoolean(COMPACT_PLAYER, next.compactPlayer)
            ?.putBoolean(GESTURES, next.gestureControls)
            ?.putBoolean(DYNAMIC_SONG_COLORS, next.dynamicSongColors)
            ?.putBoolean(SAVE_HISTORY, next.saveHistory)
            ?.putInt(ICON_SCALE, next.iconScale)
            ?.putInt(BOTTOM_NAV_SCALE, next.bottomNavScale)
            ?.putInt(GRID_COLUMNS, next.gridColumns)
            ?.putBoolean(BOTTOM_LABELS, next.showBottomLabels)
            ?.putInt(PLAYER_PROGRESS_STYLE, next.playerProgressStyle.coerceIn(0, 3))
            ?.putInt(PLAYER_SEEK_MOTION, next.playerSeekMotion.coerceIn(0, 2))
            ?.putBoolean(PERSISTENT_QUEUE, next.persistentQueue)
            ?.putBoolean(CONTINUE_PLAYBACK_DISMISSED, next.continuePlaybackWhenDismissed)
            ?.putInt(ACCENT, next.accentArgb)
            ?.putBoolean(SPONSOR_BLOCK, next.sponsorBlockEnabled)
            ?.putInt(CROSSFADE_MS, next.crossfadeMs)
            ?.putBoolean(LYRICS_LRCLIB, next.lyricsPreferLrclib)
            ?.putBoolean(LYRICS_ROMANIZE, next.lyricsRomanize)
            ?.putInt(STREAM_QUALITY, next.streamQualityTier.coerceIn(0, 3))
            ?.putInt(DOWNLOAD_QUALITY, next.downloadQualityTier.coerceIn(0, 3))
            ?.putString(CONTENT_LANG, next.contentLanguageTag)
            ?.putString(APP_LANG, next.appLanguageTag)
            ?.putBoolean(PROXY_ON, next.proxyEnabled)
            ?.putString(PROXY_EP, next.proxyEndpoint)
            ?.putBoolean(NORM_VOL, next.normalizeVolume)
            ?.putBoolean(SKIP_SIL, next.skipSilence)
            ?.putBoolean(AUTO_BACKUP, next.autoBackupEnabled)
            ?.putBoolean(AUTO_CHECK_UPDATES, next.autoCheckUpdates)
            ?.putBoolean(UPDATE_NOTIFICATIONS, next.updateNotifications)
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
    val preset = FoxyThemePresets[themePalette.coerceIn(0, FoxyThemePresets.lastIndex)]
    val baseAccent = Color(0xFFFF1744)
    val accent = if (dynamicSongColors) dynamicAccent ?: baseAccent else baseAccent
    val dark = when (themeMode) {
        1 -> true
        2 -> false
        else -> systemDark
    }
    return if (dark) {
        FoxyPalette(
            background = preset.background,
            surface = preset.surface,
            surfaceHigh = preset.surfaceHigh,
            pill = preset.pill,
            accent = accent,
            muted = preset.muted
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
