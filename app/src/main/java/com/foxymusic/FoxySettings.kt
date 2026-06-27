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
    val disableAnimations: Boolean = false,
    val hapticFeedback: Boolean = true,
    /** 0 = default, 1 = slim. Legacy values normalize back to 0. */
    val playerProgressStyle: Int = 0,
    /** Legacy: unused. */
    val playerSeekMotion: Int = 0,
    /** 0 = blurred artwork, 1 = unblurred artwork, 2 = solid black, 3 = video clip. */
    val playerBackgroundStyle: Int = 0,
    /** 0 = classic controls, 1 = reserved, 2 = top action cluster. */
    val playerStyle: Int = 0,
    /** 0 = soft glass, 1 = outline, 2 = solid accent. */
    val playerButtonsStyle: Int = 0,
    /** Single switch for the iPhone-style liquid glass shell treatment. */
    val enableLiquidGlassLayout: Boolean = false,
    /** 0 = default, 1 = liquid glass, 2 = transparent. */
    val miniPlayerStyle: Int = 0,
    /** 0 = default, 1 = liquid glass, 2 = transparent. */
    val bottomNavigationStyle: Int = 0,
    /** 0 = rounded square, 1 = circle/vinyl, 2 = compact rounded. */
    val playerArtworkShape: Int = 0,
    val hidePlayerArtwork: Boolean = false,
    val cropArtworkSquare: Boolean = true,
    val thumbnailCornerRadius: Int = 16,
    /** 0 = none, 1 = fade, 2 = glow, 3 = slide, 4 = karaoke, 5 = apple. */
    val lyricsAnimationStyle: Int = 1,
    /** Restore last queue and transport state after the app restarts. */
    val persistentQueue: Boolean = true,
    /** Keep playing when the app is swiped away from recent tasks. */
    val continuePlaybackWhenDismissed: Boolean = false,
    /** Default accent: white/black player chrome. */
    val accentArgb: Int = 0xFFFFFFFF.toInt(),
    /** Auto-skip sponsor / promo segments via SponsorBlock. */
    val sponsorBlockEnabled: Boolean = true,
    /** Crossfade at track boundaries (volume ramp, single player). 0 = off. */
    val crossfadeMs: Int = 0,
    /** Prefer LRCLIB synced lyrics; otherwise try YouTube transcript first. */
    val lyricsPreferLrclib: Boolean = true,
    /** Show synced lyrics in Latin / English letters (romanization). */
    val lyricsRomanize: Boolean = false,
    /** 0 = low (<128), 1 = balanced, 2 = normal (~128), 3 = high (>250), 4 = ultra (best/lossless if available). */
    val streamQualityTier: Int = 2,
    /** Separate preference for offline downloads. */
    val downloadQualityTier: Int = 2,
    /** Network-specific stream tiers. -1 follows [streamQualityTier]. */
    val wifiQualityTier: Int = -1,
    val mobileQualityTier: Int = -1,
    /** 0 = YouTube only, 1 = YouTube then SoundCloud, 2 = SoundCloud then YouTube. */
    val streamSourcePriority: Int = 0,
    /** 0 = auto/highest confidence, 1 = YT/SoundCloud first, 2 = Spotify/Canvas first, 3 = song cover first. */
    val artworkPriority: Int = 0,
    /** 0 = built-in Shazam-style fingerprint, 1 = Android microphone/fast path. */
    val recognitionSource: Int = 0,
    /** Local recognition history cap. */
    val recognitionHistoryLimit: Int = 40,
    /** Experimental adaptive thumbnail glow on Home section headers. */
    val experimentalHomeHeaderAccent: Boolean = false,
    /** Use the saved custom wallpaper on Home/Search/Library instead of the default gradient. */
    val homeBackgroundEnabled: Boolean = false,
    /** 0 = Home, 1 = Search, 3 = Library. */
    val defaultOpenTab: Int = 0,
    val quickPicksDisplayMode: Int = 0,
    val showLikedInLibrary: Boolean = true,
    val showDownloadsInLibrary: Boolean = true,
    val showHistoryInLibrary: Boolean = true,
    val showMostPlayedInLibrary: Boolean = true,
    val showPlaylistsInLibrary: Boolean = true,
    val showLocalInLibrary: Boolean = true,
    val showRecognizedInLibrary: Boolean = true,
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
    val autoSkipNextOnError: Boolean = false,
    /** Automatically writes local JSON snapshots when settings/library state changes. */
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
    FoxyThemePreset("Foxy Pop", "Clean AMOLED contrast in white and black", Color(0xFF000000), Color(0xFF1E1E1E), Color(0xFF2C2C2C), Color(0xFF383838), Color(0xFFFFFFFF), Color(0xFFA8A8A8)),
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
    private const val DISABLE_ANIMATIONS = "disable_animations"
    private const val HAPTIC_FEEDBACK = "haptic_feedback"
    private const val PLAYER_PROGRESS_STYLE = "player_progress_style"
    private const val PLAYER_SEEK_MOTION = "player_seek_motion"
    private const val PLAYER_BACKGROUND_STYLE = "player_background_style"
    private const val PLAYER_STYLE = "player_style"
    private const val PLAYER_BUTTONS_STYLE = "player_buttons_style"
    private const val ENABLE_LIQUID_GLASS_LAYOUT = "enable_liquid_glass_layout"
    private const val MINI_PLAYER_STYLE = "mini_player_style"
    private const val BOTTOM_NAV_STYLE = "bottom_nav_style"
    private const val PLAYER_ARTWORK_SHAPE = "player_artwork_shape"
    private const val HIDE_PLAYER_ARTWORK = "hide_player_artwork"
    private const val CROP_ARTWORK_SQUARE = "crop_artwork_square"
    private const val THUMBNAIL_RADIUS = "thumbnail_corner_radius"
    private const val LYRICS_ANIMATION_STYLE = "lyrics_animation_style"
    private const val PERSISTENT_QUEUE = "persistent_queue"
    private const val CONTINUE_PLAYBACK_DISMISSED = "continue_playback_when_dismissed"
    private const val ACCENT = "accent"
    private const val SPONSOR_BLOCK = "sponsor_block"
    private const val CROSSFADE_MS = "crossfade_ms"
    private const val LYRICS_LRCLIB = "lyrics_lrclib_first"
    private const val LYRICS_ROMANIZE = "lyrics_romanize"
    private const val STREAM_QUALITY = "stream_quality_tier"
    private const val DOWNLOAD_QUALITY = "download_quality_tier"
    private const val WIFI_QUALITY = "wifi_quality_tier"
    private const val MOBILE_QUALITY = "mobile_quality_tier"
    private const val STREAM_SOURCE_PRIORITY = "stream_source_priority"
    private const val ARTWORK_PRIORITY = "artwork_priority"
    private const val RECOGNITION_SOURCE = "recognition_source"
    private const val RECOGNITION_HISTORY_LIMIT = "recognition_history_limit"
    private const val EXPERIMENTAL_HOME_HEADER_ACCENT = "experimental_home_header_accent"
    private const val HOME_BACKGROUND_ENABLED = "home_background_enabled"
    private const val DEFAULT_OPEN_TAB = "default_open_tab"
    private const val QUICK_PICKS_DISPLAY = "quick_picks_display"
    private const val SHOW_LIKED_LIBRARY = "show_liked_library"
    private const val SHOW_DOWNLOADS_LIBRARY = "show_downloads_library"
    private const val SHOW_HISTORY_LIBRARY = "show_history_library"
    private const val SHOW_MOST_PLAYED_LIBRARY = "show_most_played_library"
    private const val SHOW_PLAYLISTS_LIBRARY = "show_playlists_library"
    private const val SHOW_LOCAL_LIBRARY = "show_local_library"
    private const val SHOW_RECOGNIZED_LIBRARY = "show_recognized_library"
    private const val CONTENT_LANG = "content_language_tag"
    private const val APP_LANG = "app_language_tag"
    private const val PROXY_ON = "proxy_enabled"
    private const val PROXY_EP = "proxy_endpoint"
    private const val NORM_VOL = "normalize_volume"
    private const val SKIP_SIL = "skip_silence"
    private const val AUTO_SKIP_ERROR = "auto_skip_error"
    private const val AUTO_BACKUP = "auto_backup"
    private const val AUTO_CHECK_UPDATES = "auto_check_updates"
    private const val UPDATE_NOTIFICATIONS = "update_notifications"

    private val _state = MutableStateFlow(FoxyCustomization())
    val state: StateFlow<FoxyCustomization> = _state
    private var appContext: Context? = null

    private fun normalizePlayerProgressStyle(value: Int): Int = if (value == 1) 1 else 0

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
            disableAnimations = prefs.getBoolean(DISABLE_ANIMATIONS, false),
            hapticFeedback = prefs.getBoolean(HAPTIC_FEEDBACK, true),
            playerProgressStyle = normalizePlayerProgressStyle(
                prefs.getInt(PLAYER_PROGRESS_STYLE, 0),
            ),
            playerSeekMotion = 0,
            playerBackgroundStyle = prefs.getInt(PLAYER_BACKGROUND_STYLE, 0).coerceIn(0, 3),
            playerStyle = prefs.getInt(PLAYER_STYLE, 0).coerceIn(0, 2),
            playerButtonsStyle = prefs.getInt(PLAYER_BUTTONS_STYLE, 0).coerceIn(0, 2),
            enableLiquidGlassLayout = prefs.getBoolean(ENABLE_LIQUID_GLASS_LAYOUT, false),
            miniPlayerStyle = prefs.getInt(MINI_PLAYER_STYLE, 0).coerceIn(0, 2),
            bottomNavigationStyle = prefs.getInt(BOTTOM_NAV_STYLE, 0).coerceIn(0, 2),
            playerArtworkShape = prefs.getInt(PLAYER_ARTWORK_SHAPE, 0).coerceIn(0, 2),
            hidePlayerArtwork = prefs.getBoolean(HIDE_PLAYER_ARTWORK, false),
            cropArtworkSquare = prefs.getBoolean(CROP_ARTWORK_SQUARE, true),
            thumbnailCornerRadius = prefs.getInt(THUMBNAIL_RADIUS, 16).coerceIn(0, 40),
            lyricsAnimationStyle = prefs.getInt(LYRICS_ANIMATION_STYLE, 1).coerceIn(0, 5),
            persistentQueue = prefs.getBoolean(PERSISTENT_QUEUE, true),
            continuePlaybackWhenDismissed = prefs.getBoolean(CONTINUE_PLAYBACK_DISMISSED, false),
            accentArgb = prefs.getInt(ACCENT, 0xFFFFFFFF.toInt()),
            sponsorBlockEnabled = prefs.getBoolean(SPONSOR_BLOCK, true),
            crossfadeMs = prefs.getInt(CROSSFADE_MS, 0).let { v ->
                when (v) {
                    3000, 5000, 8000, 12000 -> v
                    else -> 0
                }
            },
            lyricsPreferLrclib = prefs.getBoolean(LYRICS_LRCLIB, true),
            lyricsRomanize = prefs.getBoolean(LYRICS_ROMANIZE, false),
            streamQualityTier = prefs.getInt(STREAM_QUALITY, 2).coerceIn(0, 4),
            downloadQualityTier = prefs.getInt(DOWNLOAD_QUALITY, 2).coerceIn(0, 4),
            wifiQualityTier = prefs.getInt(WIFI_QUALITY, -1).coerceIn(-1, 4),
            mobileQualityTier = prefs.getInt(MOBILE_QUALITY, -1).coerceIn(-1, 4),
            streamSourcePriority = prefs.getInt(STREAM_SOURCE_PRIORITY, 0).coerceIn(0, 2),
            artworkPriority = prefs.getInt(ARTWORK_PRIORITY, 0).coerceIn(0, 3),
            recognitionSource = prefs.getInt(RECOGNITION_SOURCE, 0).coerceIn(0, 1),
            recognitionHistoryLimit = prefs.getInt(RECOGNITION_HISTORY_LIMIT, 40).coerceIn(10, 100),
            experimentalHomeHeaderAccent = prefs.getBoolean(EXPERIMENTAL_HOME_HEADER_ACCENT, false),
            homeBackgroundEnabled = prefs.getBoolean(HOME_BACKGROUND_ENABLED, false),
            defaultOpenTab = prefs.getInt(DEFAULT_OPEN_TAB, 0).let { if (it == 1 || it == 3) it else 0 },
            quickPicksDisplayMode = prefs.getInt(QUICK_PICKS_DISPLAY, 0).coerceIn(0, 1),
            showLikedInLibrary = prefs.getBoolean(SHOW_LIKED_LIBRARY, true),
            showDownloadsInLibrary = prefs.getBoolean(SHOW_DOWNLOADS_LIBRARY, true),
            showHistoryInLibrary = prefs.getBoolean(SHOW_HISTORY_LIBRARY, true),
            showMostPlayedInLibrary = prefs.getBoolean(SHOW_MOST_PLAYED_LIBRARY, true),
            showPlaylistsInLibrary = prefs.getBoolean(SHOW_PLAYLISTS_LIBRARY, true),
            showLocalInLibrary = prefs.getBoolean(SHOW_LOCAL_LIBRARY, true),
            showRecognizedInLibrary = prefs.getBoolean(SHOW_RECOGNIZED_LIBRARY, true),
            contentLanguageTag = prefs.getString(CONTENT_LANG, "en-US") ?: "en-US",
            appLanguageTag = prefs.getString(APP_LANG, "").orEmpty(),
            proxyEnabled = prefs.getBoolean(PROXY_ON, false),
            proxyEndpoint = prefs.getString(PROXY_EP, "").orEmpty(),
            normalizeVolume = prefs.getBoolean(NORM_VOL, false),
            skipSilence = prefs.getBoolean(SKIP_SIL, false),
            autoSkipNextOnError = prefs.getBoolean(AUTO_SKIP_ERROR, false),
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
            ?.putBoolean(DISABLE_ANIMATIONS, next.disableAnimations)
            ?.putBoolean(HAPTIC_FEEDBACK, next.hapticFeedback)
            ?.putInt(
                PLAYER_PROGRESS_STYLE,
                normalizePlayerProgressStyle(next.playerProgressStyle),
            )
            ?.putInt(PLAYER_SEEK_MOTION, 0)
            ?.putInt(PLAYER_BACKGROUND_STYLE, next.playerBackgroundStyle.coerceIn(0, 3))
            ?.putInt(PLAYER_STYLE, next.playerStyle.coerceIn(0, 2))
            ?.putInt(PLAYER_BUTTONS_STYLE, next.playerButtonsStyle.coerceIn(0, 2))
            ?.putBoolean(ENABLE_LIQUID_GLASS_LAYOUT, next.enableLiquidGlassLayout)
            ?.putInt(MINI_PLAYER_STYLE, next.miniPlayerStyle.coerceIn(0, 2))
            ?.putInt(BOTTOM_NAV_STYLE, next.bottomNavigationStyle.coerceIn(0, 2))
            ?.putInt(PLAYER_ARTWORK_SHAPE, next.playerArtworkShape.coerceIn(0, 2))
            ?.putBoolean(HIDE_PLAYER_ARTWORK, next.hidePlayerArtwork)
            ?.putBoolean(CROP_ARTWORK_SQUARE, next.cropArtworkSquare)
            ?.putInt(THUMBNAIL_RADIUS, next.thumbnailCornerRadius.coerceIn(0, 40))
            ?.putInt(LYRICS_ANIMATION_STYLE, next.lyricsAnimationStyle.coerceIn(0, 5))
            ?.putBoolean(PERSISTENT_QUEUE, next.persistentQueue)
            ?.putBoolean(CONTINUE_PLAYBACK_DISMISSED, next.continuePlaybackWhenDismissed)
            ?.putInt(ACCENT, next.accentArgb)
            ?.putBoolean(SPONSOR_BLOCK, next.sponsorBlockEnabled)
            ?.putInt(CROSSFADE_MS, next.crossfadeMs)
            ?.putBoolean(LYRICS_LRCLIB, next.lyricsPreferLrclib)
            ?.putBoolean(LYRICS_ROMANIZE, next.lyricsRomanize)
            ?.putInt(STREAM_QUALITY, next.streamQualityTier.coerceIn(0, 4))
            ?.putInt(DOWNLOAD_QUALITY, next.downloadQualityTier.coerceIn(0, 4))
            ?.putInt(WIFI_QUALITY, next.wifiQualityTier.coerceIn(-1, 4))
            ?.putInt(MOBILE_QUALITY, next.mobileQualityTier.coerceIn(-1, 4))
            ?.putInt(STREAM_SOURCE_PRIORITY, next.streamSourcePriority.coerceIn(0, 2))
            ?.putInt(ARTWORK_PRIORITY, next.artworkPriority.coerceIn(0, 3))
            ?.putInt(RECOGNITION_SOURCE, next.recognitionSource.coerceIn(0, 1))
            ?.putInt(RECOGNITION_HISTORY_LIMIT, next.recognitionHistoryLimit.coerceIn(10, 100))
            ?.putBoolean(EXPERIMENTAL_HOME_HEADER_ACCENT, next.experimentalHomeHeaderAccent)
            ?.putBoolean(HOME_BACKGROUND_ENABLED, next.homeBackgroundEnabled)
            ?.putInt(DEFAULT_OPEN_TAB, if (next.defaultOpenTab == 1 || next.defaultOpenTab == 3) next.defaultOpenTab else 0)
            ?.putInt(QUICK_PICKS_DISPLAY, next.quickPicksDisplayMode.coerceIn(0, 1))
            ?.putBoolean(SHOW_LIKED_LIBRARY, next.showLikedInLibrary)
            ?.putBoolean(SHOW_DOWNLOADS_LIBRARY, next.showDownloadsInLibrary)
            ?.putBoolean(SHOW_HISTORY_LIBRARY, next.showHistoryInLibrary)
            ?.putBoolean(SHOW_MOST_PLAYED_LIBRARY, next.showMostPlayedInLibrary)
            ?.putBoolean(SHOW_PLAYLISTS_LIBRARY, next.showPlaylistsInLibrary)
            ?.putBoolean(SHOW_LOCAL_LIBRARY, next.showLocalInLibrary)
            ?.putBoolean(SHOW_RECOGNIZED_LIBRARY, next.showRecognizedInLibrary)
            ?.putString(CONTENT_LANG, next.contentLanguageTag)
            ?.putString(APP_LANG, next.appLanguageTag)
            ?.putBoolean(PROXY_ON, next.proxyEnabled)
            ?.putString(PROXY_EP, next.proxyEndpoint)
            ?.putBoolean(NORM_VOL, next.normalizeVolume)
            ?.putBoolean(SKIP_SIL, next.skipSilence)
            ?.putBoolean(AUTO_SKIP_ERROR, next.autoSkipNextOnError)
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
    val baseAccent = Color(0xFFFFFFFF)
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
