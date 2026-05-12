package com.foxymusic

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Podcasts
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class HomeFeed(
    val homeSections: List<RecommendationSection> = emptyList(),
    val songs: List<Song> = emptyList(),
    val videos: List<Song> = emptyList(),
    val podcasts: List<Song> = emptyList(),
    val playlists: List<Song> = emptyList(),
    val discovery: List<RecommendationSection> = emptyList()
)

@OptIn(ExperimentalMaterialApi::class, ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(onPlayAll: () -> Unit = {}) {
    val playerState by MusicPlayer.state.collectAsState()
    val account by FoxyAccount.state.collectAsState()
    val colors = foxyPalette()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var feed by remember { mutableStateOf(HomeFeed()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    var menuSong by remember { mutableStateOf<Song?>(null) }

    fun playSong(song: Song, queue: List<Song>) {
        scope.launch(Dispatchers.IO) {
            MusicPlayer.playQueue(context, queue.ifEmpty { listOf(song) }, queue.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0))
        }
    }

    fun loadHome() {
        loading = true
        error = null
        scope.launch {
            val loaded = runCatching {
                withContext(Dispatchers.IO) {
                    val home = async { YTMusicApi.homeRecommendations() }
                    val songs = async { YTMusicApi.search("new music songs").take(20) }
                    val videos = async { YTMusicApi.videos("trending music videos").take(16) }
                    val podcasts = async { YTMusicApi.search("music podcasts", null).take(12) }
                    val playlists = async { YTMusicApi.search("workout focus chill playlists", null).take(12) }
                    val discovery = listOf(
                        RecommendationSection("Charts and trending", YTMusicApi.search("top songs today").take(10)),
                        RecommendationSection("New releases", YTMusicApi.search("new release music").take(10)),
                        RecommendationSection("Late night radio", YTMusicApi.getMoodMix("Late Night").take(10))
                    ).filter { it.songs.isNotEmpty() }
                    HomeFeed(
                        homeSections = home.await(),
                        songs = songs.await(),
                        videos = videos.await(),
                        podcasts = podcasts.await(),
                        playlists = playlists.await(),
                        discovery = discovery
                    )
                }
            }
            feed = loaded.getOrElse {
                error = it.message ?: "Home could not refresh"
                HomeFeed(homeSections = YTMusicApi.homeRecommendations())
            }
            loading = false
            refreshing = false
        }
    }

    val quickSongs = feed.homeSections.firstOrNull()?.songs.orEmpty().ifEmpty { feed.songs }
    val pullRefreshState = rememberPullRefreshState(refreshing, onRefresh = {
        refreshing = true
        loadHome()
    })

    LaunchedEffect(account.cookie) { loadHome() }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color.Black, Color(0xFF090C0B), colors.background)))
                .pullRefresh(pullRefreshState),
            verticalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            item {
                Column(Modifier.padding(horizontal = 18.dp, vertical = 8.dp)) {
                    Text(dynamicHomeGreeting(), color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.Black)
                    Text("FoxyMusic", color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Black)
                    Text("Songs, videos, podcasts, playlists, and discovery in one place.", color = colors.muted, fontSize = 13.sp)
                }
            }

            item { MoodStrip { mood -> scope.launch { YTMusicApi.getMoodMix(mood).also { if (it.isNotEmpty()) MusicPlayer.playQueue(context, it, 0) } } } }

            item {
                HomeSpotlight(
                    song = quickSongs.firstOrNull(),
                    loading = loading,
                    error = error,
                    onPlay = { quickSongs.firstOrNull()?.let { playSong(it, quickSongs) } },
                    onRadio = { quickSongs.firstOrNull()?.let { MusicPlayer.startRadio(context, it) } }
                )
            }

            item {
                SectionHeader("Quick picks", "Search", onPlayAll)
                LazyHorizontalGrid(
                    rows = GridCells.Fixed(4),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.fillMaxWidth().height(300.dp)
                ) {
                    items(quickSongs.take(16), key = { it.videoId }) { song ->
                        val isCurrent = playerState.currentSong?.videoId == song.videoId
                        CompactHomeSong(
                            song = song,
                            isCurrent = isCurrent,
                            isPlaying = isCurrent && playerState.isPlaying,
                            onClick = { playSong(song, quickSongs) },
                            onMore = { menuSong = song }
                        )
                    }
                }
            }

            item {
                DiscoveryGrid(
                    onCharts = { scope.launch { YTMusicApi.search("top songs today").also { MusicPlayer.playQueue(context, it, 0) } } },
                    onMood = { scope.launch { YTMusicApi.getMoodMix("Focus").also { MusicPlayer.playQueue(context, it, 0) } } },
                    onNew = { scope.launch { YTMusicApi.search("new release music").also { MusicPlayer.playQueue(context, it, 0) } } },
                    onPlaylists = { scope.launch { YTMusicApi.search("best music playlists", null).also { MusicPlayer.playQueue(context, it, 0) } } }
                )
            }

            item { TypeRail("Songs", Icons.Rounded.QueueMusic, feed.songs, onSong = { playSong(it, feed.songs) }, onMore = { menuSong = it }) }
            item { TypeRail("Videos", Icons.Rounded.Movie, feed.videos, onSong = { playSong(it, feed.videos) }, onMore = { menuSong = it }) }
            item { TypeRail("Podcasts", Icons.Rounded.Podcasts, feed.podcasts, onSong = { playSong(it, feed.podcasts) }, onMore = { menuSong = it }) }
            item { TypeRail("Playlists", Icons.Rounded.Album, feed.playlists, onSong = { playSong(it, feed.playlists) }, onMore = { menuSong = it }) }

            items(feed.discovery + feed.homeSections.drop(1), key = { it.title }) { section ->
                RecommendationRail(section = section, onSongClick = { playSong(it, section.songs) }, onSongMore = { menuSong = it })
            }

            item { Spacer(Modifier.height(96.dp)) }
        }

        PullRefreshIndicator(
            refreshing = refreshing,
            state = pullRefreshState,
            modifier = Modifier.align(Alignment.TopCenter),
            backgroundColor = colors.surface,
            contentColor = colors.accent
        )
    }

    menuSong?.let { SongActionMenu(song = it, onDismiss = { menuSong = null }) }
}

@Composable
private fun MoodStrip(onMood: (String) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        listOf("Energize", "Focus", "Chill", "Workout", "Romance", "Late Night", "Hindi", "Punjabi").forEachIndexed { index, mood ->
            MetroChip(label = mood, selected = index == 0, onClick = { onMood(mood) })
        }
    }
}

@Composable
private fun HomeSpotlight(song: Song?, loading: Boolean, error: String?, onPlay: () -> Unit, onRadio: () -> Unit) {
    val colors = foxyPalette()
    Box(
        modifier = Modifier.padding(horizontal = 18.dp).fillMaxWidth().height(178.dp).clip(RoundedCornerShape(10.dp))
    ) {
        TrackArtwork(song, Modifier.fillMaxSize(), 10)
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.88f), colors.accent.copy(alpha = 0.36f), Color.Transparent))))
        Row(Modifier.fillMaxSize().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Start listening", color = colors.accent, fontSize = 12.sp, fontWeight = FontWeight.Black)
                Text(song?.title ?: if (loading) "Loading your feed" else "A station is ready", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(error ?: song?.artist ?: "Refresh or search to tune the feed", color = colors.muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    RoundAction(Icons.Rounded.PlayArrow, "Play", onPlay)
                    RoundAction(Icons.Rounded.Radio, "Radio", onRadio)
                }
            }
            TrackArtwork(song, Modifier.size(118.dp), 8)
        }
    }
}

@Composable
private fun DiscoveryGrid(onCharts: () -> Unit, onMood: () -> Unit, onNew: () -> Unit, onPlaylists: () -> Unit) {
    val cards = listOf(
        Triple("Charts", Icons.Rounded.AutoAwesome, onCharts),
        Triple("Mood radio", Icons.Rounded.Radio, onMood),
        Triple("New releases", Icons.Rounded.Album, onNew),
        Triple("Playlists", Icons.Rounded.QueueMusic, onPlaylists)
    )
    Column(Modifier.padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("Explore")
        cards.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEachIndexed { index, item ->
                    ExploreTile(item.first, item.second, if (index == 0) Color(0xFF251412) else Color(0xFF14231E), item.third, Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ExploreTile(title: String, icon: ImageVector, color: Color, onClick: () -> Unit, modifier: Modifier) {
    val colors = foxyPalette()
    Row(
        modifier = modifier.height(86.dp).clip(RoundedCornerShape(8.dp)).background(color).clickable { onClick() }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(42.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.24f)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = colors.accent)
        }
        Text(title, color = Color.White, fontWeight = FontWeight.Black, fontSize = 16.sp, modifier = Modifier.padding(start = 12.dp))
    }
}

@Composable
private fun TypeRail(title: String, icon: ImageVector, songs: List<Song>, onSong: (Song) -> Unit, onMore: (Song) -> Unit) {
    if (songs.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = foxyPalette().accent, modifier = Modifier.size(22.dp))
            Text(title, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(start = 8.dp))
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Spacer(Modifier.width(6.dp)) }
            items(songs, key = { it.videoId }) { song ->
                PosterCard(song, onClick = { onSong(song) }, onMore = { onMore(song) })
            }
            item { Spacer(Modifier.width(6.dp)) }
        }
    }
}

@Composable
private fun PosterCard(song: Song, onClick: () -> Unit, onMore: () -> Unit) {
    val colors = foxyPalette()
    Box(Modifier.width(148.dp).clickable { onClick() }) {
        Column {
            TrackArtwork(song, Modifier.fillMaxWidth().aspectRatio(1f), 8)
            Text(song.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            Text(song.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconButton(onClick = onMore, modifier = Modifier.align(Alignment.TopEnd).size(34.dp).background(Color.Black.copy(alpha = 0.48f), CircleShape)) {
            Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun CompactHomeSong(song: Song, isCurrent: Boolean, isPlaying: Boolean, onClick: () -> Unit, onMore: () -> Unit) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier.width(320.dp).clip(RoundedCornerShape(6.dp)).background(if (isCurrent) colors.accent.copy(alpha = 0.16f) else Color.Transparent).clickable { onClick() }.padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TrackArtwork(song, Modifier.size(54.dp), 4)
        Column(Modifier.padding(start = 12.dp).weight(1f)) {
            Text(song.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(song.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (isPlaying) Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = colors.accent, modifier = Modifier.size(20.dp))
        IconButton(onClick = onMore, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = colors.muted)
        }
    }
}

@Composable
private fun SectionHeader(title: String, action: String? = null, onAction: () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
        action?.let {
            Text(it, color = foxyPalette().accent, fontSize = 13.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { onAction() }.padding(8.dp))
        }
    }
}

@Composable
private fun RoundAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(42.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.15f))) {
        Icon(icon, contentDescription = label, tint = Color.White)
    }
}

private fun dynamicHomeGreeting(): String {
    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
    return when (hour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Late night listening"
    }
}
