package com.foxymusic

import androidx.compose.runtime.getValue
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Equalizer
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Login
import androidx.compose.material.icons.rounded.Mood
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import coil.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class DiscoveryCard(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val colors: List<Color>
)

private val discoveryCards = listOf(
    DiscoveryCard("Charts", "What is moving right now", Icons.Rounded.TrendingUp, listOf(Color(0xFFEA6A5A), Color(0xFF211114))),
    DiscoveryCard("Mood Radio", "Stations for your current energy", Icons.Rounded.Mood, listOf(Color(0xFF4AA88F), Color(0xFF10201C))),
    DiscoveryCard("New Releases", "Fresh albums and singles", Icons.Rounded.Album, listOf(Color(0xFF7E8DF5), Color(0xFF14182E))),
    DiscoveryCard("Hidden Gems", "Songs outside the obvious loop", Icons.Rounded.AutoAwesome, listOf(Color(0xFFE0A64B), Color(0xFF251907)))
)

@Composable
fun DiscoverScreen(navController: NavController) {
    val colors = foxyPalette()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sections by remember { mutableStateOf<List<RecommendationSection>>(emptyList()) }

    fun loadDiscovery(seed: String) {
        scope.launch {
            sections = withContext(Dispatchers.IO) {
                listOf(
                    "Songs for $seed" to "$seed songs",
                    "$seed playlists" to "$seed playlist",
                    "$seed radio" to "$seed radio"
                ).mapNotNull { (title, query) ->
                    val songs = runCatching { YTMusicApi.search(query).take(10) }.getOrDefault(emptyList())
                    songs.takeIf { it.isNotEmpty() }?.let { RecommendationSection(title, it) }
                }
            }
        }
    }

    fun play(song: Song, songs: List<Song>) {
        scope.launch(Dispatchers.IO) {
            MusicPlayer.playQueue(context, songs, songs.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0))
        }
    }

    LaunchedEffect(Unit) { loadDiscovery("trending music") }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(Color(0xFF071312), colors.background), endY = 720f)
            )
            .padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp)
    ) {
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text("Find the next thing", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Black)
            Text("Genres, moods, charts, releases, and radio stations.", color = colors.muted, fontSize = 14.sp)
        }

        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                items(discoveryCards) { card ->
                    DiscoverCard(card, onClick = { loadDiscovery(card.title) })
                }
            }
        }

        items(sections, key = { it.title }) { section ->
            SectionLabel(section.title)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(section.songs, key = { it.videoId }) { song ->
                    Column(
                        modifier = Modifier
                            .size(width = 138.dp, height = 200.dp)
                            .clickable { play(song, section.songs) }
                    ) {
                        TrackArtwork(song = song, modifier = Modifier.fillMaxWidth().aspectRatio(1f), cornerRadius = 18.dp)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(song.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }

        item {
            SectionLabel("Browse by mood")
            MoodGrid()
        }

        item {
            SectionLabel("Editorial shortcuts")
            FoxyListTile(Icons.Rounded.Radio, "Start a smart radio", "Builds a station from your current taste", onClick = { navController.navigate("search") })
            Spacer(modifier = Modifier.height(10.dp))
            FoxyListTile(Icons.Rounded.Equalizer, "Audio-first discovery", "High-energy, focus, chill and late-night clusters")
            Spacer(modifier = Modifier.height(10.dp))
            FoxyListTile(Icons.Rounded.QueueMusic, "Queue builder", "Search songs and turn them into a listening session")
        }
    }
}

@Composable
private fun DiscoverCard(card: DiscoveryCard, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(width = 214.dp, height = 180.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(Brush.linearGradient(card.colors))
            .clickable { onClick() }
            .padding(18.dp)
    ) {
        Icon(card.icon, contentDescription = null, tint = Color.White.copy(alpha = 0.94f), modifier = Modifier.size(34.dp))
        Column(modifier = Modifier.align(Alignment.BottomStart)) {
            Text(card.title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
            Text(card.subtitle, color = Color.White.copy(alpha = 0.76f), fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun MoodGrid() {
    val moods = listOf("Chill", "Romance", "Workout", "Focus", "Party", "Sleep")
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        moods.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEachIndexed { index, mood ->
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .aspectRatio(2.2f)
                            .clip(RoundedCornerShape(20.dp))
                            .background(if (index == 0) Color(0xFF251D2B) else Color(0xFF182521))
                            .padding(16.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        Text(mood, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
fun ProfileScreen(navController: NavController) {
    val account by FoxyAccount.state.collectAsStateWithLifecycle()
    val library by FoxyLibraryStore.state
    val colors = foxyPalette()
    LaunchedEffect(account.cookie) {
        if (account.isSignedIn) {
            withContext(Dispatchers.IO) {
                runCatching { YTMusicApi.accountInfo() }.getOrNull()
            }?.let { FoxyAccount.updateProfile(it.name, it.email, it.avatarUrl) }
        }
    }
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(color = colors.background)
            .padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(76.dp)
                        .clip(CircleShape)
                        .background(colors.accent),
                    contentAlignment = Alignment.Center
                ) {
                    if (account.avatarUrl.isNotBlank()) {
                        AsyncImage(
                            model = account.avatarUrl,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    } else {
                        Text(account.displayName.initialsForProfile(), color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
                    }
                }
                Column(modifier = Modifier.padding(start = 16.dp).weight(1f)) {
                    Text(account.displayName, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(if (account.isSignedIn) "YouTube Music connected" else "Guest mode", color = colors.muted, fontSize = 13.sp)
                }
            }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                ProfileStat(library.likedSongs.size.toString(), "Liked", Modifier.weight(1f))
                ProfileStat(library.savedSongs.size.toString(), "Saved", Modifier.weight(1f))
                ProfileStat(library.historySongs.size.toString(), "Played", Modifier.weight(1f))
            }
        }

        item {
            FoxyListTile(
                if (account.isSignedIn) Icons.Rounded.Favorite else Icons.Rounded.Login,
                if (account.isSignedIn) "Account recommendations active" else "Connect YouTube Music",
                if (account.isSignedIn) account.email.ifBlank { "Session stored locally" } else "Unlock personalized home, library sync foundation, and better browse results",
                onClick = { if (!account.isSignedIn) navController.navigate("login") }
            )
        }
        item { FoxyListTile(Icons.Rounded.Download, "Downloads", "Offline music and cache controls", onClick = { navController.navigate("downloads") }) }
        item { FoxyListTile(Icons.Rounded.Settings, "Settings", "Appearance, player, privacy and experiments", onClick = { navController.navigate("settings") }) }
    }
}

@Composable
private fun ProfileStat(value: String, label: String, modifier: Modifier) {
    val colors = foxyPalette()
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(18.dp))
            .background(color = colors.surface)
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black)
        Text(label, color = colors.muted, fontSize = 12.sp)
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
}

private fun String.initialsForProfile(): String {
    val pieces = trim().split(" ").filter { it.isNotBlank() }
    return pieces.take(2).joinToString("") { it.first().uppercaseChar().toString() }.ifBlank { "FM" }
}
