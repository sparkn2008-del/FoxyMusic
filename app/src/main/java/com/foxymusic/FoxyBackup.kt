package com.foxymusic

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object FoxyBackup {
    private const val BACKUP_DIR = "foxy_backups"
    private const val MIN_AUTO_BACKUP_INTERVAL_MS = 10L * 60L * 1000L

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    @Volatile
    private var lastAutoBackupAtMs = 0L

    fun requestAutoBackup(context: Context) {
        if (!FoxySettings.state.value.autoBackupEnabled) return
        val now = System.currentTimeMillis()
        if (now - lastAutoBackupAtMs < MIN_AUTO_BACKUP_INTERVAL_MS) return
        lastAutoBackupAtMs = now
        val app = context.applicationContext
        scope.launch {
            runCatching { create(app, automatic = true) }
        }
    }

    fun create(context: Context, automatic: Boolean = false): Map<String, Any?> {
        val file = nextBackupFile(context, automatic)
        val root = JSONObject().apply {
            put("schema", 1)
            put("createdAt", System.currentTimeMillis())
            put("automatic", automatic)
            put("settings", FoxySettings.state.value.toBackupJson())
            put("library", FoxyLibraryStore.snapshotJson())
            put("playlists", FoxyUserPlaylists.snapshotJson())
        }
        file.writeText(root.toString(2))
        pruneOldBackups(context)
        return statusMap(file)
    }

    fun restoreLatest(context: Context): Map<String, Any?> {
        val file = latestBackupFile(context)
            ?: return mapOf("ok" to false, "error" to "No backup found")
        val root = JSONObject(file.readText())
        root.optJSONObject("settings")?.let { FoxySettings.restoreFromBackupJson(it) }
        root.optJSONObject("library")?.let { FoxyLibraryStore.restoreFromJson(it) }
        root.optJSONArray("playlists")?.let { FoxyUserPlaylists.restoreFromJson(it) }
        return statusMap(file) + mapOf("restored" to true)
    }

    fun status(context: Context): Map<String, Any?> {
        val latest = latestBackupFile(context)
        return if (latest == null) {
            mapOf("ok" to true, "exists" to false)
        } else {
            statusMap(latest)
        }
    }

    private fun backupDir(context: Context): File =
        File(context.filesDir, BACKUP_DIR).apply { mkdirs() }

    private fun nextBackupFile(context: Context, automatic: Boolean): File {
        val fmt = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val prefix = if (automatic) "auto" else "manual"
        return File(backupDir(context), "foxy-$prefix-${fmt.format(Date())}.json")
    }

    private fun latestBackupFile(context: Context): File? =
        backupDir(context)
            .listFiles { f -> f.isFile && f.name.endsWith(".json") }
            ?.maxByOrNull { it.lastModified() }

    private fun pruneOldBackups(context: Context) {
        val files = backupDir(context)
            .listFiles { f -> f.isFile && f.name.endsWith(".json") }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()
        files.drop(12).forEach { runCatching { it.delete() } }
    }

    private fun statusMap(file: File): Map<String, Any?> =
        mapOf(
            "ok" to true,
            "exists" to true,
            "path" to file.absolutePath,
            "fileName" to file.name,
            "updatedAt" to file.lastModified(),
            "bytes" to file.length(),
        )
}

fun Song.toBackupJson(): JSONObject = JSONObject().apply {
    put("videoId", videoId)
    put("title", title)
    put("artist", artist)
    put("thumbnail", thumbnail)
    put("duration", duration ?: "")
    put("album", album ?: "")
    put("localPath", localPath ?: "")
    put("isDownloaded", isDownloaded)
    put("artworkUrl", artworkUrl ?: "")
}

fun JSONArray?.songsFromBackupJson(): List<Song> {
    val arr = this ?: return emptyList()
    val out = ArrayList<Song>()
    for (i in 0 until arr.length()) {
        val o = arr.optJSONObject(i) ?: continue
        val videoId = o.optString("videoId").trim()
        if (videoId.isBlank()) continue
        out += Song(
            videoId = videoId,
            title = o.optString("title").ifBlank { "Unknown title" },
            artist = o.optString("artist").ifBlank { "Unknown artist" },
            thumbnail = o.optString("thumbnail"),
            duration = o.optString("duration").takeIf { it.isNotBlank() },
            album = o.optString("album").takeIf { it.isNotBlank() },
            localPath = o.optString("localPath").takeIf { it.isNotBlank() },
            isDownloaded = o.optBoolean("isDownloaded"),
            artworkUrl = o.optString("artworkUrl").takeIf { it.isNotBlank() },
        )
    }
    return out
}

private fun FoxyCustomization.toBackupJson(): JSONObject = JSONObject().apply {
    put("themeMode", themeMode)
    put("themePalette", themePalette)
    put("blurEffects", blurEffects)
    put("compactPlayer", compactPlayer)
    put("gestureControls", gestureControls)
    put("iconScale", iconScale)
    put("bottomNavScale", bottomNavScale)
    put("gridColumns", gridColumns)
    put("showBottomLabels", showBottomLabels)
    put("disableAnimations", disableAnimations)
    put("hapticFeedback", hapticFeedback)
    put("dynamicSongColors", dynamicSongColors)
    put("saveHistory", saveHistory)
    put("persistentQueue", persistentQueue)
    put("continuePlaybackWhenDismissed", continuePlaybackWhenDismissed)
    put("accentArgb", accentArgb)
    put("sponsorBlockEnabled", sponsorBlockEnabled)
    put("crossfadeMs", crossfadeMs)
    put("lyricsPreferLrclib", lyricsPreferLrclib)
    put("lyricsRomanize", lyricsRomanize)
    put("playerButtonsStyle", playerButtonsStyle)
    put("miniPlayerStyle", miniPlayerStyle)
    put("bottomNavigationStyle", bottomNavigationStyle)
    put("hidePlayerArtwork", hidePlayerArtwork)
    put("cropArtworkSquare", cropArtworkSquare)
    put("thumbnailCornerRadius", thumbnailCornerRadius)
    put("streamQualityTier", streamQualityTier)
    put("downloadQualityTier", downloadQualityTier)
    put("streamSourcePriority", streamSourcePriority)
    put("homeBackgroundEnabled", homeBackgroundEnabled)
    put("defaultOpenTab", defaultOpenTab)
    put("quickPicksDisplayMode", quickPicksDisplayMode)
    put("showLikedInLibrary", showLikedInLibrary)
    put("showDownloadsInLibrary", showDownloadsInLibrary)
    put("showHistoryInLibrary", showHistoryInLibrary)
    put("showMostPlayedInLibrary", showMostPlayedInLibrary)
    put("showPlaylistsInLibrary", showPlaylistsInLibrary)
    put("showLocalInLibrary", showLocalInLibrary)
    put("showRecognizedInLibrary", showRecognizedInLibrary)
    put("contentLanguageTag", contentLanguageTag)
    put("appLanguageTag", appLanguageTag)
    put("proxyEnabled", proxyEnabled)
    put("proxyEndpoint", proxyEndpoint)
    put("normalizeVolume", normalizeVolume)
    put("skipSilence", skipSilence)
    put("autoSkipNextOnError", autoSkipNextOnError)
    put("autoBackupEnabled", autoBackupEnabled)
    put("autoCheckUpdates", autoCheckUpdates)
    put("updateNotifications", updateNotifications)
}

private fun FoxySettings.restoreFromBackupJson(json: JSONObject) {
    update { current ->
        current.copy(
            themeMode = json.optInt("themeMode", current.themeMode).coerceIn(0, 2),
            themePalette = json.optInt("themePalette", current.themePalette)
                .coerceIn(0, FoxyThemePresets.lastIndex),
            blurEffects = json.optBoolean("blurEffects", current.blurEffects),
            compactPlayer = json.optBoolean("compactPlayer", current.compactPlayer),
            gestureControls = json.optBoolean("gestureControls", current.gestureControls),
            iconScale = json.optInt("iconScale", current.iconScale).coerceIn(0, 2),
            bottomNavScale = json.optInt("bottomNavScale", current.bottomNavScale)
                .coerceIn(0, 2),
            gridColumns = json.optInt("gridColumns", current.gridColumns).coerceIn(2, 4),
            showBottomLabels = json.optBoolean("showBottomLabels", current.showBottomLabels),
            disableAnimations = json.optBoolean(
                "disableAnimations",
                current.disableAnimations,
            ),
            hapticFeedback = json.optBoolean("hapticFeedback", current.hapticFeedback),
            dynamicSongColors = json.optBoolean("dynamicSongColors", current.dynamicSongColors),
            saveHistory = json.optBoolean("saveHistory", current.saveHistory),
            persistentQueue = json.optBoolean("persistentQueue", current.persistentQueue),
            continuePlaybackWhenDismissed = json.optBoolean(
                "continuePlaybackWhenDismissed",
                current.continuePlaybackWhenDismissed,
            ),
            accentArgb = json.optInt("accentArgb", current.accentArgb),
            sponsorBlockEnabled = json.optBoolean(
                "sponsorBlockEnabled",
                current.sponsorBlockEnabled,
            ),
            crossfadeMs = json.optInt("crossfadeMs", current.crossfadeMs).let { v ->
                when (v) {
                    0, 3000, 5000, 8000, 12000 -> v
                    else -> current.crossfadeMs
                }
            },
            lyricsPreferLrclib = json.optBoolean(
                "lyricsPreferLrclib",
                current.lyricsPreferLrclib,
            ),
            lyricsRomanize = json.optBoolean("lyricsRomanize", current.lyricsRomanize),
            playerButtonsStyle = json.optInt("playerButtonsStyle", current.playerButtonsStyle)
                .coerceIn(0, 2),
            miniPlayerStyle = json.optInt("miniPlayerStyle", current.miniPlayerStyle)
                .coerceIn(0, 2),
            bottomNavigationStyle = json.optInt(
                "bottomNavigationStyle",
                current.bottomNavigationStyle,
            ).coerceIn(0, 2),
            hidePlayerArtwork = json.optBoolean(
                "hidePlayerArtwork",
                current.hidePlayerArtwork,
            ),
            cropArtworkSquare = json.optBoolean(
                "cropArtworkSquare",
                current.cropArtworkSquare,
            ),
            thumbnailCornerRadius = json.optInt(
                "thumbnailCornerRadius",
                current.thumbnailCornerRadius,
            ).coerceIn(0, 40),
            streamQualityTier = json.optInt("streamQualityTier", current.streamQualityTier)
                .coerceIn(0, 4),
            downloadQualityTier = json.optInt("downloadQualityTier", current.downloadQualityTier)
                .coerceIn(0, 4),
            streamSourcePriority = json.optInt("streamSourcePriority", current.streamSourcePriority)
                .coerceIn(0, 2),
            homeBackgroundEnabled = json.optBoolean(
                "homeBackgroundEnabled",
                current.homeBackgroundEnabled,
            ),
            defaultOpenTab = json.optInt("defaultOpenTab", current.defaultOpenTab)
                .let { if (it == 1 || it == 3) it else 0 },
            quickPicksDisplayMode = json.optInt(
                "quickPicksDisplayMode",
                current.quickPicksDisplayMode,
            ).coerceIn(0, 1),
            showLikedInLibrary = json.optBoolean(
                "showLikedInLibrary",
                current.showLikedInLibrary,
            ),
            showDownloadsInLibrary = json.optBoolean(
                "showDownloadsInLibrary",
                current.showDownloadsInLibrary,
            ),
            showHistoryInLibrary = json.optBoolean(
                "showHistoryInLibrary",
                current.showHistoryInLibrary,
            ),
            showMostPlayedInLibrary = json.optBoolean(
                "showMostPlayedInLibrary",
                current.showMostPlayedInLibrary,
            ),
            showPlaylistsInLibrary = json.optBoolean(
                "showPlaylistsInLibrary",
                current.showPlaylistsInLibrary,
            ),
            showLocalInLibrary = json.optBoolean(
                "showLocalInLibrary",
                current.showLocalInLibrary,
            ),
            showRecognizedInLibrary = json.optBoolean(
                "showRecognizedInLibrary",
                current.showRecognizedInLibrary,
            ),
            contentLanguageTag = json.optString(
                "contentLanguageTag",
                current.contentLanguageTag,
            ).ifBlank { current.contentLanguageTag },
            appLanguageTag = json.optString("appLanguageTag", current.appLanguageTag),
            proxyEnabled = json.optBoolean("proxyEnabled", current.proxyEnabled),
            proxyEndpoint = json.optString("proxyEndpoint", current.proxyEndpoint),
            normalizeVolume = json.optBoolean("normalizeVolume", current.normalizeVolume),
            skipSilence = json.optBoolean("skipSilence", current.skipSilence),
            autoSkipNextOnError = json.optBoolean(
                "autoSkipNextOnError",
                current.autoSkipNextOnError,
            ),
            autoBackupEnabled = json.optBoolean("autoBackupEnabled", current.autoBackupEnabled),
            autoCheckUpdates = json.optBoolean("autoCheckUpdates", current.autoCheckUpdates),
            updateNotifications = json.optBoolean(
                "updateNotifications",
                current.updateNotifications,
            ),
        )
    }
}
