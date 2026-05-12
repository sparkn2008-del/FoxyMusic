package com.foxymusic

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AudioFile
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
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
    MetroBackScaffold("History", navController) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(listOf("Local", "Remote")) { MetroChip(it, selected = it == "Local") }
            }
        }
        item { MetroSectionTitle("Today") }
        items(historySongs) { song ->
            MetroSongRow(song, trailing = {
                Icon(Icons.Rounded.DensityMedium, contentDescription = "More", tint = MetroMuted)
            })
        }
    }
}

@Composable
fun StatsScreen(navController: NavController) {
    MetroBackScaffold("Stats", navController) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(listOf("Continuous", "1 week", "1 month", "3 months")) { MetroChip(it, selected = it == "1 week") }
            }
        }
        item { MetroSectionTitle("2 playlists") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), modifier = Modifier.fillMaxWidth()) {
                StatTile("Weekly Most", Icons.Rounded.History, Modifier.weight(1f))
                StatTile("Monthly Most", Icons.Rounded.TrendingUp, Modifier.weight(1f))
            }
        }
        item { MetroSectionTitle("114 Songs", action = "Play all") }
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                items(historySongs.take(4)) { song -> StatSongCard(song) }
            }
        }
        item { MetroSectionTitle("147 Artists") }
        items(historySongs.take(3)) { song -> MetroSongRow(song) }
    }
}

@Composable
fun SettingsHubScreen(navController: NavController) {
    MetroBackScaffold("Settings", navController) {
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

    MetroBackScaffold("Player and audio", navController) {
        item { MetroLabel("Player") }
        item { MetroIconTile(Icons.Rounded.AudioFile, "Audio quality", "High") }
        item { MetroToggleRow(Icons.Rounded.Sync, "Crossfade", "Fades out the current song as the next one fades in", crossfade) { crossfade = it } }
        item {
            MetroSliderRow(Icons.Rounded.Timer, "Crossfade duration", "${crossfadeDuration.toInt()} seconds", crossfadeDuration, 0f..12f) {
                crossfadeDuration = it
            }
        }
        item { MetroToggleRow(Icons.Rounded.SkipNext, "Skip silence", "Fast-forward through silent parts of songs", skipSilence) { skipSilence = it } }
        item { MetroToggleRow(Icons.Rounded.VolumeUp, "Audio normalization", null, normalize) { normalize = it } }
        item { MetroLabel("Sleep timer") }
        item { MetroIconTile(Icons.Rounded.Add, "Add alarm", "No alarms yet. Add one to start scheduled playback") }
        item { MetroToggleRow(Icons.Rounded.BatterySaver, "Battery optimization", "Disable optimization for reliable alarm behavior", false) {} }
        item { MetroLabel("Queue") }
        item { MetroToggleRow(Icons.Rounded.QueueMusic, "Persistent queue", "Restore your last queue when the app starts", persistentQueue) { persistentQueue = it } }
        item { MetroToggleRow(Icons.Rounded.PlayArrow, "Autoplay", "Automatically play the next song when the current one ends", autoplay) { autoplay = it } }
        item { MetroToggleRow(Icons.Rounded.Download, "Auto-download on like", "Automatically download songs when you like them", cacheOnLike) { cacheOnLike = it } }
    }
}

@Composable
fun AppearanceScreen(navController: NavController) {
    var dynamicIcon by remember { mutableStateOf(true) }
    var refreshRate by remember { mutableStateOf(true) }
    var newMini by remember { mutableStateOf(true) }
    var newPlayer by remember { mutableStateOf(true) }
    var swipeChange by remember { mutableStateOf(true) }
    var glowingLyrics by remember { mutableStateOf(true) }

    MetroBackScaffold("Appearance", navController) {
        item { MetroLabel("Theme") }
        item { MetroToggleRow(Icons.Rounded.Brush, "Enable dynamic icon", null, dynamicIcon) { dynamicIcon = it } }
        item { MetroToggleRow(Icons.Rounded.Speed, "Enable high refresh rate", "Forces the display to run at its highest supported refresh rate", refreshRate) { refreshRate = it } }
        item { MetroIconTile(Icons.Rounded.Palette, "Theme", "Customize your app theme") }
        item { MetroLabel("Mini-player") }
        item { MetroToggleRow(Icons.Rounded.LibraryMusic, "New mini-player design", null, newMini) { newMini = it } }
        item { MetroIconTile(Icons.Rounded.GridView, "Mini-player background style", "Follow theme") }
        item { MetroLabel("Player") }
        item { MetroToggleRow(Icons.Rounded.Palette, "New player design", null, newPlayer) { newPlayer = it } }
        item { MetroIconTile(Icons.Rounded.Brush, "Player background style", "Blur") }
        item { MetroIconTile(Icons.Rounded.Settings, "Player button colors", "Default") }
        item { MetroIconTile(Icons.Rounded.DensityMedium, "Player slider style", "Squiggly") }
        item { MetroToggleRow(Icons.Rounded.Sync, "Enable swipe to change song", null, swipeChange) { swipeChange = it } }
        item { MetroLabel("Lyrics") }
        item { MetroToggleRow(Icons.Rounded.Lyrics, "Enable glowing lyrics effect", "Adds glow and bounce to the active lyric line", glowingLyrics) { glowingLyrics = it } }
        item { MetroIconTile(Icons.Rounded.Lyrics, "Lyrics text size", "24 sp") }
        item { MetroIconTile(Icons.Rounded.Lyrics, "Default open tab", "Library") }
    }
}

@Composable
fun StorageScreen(navController: NavController) {
    var songCache by remember { mutableStateOf(true) }
    var songCacheSize by remember { mutableFloatStateOf(1f) }
    var imageCacheSize by remember { mutableFloatStateOf(0.5f) }

    MetroBackScaffold("Storage", navController) {
        item { MetroLabel("Storage") }
        item { MetroIconTile(Icons.Rounded.Download, "Downloaded songs", "572 MB") }
        item { MetroIconTile(Icons.Rounded.DensityMedium, "Clear all downloads") }
        item { MetroLabel("Song Cache") }
        item { MetroToggleRow(Icons.Rounded.Cached, "Enable song cache", "Automatically cache songs for faster future playback", songCache) { songCache = it } }
        item { MetroSliderRow(Icons.Rounded.Cached, "Max song cache size", "${songCacheSize.toInt()} GB", songCacheSize, 0f..4f) { songCacheSize = it } }
        item { MetroIconTile(Icons.Rounded.DensityMedium, "Clear song cache") }
        item { MetroLabel("Image Cache") }
        item { MetroSliderRow(Icons.Rounded.Search, "Max image cache size", "${(imageCacheSize * 1024).toInt()} MB", imageCacheSize, 0f..1f) { imageCacheSize = it } }
        item { MetroIconTile(Icons.Rounded.DensityMedium, "Clear image cache") }
    }
}

@Composable
fun UpdaterScreen(navController: NavController) {
    var autoUpdates by remember { mutableStateOf(true) }
    var notifications by remember { mutableStateOf(true) }

    MetroBackScaffold("Updater", navController) {
        item { MetroLabel("Current version") }
        item { MetroIconTile(Icons.Rounded.Update, "Version: 1.0", "FoxyMusic debug") }
        item { MetroLabel("Update settings") }
        item { MetroToggleRow(Icons.Rounded.Sync, "Automatically check for updates", null, autoUpdates) { autoUpdates = it } }
        item { MetroToggleRow(Icons.Rounded.Alarm, "Enable update notifications", null, notifications) { notifications = it } }
        item { MetroIconTile(Icons.Rounded.Update, "Check for updates") }
    }
}

@Composable
fun AboutScreen(navController: NavController) {
    MetroBackScaffold("About", navController) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(MetroSurface).padding(28.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = MetroAccent, modifier = Modifier.size(58.dp))
                    Column(modifier = Modifier.padding(start = 20.dp)) {
                        Text("FoxyMusic", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold)
                        Text("1.0  UNIVERSAL", color = MetroAccent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(modifier = Modifier.height(22.dp))
                Text("A fast, premium music client built for search, recommendations, smooth playback, and a clean AMOLED interface.", color = MetroMuted, fontSize = 15.sp)
            }
        }
        item { MetroLabel("Community & Info") }
        item { MetroIconTile(Icons.Rounded.Security, "Privacy-first local controls") }
        item { MetroIconTile(Icons.Rounded.Info, "Open-source friendly architecture") }
        item { MetroIconTile(Icons.Rounded.Favorite, "Made for FoxyMusic") }
    }
}

@Composable
private fun MetroBackScaffold(
    title: String,
    navController: NavController,
    content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize().background(MetroBlack)
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
private fun MetroLabel(label: String) {
    Text(label, color = MetroAccent, fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 20.dp, bottom = 4.dp))
}

@Composable
private fun SettingsNavRow(icon: ImageVector, title: String, subtitle: String, route: String, navController: NavController) {
    MetroIconTile(icon = icon, title = title, subtitle = subtitle, onClick = { navController.navigate(route) })
}

@Composable
private fun MetroSliderRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MetroSurface).padding(14.dp)
    ) {
        MetroIconTile(icon, title, subtitle)
        Slider(value = value, onValueChange = onValueChange, valueRange = valueRange)
    }
}

@Composable
private fun StatTile(title: String, icon: ImageVector, modifier: Modifier) {
    Column(modifier = modifier) {
        Box(modifier = Modifier.fillMaxWidth().height(142.dp).clip(RoundedCornerShape(4.dp)).background(MetroSurfaceHigh), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = MetroMuted, modifier = Modifier.size(54.dp))
        }
        Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 10.dp))
    }
}

@Composable
private fun StatSongCard(song: Song) {
    Column(modifier = Modifier.fillMaxWidth().size(width = 180.dp, height = 170.dp)) {
        Box(modifier = Modifier.fillMaxWidth().height(92.dp).clip(RoundedCornerShape(4.dp)).background(MetroSurfaceHigh), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = Color.White)
        }
        Text(song.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text("1 time - 43:46", color = MetroMuted, fontSize = 13.sp)
    }
}
