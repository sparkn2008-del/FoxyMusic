package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AudioFile
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.BatterySaver
import androidx.compose.material.icons.rounded.Bluetooth
import androidx.compose.material.icons.rounded.Brush
import androidx.compose.material.icons.rounded.Cached
import androidx.compose.material.icons.rounded.CheckBox
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.DensityMedium
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Equalizer
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Lyrics
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material.icons.rounded.Update
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController

private val historySongs = listOf(
    Song("history-1", "fear", "NILXRO - 1:42", ""),
    Song("history-2", "Ride Or Die, Pt. 2", "Sevdaliza - 2:39", ""),
    Song("history-3", "Boyfriend", "Karan Aujla, Ikky - 2:41", ""),
    Song("history-4", "KALYANI", "ARJN, KDS, FIFTY4, RONN - 3:55", ""),
    Song("history-5", "Mann Mera", "Gajendra Verma - 3:47", ""),
    Song("history-6", "Atif aslam (AADAT UNPLUGGED)", "R z Musical PANDA - 4:25", "")
)

@Composable
fun HistoryScreen(navController: NavController) {
    FoxyBackScaffold("History", navController) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(listOf("Local", "Remote")) { FoxyPillChip(it, selected = it == "Local") }
            }
        }
        item { FoxySectionTitle("Today") }
        items(historySongs) { song ->
            FoxySongRow(song, trailing = {
                val colors = foxyPalette()
                Icon(Icons.Rounded.DensityMedium, contentDescription = "More", tint = colors.muted)
            })
        }
    }
}

@Composable
fun StatsScreen(navController: NavController) {
    FoxyBackScaffold("Stats", navController) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(listOf("Continuous", "1 week", "1 month", "3 months")) { FoxyPillChip(it, selected = it == "1 week") }
            }
        }
        item { FoxySectionTitle("2 playlists") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), modifier = Modifier.fillMaxWidth()) {
                StatTile("Weekly Most", Icons.Rounded.History, Modifier.weight(1f))
                StatTile("Monthly Most", Icons.Rounded.TrendingUp, Modifier.weight(1f))
            }
        }
        item { FoxySectionTitle("114 Songs", action = "Play all") }
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                items(historySongs.take(4)) { song -> StatSongCard(song) }
            }
        }
        item { FoxySectionTitle("147 Artists") }
        items(historySongs.take(3)) { song -> FoxySongRow(song) }
    }
}

@Composable
fun SettingsHubScreen(navController: NavController) {
    FoxyBackScaffold("Settings", navController) {
        item { SettingsNavRow(Icons.Rounded.GraphicEq, "Player and audio", "Playback, queue, sleep timer", "settings_player", navController) }
        item { SettingsNavRow(Icons.Rounded.Palette, "Appearance", "Player, lyrics, and layout style", "appearance", navController) }
        item { SettingsNavRow(Icons.Rounded.Storage, "Storage", "Downloads and cache", "storage", navController) }
        item { SettingsNavRow(Icons.Rounded.Update, "Updater", "Version and update checks", "updater", navController) }
        item { SettingsNavRow(Icons.Rounded.Info, "About", "Project and credits", "about", navController) }
    }
}

@Composable
fun PlayerAudioScreen(navController: NavController) {
    var crossfade by remember { mutableStateOf(true) }
    var skipSilence by remember { mutableStateOf(false) }
    var normalize by remember { mutableStateOf(true) }
    var autoplay by remember { mutableStateOf(true) }
    var persistentQueue by remember { mutableStateOf(true) }
    var cacheOnLike by remember { mutableStateOf(false) }
    var crossfadeDuration by remember { mutableFloatStateOf(5f) }

    FoxyBackScaffold("Player and audio", navController) {
        item { FoxyScreenLabel("Player") }
        item { FoxyListTile(Icons.Rounded.AudioFile, "Audio quality", "High") }
        item { FoxyToggleRow(Icons.Rounded.Sync, "Crossfade", "Fades out the current song as the next one fades in", crossfade) { crossfade = it } }
        item {
            FoxyDemoSliderRow(Icons.Rounded.Timer, "Crossfade duration", "${crossfadeDuration.toInt()} seconds", crossfadeDuration, 0f..12f) {
                crossfadeDuration = it
            }
        }
        item { FoxyToggleRow(Icons.Rounded.SkipNext, "Skip silence", "Fast-forward through silent parts of songs", skipSilence) { skipSilence = it } }
        item { FoxyToggleRow(Icons.Rounded.VolumeUp, "Audio normalization", null, normalize) { normalize = it } }
        item { FoxyScreenLabel("Sleep timer") }
        item { FoxyListTile(Icons.Rounded.Add, "Add alarm", "No alarms yet. Add one to start scheduled playback") }
        item { FoxyToggleRow(Icons.Rounded.BatterySaver, "Battery optimization", "Disable optimization for reliable alarm behavior", false) {} }
        item { FoxyScreenLabel("Queue") }
        item { FoxyToggleRow(Icons.Rounded.QueueMusic, "Persistent queue", "Restore your last queue when the app starts", persistentQueue) { persistentQueue = it } }
        item { FoxyToggleRow(Icons.Rounded.PlayArrow, "Autoplay", "Automatically play the next song when the current one ends", autoplay) { autoplay = it } }
        item { FoxyToggleRow(Icons.Rounded.Download, "Auto-download on like", "Automatically download songs when you like them", cacheOnLike) { cacheOnLike = it } }
    }
}

@Composable
fun AppearanceScreen(navController: NavController) {
    val settings by FoxySettings.state.collectAsState()
    val colors = foxyPalette()

    FoxyBackScaffold("Appearance", navController) {
        item { FoxyScreenLabel("Theme") }
        item {
            AppearanceChoiceRow(
                title = "App theme",
                subtitle = "System, AMOLED dark, or light",
                options = listOf("System", "Dark", "Light"),
                selectedIndex = settings.themeMode,
                onSelect = { selected -> FoxySettings.update { it.copy(themeMode = selected) } }
            )
        }
        item {
            FoxyToggleRow(
                Icons.Rounded.AutoAwesome,
                "Match current song artwork",
                "Automatically chooses the accent from the playing song thumbnail",
                settings.dynamicSongColors
            ) { enabled -> FoxySettings.update { it.copy(dynamicSongColors = enabled) } }
        }
        item {
            ThemePresetPicker(
                selectedIndex = settings.themePalette,
                dynamicSongColors = settings.dynamicSongColors,
                onPick = { selected ->
                    val preset = FoxyThemePresets[selected]
                    FoxySettings.update { it.copy(themePalette = selected, accentArgb = preset.accent.toArgb()) }
                }
            )
        }
        item {
            AccentSwatchRow(selectedAccent = settings.accent) { selected ->
                FoxySettings.update { it.copy(accentArgb = selected.toArgb(), dynamicSongColors = false) }
            }
        }
        item { FoxyScreenLabel("Interface") }
        item { FoxyToggleRow(Icons.Rounded.Brush, "Blur effects", "Use blurred artwork surfaces in the player", settings.blurEffects) { enabled -> FoxySettings.update { it.copy(blurEffects = enabled) } } }
        item { FoxyToggleRow(Icons.Rounded.LibraryMusic, "Compact mini-player", "Smaller player above navigation", settings.compactPlayer) { enabled -> FoxySettings.update { it.copy(compactPlayer = enabled) } } }
        item {
            AppearanceChoiceRow(
                title = "Icon size",
                subtitle = "Controls action and toolbar icons",
                options = listOf("Small", "Medium", "Large"),
                selectedIndex = settings.iconScale,
                onSelect = { selected -> FoxySettings.update { it.copy(iconScale = selected) } }
            )
        }
        item {
            AppearanceChoiceRow(
                title = "Bottom tab size",
                subtitle = "Controls the navigation bar height",
                options = listOf("Small", "Medium", "Large"),
                selectedIndex = settings.bottomNavScale,
                onSelect = { selected -> FoxySettings.update { it.copy(bottomNavScale = selected) } }
            )
        }
        item { FoxyToggleRow(Icons.Rounded.GridView, "Show bottom labels", "Display text below Home, Search, Library, and Me", settings.showBottomLabels) { enabled -> FoxySettings.update { it.copy(showBottomLabels = enabled) } } }
        item { FoxyScreenLabel("Mini-player") }
        item { FoxyListTile(Icons.Rounded.GridView, "Mini-player background style", if (settings.dynamicSongColors) "Artwork accent" else "Theme accent") }
        item { FoxyScreenLabel("Player") }
        item { FoxyListTile(Icons.Rounded.Brush, "Player background style", if (settings.blurEffects) "Blurred artwork" else "Solid theme") }
        item { FoxyListTile(Icons.Rounded.Settings, "Player button colors", "Accent: ${FoxyThemePresets[settings.themePalette.coerceIn(0, FoxyThemePresets.lastIndex)].name}") }
        item {
            AppearanceChoiceRow(
                title = "Player progress style",
                subtitle = "Used by the Flutter player",
                options = listOf("Line", "Pill", "Wave", "Squiggle"),
                selectedIndex = settings.playerProgressStyle,
                onSelect = { selected -> FoxySettings.update { it.copy(playerProgressStyle = selected) } }
            )
        }
        item { FoxyToggleRow(Icons.Rounded.Sync, "Enable swipe to change song", null, settings.gestureControls) { enabled -> FoxySettings.update { it.copy(gestureControls = enabled) } } }
        item { FoxyScreenLabel("Lyrics") }
        item { FoxyListTile(Icons.Rounded.Lyrics, "Enable glowing lyrics effect", "Follows ${if (settings.dynamicSongColors) "song colors" else "theme colors"}") }
        item { FoxyListTile(Icons.Rounded.Lyrics, "Lyrics text size", "24 sp") }
        item { FoxyListTile(Icons.Rounded.Lyrics, "Default open tab", "Library") }
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(color = colors.surface)
                    .padding(18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(48.dp).clip(CircleShape).background(colors.accent))
                Column(Modifier.padding(start = 14.dp)) {
                    Text("Live preview", color = Color.White, fontWeight = FontWeight.Bold)
                    Text("The whole app now reads this palette, including Flutter theme payloads.", color = colors.muted, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
fun StorageScreen(navController: NavController) {
    var songCache by remember { mutableStateOf(true) }
    var songCacheSize by remember { mutableFloatStateOf(1f) }
    var imageCacheSize by remember { mutableFloatStateOf(0.5f) }

    FoxyBackScaffold("Storage", navController) {
        item { FoxyScreenLabel("Storage") }
        item { FoxyListTile(Icons.Rounded.Download, "Downloaded songs", "572 MB") }
        item { FoxyListTile(Icons.Rounded.DensityMedium, "Clear all downloads") }
        item { FoxyScreenLabel("Song Cache") }
        item { FoxyToggleRow(Icons.Rounded.Cached, "Enable song cache", "Automatically cache songs for faster future playback", songCache) { songCache = it } }
        item { FoxyDemoSliderRow(Icons.Rounded.Cached, "Max song cache size", "${songCacheSize.toInt()} GB", songCacheSize, 0f..4f) { songCacheSize = it } }
        item { FoxyListTile(Icons.Rounded.DensityMedium, "Clear song cache") }
        item { FoxyScreenLabel("Image Cache") }
        item { FoxyDemoSliderRow(Icons.Rounded.Search, "Max image cache size", "${(imageCacheSize * 1024).toInt()} MB", imageCacheSize, 0f..1f) { imageCacheSize = it } }
        item { FoxyListTile(Icons.Rounded.DensityMedium, "Clear image cache") }
    }
}

@Composable
fun UpdaterScreen(navController: NavController) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val settings by FoxySettings.state.collectAsState()
    val (versionName, _) = remember(context) { FoxyGithubUpdate.installedVersion(context) }
    var checkStatus by remember { mutableStateOf<String?>(null) }

    FoxyBackScaffold("Updater", navController) {
        item { FoxyScreenLabel("Current version") }
        item { FoxyListTile(Icons.Rounded.Update, "Version: $versionName", "GitHub releases") }
        item { FoxyScreenLabel("Update settings") }
        item {
            FoxyToggleRow(Icons.Rounded.Sync, "Automatically check for updates", null, settings.autoCheckUpdates) {
                FoxySettings.update { s -> s.copy(autoCheckUpdates = it) }
            }
        }
        item {
            FoxyToggleRow(Icons.Rounded.Alarm, "Enable update notifications", null, settings.updateNotifications) {
                FoxySettings.update { s -> s.copy(updateNotifications = it) }
            }
        }
        item {
            FoxyListTile(Icons.Rounded.Update, "Check for updates", checkStatus) {
                checkStatus = "Checking…"
                scope.launch(Dispatchers.IO) {
                    val result = FoxyGithubUpdate.checkForUpdate(context)
                    FoxyUpdatePrefs.setLastCheckMs(context, System.currentTimeMillis())
                    val status = when {
                        !result.ok -> result.error ?: "Check failed"
                        result.updateAvailable -> "Update: ${result.latestTag}"
                        else -> "Up to date (${result.latestTag.ifBlank { "latest" }})"
                    }
                    withContext(Dispatchers.Main) {
                        checkStatus = status
                    }
                    if (result.ok && result.updateAvailable && settings.updateNotifications) {
                        val tag = result.latestTag
                        if (tag.isNotBlank() && tag != FoxyUpdatePrefs.lastNotifiedTag(context)) {
                            FoxyUpdateNotifier.show(context, tag, result.htmlUrl, result.releaseNotes)
                            FoxyUpdatePrefs.setLastNotifiedTag(context, tag)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun AboutScreen(navController: NavController) {
    FoxyBackScaffold("About", navController) {
        item {
            val colors = foxyPalette()
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(color = colors.surface).padding(28.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = colors.accent, modifier = Modifier.size(58.dp))
                    Column(modifier = Modifier.padding(start = 20.dp)) {
                        Text("FoxyMusic", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold)
                        Text("v1.0", color = colors.accent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(modifier = Modifier.height(14.dp))
                Text(
                    "Made with ❤️ by Foxy Nish aka sparkn2008-del 🦊✨",
                    color = colors.muted,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                Text("github.com/sparkn2008-del/FoxyMusic", color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.height(22.dp))
            }
        }
        item { FoxyScreenLabel("Community & Info") }
        item { FoxyListTile(Icons.Rounded.Security, "Privacy-first local controls") }
        item { FoxyListTile(Icons.Rounded.Info, "Open-source friendly architecture") }
        item { FoxyListTile(Icons.Rounded.Favorite, "Made with ❤️ by Foxy Nish aka sparkn2008-del") }
    }
}

@Composable
private fun ThemePresetPicker(
    selectedIndex: Int,
    dynamicSongColors: Boolean,
    onPick: (Int) -> Unit
) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(color = colors.surface)
            .padding(16.dp)
    ) {
        Text("Themes", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
        Text(
            if (dynamicSongColors) "Preset surfaces stay active; accent can follow artwork." else "Pick a full FoxyMusic color system.",
            color = colors.muted,
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 3.dp, bottom = 12.dp)
        )
        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(FoxyThemePresets.indices.toList()) { index ->
                val preset = FoxyThemePresets[index]
                Column(
                    modifier = Modifier
                        .size(width = 172.dp, height = 126.dp)
                        .clip(RoundedCornerShape(18.dp))
                        .background(preset.surface)
                        .clickable { onPick(index) }
                        .padding(14.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(preset.background, preset.surfaceHigh, preset.accent).forEach { swatch ->
                            Box(Modifier.size(24.dp).clip(CircleShape).background(swatch))
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    Text(preset.name, color = Color.White, fontWeight = FontWeight.Black, maxLines = 1)
                    Text(
                        if (selectedIndex == index) "Selected" else preset.description,
                        color = if (selectedIndex == index) preset.accent else preset.muted,
                        fontSize = 11.sp,
                        maxLines = 2
                    )
                }
            }
        }
    }
}

@Composable
private fun AccentSwatchRow(selectedAccent: Color, onPick: (Color) -> Unit) {
    val colors = foxyPalette()
    val accents = listOf(
        Color(0xFFFF1744),
        Color(0xFFFF6F91),
        Color(0xFFFFC857),
        Color(0xFFA5D76E),
        Color(0xFF54E0C1),
        Color(0xFF6CB6FF),
        Color(0xFFB58CFF),
        Color(0xFFFFFFFF)
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(color = colors.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text("Accent", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Text("Manual swatches turn artwork matching off", color = colors.muted, fontSize = 12.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
            accents.forEach { accent ->
                Box(
                    modifier = Modifier
                        .size(if (selectedAccent == accent) 34.dp else 28.dp)
                        .clip(CircleShape)
                        .background(accent)
                        .clickable { onPick(accent) }
                )
            }
        }
    }
}

@Composable
private fun AppearanceChoiceRow(
    title: String,
    subtitle: String,
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit
) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(color = colors.surface)
            .padding(16.dp)
    ) {
        Text(title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        Text(subtitle, color = colors.muted, fontSize = 12.sp)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(top = 12.dp)
        ) {
            options.forEachIndexed { index, label ->
                Button(
                    onClick = { onSelect(index) },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (selectedIndex == index) colors.accent else colors.surfaceHigh,
                        contentColor = if (selectedIndex == index) Color.Black else Color.White
                    )
                ) {
                    Text(label, fontSize = 12.sp, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun FoxyBackScaffold(
    title: String,
    navController: NavController,
    content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit
) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier.fillMaxSize().background(color = colors.background)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 18.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { navController.popBackStack() }) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = "Back", tint = Color.White, modifier = Modifier.size(34.dp))
            }
            Text(title, color = Color.White, fontSize = 34.sp, modifier = Modifier.padding(start = 8.dp))
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content
        )
    }
}

@Composable
private fun FoxyScreenLabel(label: String) {
    val colors = foxyPalette()
    Text(label, color = colors.accent, fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 20.dp, bottom = 4.dp))
}

@Composable
private fun SettingsNavRow(icon: ImageVector, title: String, subtitle: String, route: String, navController: NavController) {
    FoxyListTile(icon = icon, title = title, subtitle = subtitle, onClick = { navController.navigate(route) })
}

@Composable
private fun FoxyDemoSliderRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit
) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(color = colors.surface).padding(14.dp)
    ) {
        FoxyListTile(icon, title, subtitle)
        Slider(value = value, onValueChange = onValueChange, valueRange = valueRange)
    }
}

@Composable
private fun StatTile(title: String, icon: ImageVector, modifier: Modifier) {
    val colors = foxyPalette()
    Column(modifier = modifier) {
        Box(modifier = Modifier.fillMaxWidth().height(142.dp).clip(RoundedCornerShape(4.dp)).background(color = colors.surfaceHigh), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = colors.muted, modifier = Modifier.size(54.dp))
        }
        Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 10.dp))
    }
}

@Composable
private fun StatSongCard(song: Song) {
    val colors = foxyPalette()
    Column(modifier = Modifier.fillMaxWidth().size(width = 180.dp, height = 170.dp)) {
        Box(modifier = Modifier.fillMaxWidth().height(92.dp).clip(RoundedCornerShape(4.dp)).background(color = colors.surfaceHigh), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = Color.White)
        }
        Text(song.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text("1 time - 43:46", color = colors.muted, fontSize = 13.sp)
    }
}
