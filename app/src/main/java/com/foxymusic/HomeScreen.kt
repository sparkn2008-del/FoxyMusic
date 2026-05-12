package com.foxymusic

import androidx.compose.foundation.background
import coil.compose.AsyncImage
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.rememberAsyncImagePainter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar

private val fallbackQueries = listOf(
    "trending songs india",
    "new hindi songs",
    "lofi chill music",
    "global pop hits",
    "punjabi hits"
)

private val moodChips = listOf("Energize", "Focus", "Romance", "Late night", "Workout", "Hindi", "Punjabi")

@Composable
fun HomeScreen(onPlayAll: () -> Unit = {}) {
    val playerState by MusicPlayer.state.collectAsState()
    val account by FoxyAccount.state.collectAsState()
    val colors = foxyPalette()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var sections by remember { mutableStateOf<List<RecommendationSection>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var menuSong by remember { mutableStateOf<Song?>(null) }

    fun playSong(song: Song, queueSongs: List<Song> = sections.flatMap { it.songs }) {
        scope.launch {
            withContext(Dispatchers.IO) {
                MusicPlayer.playQueue(
                    context,
                    queueSongs.ifEmpty { listOf(song) },
                    queueSongs.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0)
                )
            }
        }
    }

    fun refresh() {
        loading = true
        error = null
        scope.launch {
            val loaded = withContext(Dispatchers.IO) {
                runCatching {
                    val home = YTMusicApi.homeRecommendations()
                    home.ifEmpty {
                        fallbackQueries.mapNotNull { query ->
                            val songs = YTMusicApi.search(query).take(10)
                            songs.takeIf { it.isNotEmpty() }?.let { RecommendationSection(query.toRailTitle(), it) }
                        }
                    }
                }
            }
            sections = loaded.getOrElse {
                error = it.message ?: "Could not load recommendations"
                emptyList()
            }
            loading = false
        }
    }

    LaunchedEffect(account.cookie) {
        refresh()
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF080A0C), colors.background, Color(0xFF050505))
                )
            )
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        item {
            Spacer(modifier = Modifier.height(8.dp))
            HomeHero(
                song = sections.firstOrNull()?.songs?.firstOrNull(),
                account = account,
                loading = loading,
                onPlay = { sections.firstOrNull()?.songs?.firstOrNull()?.let { playSong(it) } },
                onRefresh = ::refresh
            )
        }

        item { MoodStrip() }

        item {
            val quickSongs = sections.firstOrNull()?.songs.orEmpty()
            HomeSectionHeader("Quick Picks", "Play all", onPlayAll)
            Spacer(modifier = Modifier.height(8.dp))

            if (quickSongs.isEmpty() && loading) {
                LoadingPanel()
            } else if (quickSongs.isEmpty()) {
                EmptyPanel(error = error, onRefresh = ::refresh)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    quickSongs.take(6).forEach { song ->
                        FoxySongRow(
                            song = song,
                            isCurrent = playerState.currentSong?.videoId == song.videoId,
                            isPlaying = playerState.isPlaying && playerState.currentSong?.videoId == song.videoId,
                            onClick = { playSong(song, quickSongs) },
                            onMore = { menuSong = song }
                        )
                    }
                }
            }
        }

        items(sections.drop(1), key = { it.title }) { section ->
            RecommendationRail(section, onSongClick = { playSong(it, section.songs) })
        }

        item {
            InsightGrid()
            Spacer(modifier = Modifier.height(16.dp))
        }
    }

    menuSong?.let { SongActionMenu(song = it, onDismiss = { menuSong = null }) }
}

// ==================== HERO ====================
@Composable
private fun HomeHero(
    song: Song?,
    account: FoxyAccountState,
    loading: Boolean,
    onPlay: () -> Unit,
    onRefresh: () -> Unit
) {
    val colors = foxyPalette()

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(Color.DarkGray)
            .clickable(enabled = song != null) { onPlay() }
    ) {
        song?.let {
            AsyncImage(
                model = it.bestPosterUrl(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
        )

        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.AutoAwesome, null, tint = colors.accent, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    if (account.isSignedIn) "Hi, ${account.displayName}" else "Good evening",
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            IconButton(onClick = onRefresh) {
                if (loading) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                } else {
                    Icon(Icons.Rounded.Refresh, "Refresh", tint = Color.White)
                }
            }
        }

        // Bottom content
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(18.dp)
        ) {
            Text("FoxyMusic", color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.ExtraBold)
            Text(
                song?.title ?: greetingTitle(),
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Black,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                song?.artist ?: "Discover new music",
                color = Color.White.copy(alpha = 0.85f),
                fontSize = 14.sp,
                maxLines = 1
            )
        }
    }
}

// ==================== MOOD STRIP ====================
@Composable
private fun MoodStrip() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        moodChips.forEach { mood ->
            MetroChip(label = mood, selected = mood == "Energize")
        }
    }
}

// ==================== SECTION HEADER ====================
@Composable
private fun HomeSectionHeader(title: String, action: String? = null, onAction: () -> Unit = {}) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            color = Color.White,
            fontSize = 21.sp,
            fontWeight = FontWeight.Black
        )
        Spacer(Modifier.weight(1f))
        if (action != null) {
            Text(
                text = action,
                color = FoxyAccent,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .clickable { onAction() }
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            )
        }
    }
}

// ==================== SONG ROW ====================
@Composable
fun FoxySongRow(
    song: Song,
    isCurrent: Boolean = false,
    isPlaying: Boolean = false,
    onClick: () -> Unit,
    onMore: () -> Unit = onClick
) {
    val colors = foxyPalette()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(if (isCurrent) colors.accent.copy(alpha = 0.1f) else Color.Transparent)
            .clickable { onClick() }
            .padding(vertical = 8.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TrackArtwork(song = song, modifier = Modifier.size(56.dp), cornerRadius = 12)

        Spacer(modifier = Modifier.width(14.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                song.title,
                color = Color.White,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                song.artist,
                color = colors.muted,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (isPlaying) {
            Icon(Icons.Rounded.GraphicEq, null, tint = FoxyMint, modifier = Modifier.size(26.dp))
        } else {
            IconButton(onClick = onMore) {
                Icon(Icons.Rounded.MoreVert, null, tint = colors.muted)
            }
        }
    }
}

// ==================== RECOMMENDATION RAIL (Main Fix) ====================
@Composable
private fun RecommendationRail(section: RecommendationSection, onSongClick: (Song) -> Unit) {
    Column {
        HomeSectionHeader(section.title)
        Spacer(modifier = Modifier.height(10.dp))

        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(section.songs, key = { it.videoId }) { song ->
                RecommendationCard(song, onClick = { onSongClick(song) })
            }
        }
    }
}

@Composable
private fun RecommendationCard(song: Song, onClick: () -> Unit) {
    val colors = foxyPalette()

    Column(
        modifier = Modifier
            .width(142.dp)
            .clip(RoundedCornerShape(16.dp))
            .clickable { onClick() }
    ) {
        Box {
            TrackArtwork(
                song = song,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .shadow(8.dp, RoundedCornerShape(16.dp)),
                cornerRadius = 16
            )

            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.65f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Text(
            song.title,
            color = Color.White,
            fontSize = 13.5.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            lineHeight = 18.sp
        )

        Text(
            song.artist,
            color = colors.muted,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// ==================== OTHER COMPONENTS ====================
@Composable
private fun InsightGrid() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HomeSectionHeader("Listening Insights")
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            InsightTile(Icons.Rounded.Timeline, "Weekly vibe", "High energy", Modifier.weight(1f))
            InsightTile(Icons.Rounded.Favorite, "Taste match", "87%", Modifier.weight(1f))
        }
    }
}

@Composable
private fun InsightTile(icon: ImageVector, title: String, value: String, modifier: Modifier) {
    val colors = foxyPalette()
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(colors.surface)
            .padding(16.dp)
    ) {
        Icon(icon, null, tint = colors.accent, modifier = Modifier.size(26.dp))
        Spacer(modifier = Modifier.height(16.dp))
        Text(value, color = Color.White, fontSize = 23.sp, fontWeight = FontWeight.Black)
        Text(title, color = colors.muted, fontSize = 12.5.sp)
    }
}

@Composable
private fun LoadingPanel() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(110.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(FoxySurfaceSoft),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(color = FoxyAccent)
    }
}

@Composable
private fun EmptyPanel(error: String?, onRefresh: () -> Unit) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(colors.surface)
            .clickable { onRefresh() }
            .padding(20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Rounded.CloudOff, null, tint = colors.accent, modifier = Modifier.size(36.dp))
        Spacer(modifier = Modifier.width(14.dp))
        Column {
            Text("Couldn't load recommendations", color = Color.White, fontWeight = FontWeight.Bold)
            Text(error ?: "Tap to retry", color = colors.muted, fontSize = 13.sp)
        }
    }
}

private fun String.toRailTitle(): String =
    split(" ").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }

private fun greetingTitle(): String {
    val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    return when (hour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Late night vibes"
    }
}