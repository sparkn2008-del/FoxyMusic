package com.foxymusic

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
    val chartsSections: List<RecommendationSection> = emptyList(),
    val songs: List<Song> = emptyList(),
    val videos: List<Song> = emptyList(),
    val podcasts: List<Song> = emptyList(),
    val playlists: List<Song> = emptyList(),
    val discovery: List<RecommendationSection> = emptyList()
)

private object HomeScreenMemoryCache {
    var cookie: String? = null
    var feed: HomeFeed = HomeFeed()
    val moodTracks: MutableMap<String, List<Song>> = mutableMapOf()
}

private fun HomeFeed.hasContent(): Boolean =
    homeSections.isNotEmpty() ||
        chartsSections.isNotEmpty() ||
        songs.isNotEmpty() ||
        videos.isNotEmpty() ||
        podcasts.isNotEmpty() ||
        playlists.isNotEmpty() ||
        discovery.isNotEmpty()

@OptIn(ExperimentalMaterialApi::class, ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(
    onSongPlay: () -> Unit = {}
) {
    val playerState by MusicPlayer.state.collectAsState()
    val account by FoxyAccount.state.collectAsState()
    val colors = foxyColors()                    // Changed to foxyColors()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var feed by remember { mutableStateOf(HomeScreenMemoryCache.feed) }
    var loading by remember { mutableStateOf(!HomeScreenMemoryCache.feed.hasContent()) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    var menuSong by remember { mutableStateOf<Song?>(null) }

    fun playSong(song: Song, queue: List<Song>) {
        scope.launch {
            MusicPlayer.playQueue(
                context,
                queue.ifEmpty { listOf(song) },
                queue.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0)
            )
            onSongPlay()
        }
    }

    fun loadHome(force: Boolean = false) {
        val cached = HomeScreenMemoryCache.feed
        if (!force && HomeScreenMemoryCache.cookie == account.cookie && cached.hasContent()) {
            feed = cached
            loading = false
            refreshing = false
            return
        }
        loading = true
        error = null
        scope.launch {
            val loaded = runCatching {
                withContext(Dispatchers.IO) {
                    val home = async { YTMusicApi.homeRecommendations() }
                    val charts = async { YTMusicApi.chartsSections() }
                    val songs = async { YTMusicApi.search("new music songs").take(20) }
                    val videos = async { YTMusicApi.videos("trending music videos").take(16) }
                    val podcasts = async { YTMusicApi.search("music podcasts").take(12) }
                    val playlists = async { YTMusicApi.search("workout focus chill playlists").take(12) }

                    val discovery = listOf(
                        RecommendationSection("Charts and trending", YTMusicApi.search("top songs today").take(10)),
                        RecommendationSection("New releases", YTMusicApi.search("new release music").take(10)),
                        RecommendationSection("Late night radio", YTMusicApi.getMoodMix("Late Night").take(10))
                    ).filter { it.songs.isNotEmpty() }

                    HomeFeed(
                        homeSections = home.await(),
                        chartsSections = charts.await(),
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
            HomeScreenMemoryCache.cookie = account.cookie
            HomeScreenMemoryCache.feed = feed
            loading = false
            refreshing = false
        }
    }

    val quickSongs = feed.homeSections.firstOrNull()?.songs.orEmpty().ifEmpty { feed.songs }
    val homeMoods = listOf("Energize", "Focus", "Chill", "Workout", "Romance", "Late Night", "Hindi", "Punjabi")
    var selectedMood by remember { mutableStateOf(homeMoods.first()) }
    var moodTracks by remember { mutableStateOf<List<Song>>(emptyList()) }
    var moodLoading by remember { mutableStateOf(false) }

    LaunchedEffect(selectedMood, account.cookie) {
        moodLoading = true
        val cacheKey = "${account.cookie.orEmpty()}:$selectedMood"
        moodTracks = HomeScreenMemoryCache.moodTracks[cacheKey] ?: runCatching {
            withContext(Dispatchers.IO) { YTMusicApi.getMoodMix(selectedMood) }
        }.getOrDefault(emptyList()).also { HomeScreenMemoryCache.moodTracks[cacheKey] = it }
        moodLoading = false
    }

    val pullRefreshState = rememberPullRefreshState(refreshing, onRefresh = {
        refreshing = true
        loadHome(force = true)
    })

    LaunchedEffect(account.cookie) { loadHome() }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .foxyRootBackground()
                .pullRefresh(pullRefreshState),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                Column(Modifier.padding(horizontal = 20.dp).statusBarsPadding()) {
                    Text(
                        "${dynamicHomeGreeting()} · For you",
                        color = colors.muted,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        "Recommended",
                        color = Color.White,
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }

            item {
                SectionHeader("Quick picks", "Play all") {
                    if (quickSongs.isNotEmpty()) {
                        scope.launch {
                            MusicPlayer.playQueue(context, quickSongs, 0)
                            onSongPlay()
                        }
                    }
                }
                Column(
                    Modifier
                        .padding(horizontal = 12.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(foxyColors().surface.copy(alpha = 0.35f))
                ) {
                    quickSongs.take(18).forEach { song ->
                        val isCurrent = playerState.currentSong?.videoId == song.videoId
                        CompactHomeSong(
                            song = song,
                            isCurrent = isCurrent,
                            isPlaying = isCurrent && playerState.isPlaying,
                            onClick = { playSong(song, quickSongs) },
                            onMore = { menuSong = song },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }

            item {
                MoodStrip(
                    moods = homeMoods,
                    selected = selectedMood,
                    onSelect = { selectedMood = it }
                )
            }

            item {
                MoodMixShelf(
                    mood = selectedMood,
                    tracks = moodTracks,
                    loading = moodLoading,
                    playerState = playerState,
                    onPlayAll = {
                        if (moodTracks.isNotEmpty()) playSong(moodTracks.first(), moodTracks)
                    },
                    onPlaySong = { s -> playSong(s, moodTracks) }
                )
            }

            item {
                HomeSpotlight(
                    song = quickSongs.firstOrNull(),
                    loading = loading,
                    error = error,
                    onPlay = { quickSongs.firstOrNull()?.let { playSong(it, quickSongs) } },
                    onRadio = {
                        quickSongs.firstOrNull()?.let {
                            scope.launch {
                                MusicPlayer.startRadio(context, it)
                                onSongPlay()
                            }
                        }
                    }
                )
            }

            item {
                DiscoveryGrid(
                    onCharts = { scope.launch { YTMusicApi.search("top songs today").also { MusicPlayer.playQueue(context, it, 0); onSongPlay() } } },
                    onMood = { scope.launch { YTMusicApi.getMoodMix("Focus").also { MusicPlayer.playQueue(context, it, 0); onSongPlay() } } },
                    onNew = { scope.launch { YTMusicApi.search("new release music").also { MusicPlayer.playQueue(context, it, 0); onSongPlay() } } },
                    onPlaylists = { scope.launch { YTMusicApi.search("best music playlists").also { MusicPlayer.playQueue(context, it, 0); onSongPlay() } } }
                )
            }

            item { TypeRail("Songs", Icons.Rounded.QueueMusic, feed.songs, onSong = { playSong(it, feed.songs) }, onMore = { menuSong = it }) }
            item { TypeRail("Videos", Icons.Rounded.Movie, feed.videos, onSong = { playSong(it, feed.videos) }, onMore = { menuSong = it }) }
            item { TypeRail("Podcasts", Icons.Rounded.Podcasts, feed.podcasts, onSong = { playSong(it, feed.podcasts) }, onMore = { menuSong = it }) }
            item { TypeRail("Playlists", Icons.Rounded.Album, feed.playlists, onSong = { playSong(it, feed.playlists) }, onMore = { menuSong = it }) }

            items(feed.chartsSections, key = { "charts:${it.title}" }) { section ->
                RecommendationRail(section = section, onSongClick = { playSong(it, section.songs) }, onSongMore = { menuSong = it })
            }

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
private fun MoodStrip(
    moods: List<String>,
    selected: String,
    onSelect: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        moods.forEach { mood ->
            FoxyPillChip(label = mood, selected = mood == selected, onClick = { onSelect(mood) })
        }
    }
}

@Composable
private fun MoodMixShelf(
    mood: String,
    tracks: List<Song>,
    loading: Boolean,
    playerState: PlayerUiState,
    onPlayAll: () -> Unit,
    onPlaySong: (Song) -> Unit
) {
    val colors = foxyColors()
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(colors.surface.copy(alpha = 0.42f))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Your mix", color = colors.accent, fontSize = 12.sp, fontWeight = FontWeight.Black)
                Text(
                    "$mood station",
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    when {
                        loading -> "Loading picks…"
                        tracks.isEmpty() -> "No tracks for this mood yet — try another chip or refresh."
                        else -> "${tracks.size} songs · tap a row to play"
                    },
                    color = colors.muted,
                    fontSize = 12.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            TextButton(
                onClick = onPlayAll,
                enabled = tracks.isNotEmpty() && !loading
            ) {
                Text("Play", color = colors.accent, fontWeight = FontWeight.Bold)
            }
        }
        if (loading) {
            LinearProgressIndicator(
                modifier = Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)),
                color = colors.accent,
                trackColor = Color.White.copy(alpha = 0.08f)
            )
        }
        if (!loading && tracks.isNotEmpty()) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(tracks.take(24), key = { it.videoId }) { song ->
                    val current = playerState.currentSong?.videoId == song.videoId
                    Column(
                        Modifier
                            .width(132.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (current) colors.accent.copy(alpha = 0.14f) else Color.Transparent)
                            .clickable { onPlaySong(song) }
                            .padding(8.dp)
                    ) {
                        TrackArtwork(song = song, modifier = Modifier.fillMaxWidth().aspectRatio(1f), cornerRadius = 10.dp)
                        Text(
                            song.title,
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                        Text(
                            song.artist,
                            color = colors.muted,
                            fontSize = 11.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeSpotlight(
    song: Song?,
    loading: Boolean,
    error: String?,
    onPlay: () -> Unit,
    onRadio: () -> Unit
) {
    val colors = foxyColors()
    Box(
        modifier = Modifier
            .padding(horizontal = 18.dp)
            .fillMaxWidth()
            .height(178.dp)
            .clip(RoundedCornerShape(10.dp))
    ) {
        TrackArtwork(song = song, modifier = Modifier.fillMaxSize())
        Box(
            Modifier.fillMaxSize()
                .background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.88f), colors.accent.copy(alpha = 0.36f), Color.Transparent)))
        )
        Row(Modifier.fillMaxSize().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Start listening", color = colors.accent, fontSize = 12.sp, fontWeight = FontWeight.Black)
                Text(
                    song?.title ?: if (loading) "Loading your feed" else "A station is ready",
                    color = Color.White,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    error ?: song?.artist ?: "Refresh or search to tune the feed",
                    color = colors.muted,
                    fontSize = 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    RoundAction(Icons.Rounded.PlayArrow, "Play", onPlay)
                    RoundAction(Icons.Rounded.Radio, "Radio", onRadio)
                }
            }
            TrackArtwork(song = song, modifier = Modifier.size(118.dp))
        }
    }
}

@Composable
private fun DiscoveryGrid(
    onCharts: () -> Unit,
    onMood: () -> Unit,
    onNew: () -> Unit,
    onPlaylists: () -> Unit
) {
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

// (Rest of the helper functions remain mostly the same but with foxyColors() and fixed TrackArtwork)

@Composable
private fun ExploreTile(title: String, icon: ImageVector, color: Color, onClick: () -> Unit, modifier: Modifier) {
    val colors = foxyColors()
    Row(
        modifier = modifier
            .height(86.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(color)
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(42.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.24f)),
            contentAlignment = Alignment.Center
        ) {
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
            Icon(icon, contentDescription = null, tint = foxyColors().accent, modifier = Modifier.size(22.dp))
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
    val colors = foxyColors()
    Box(Modifier.width(148.dp).clickable { onClick() }) {
        Column {
            TrackArtwork(song = song, modifier = Modifier.fillMaxWidth().aspectRatio(1f))
            Text(song.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            Text(song.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconButton(onClick = onMore, modifier = Modifier.align(Alignment.TopEnd).size(34.dp).background(Color.Black.copy(alpha = 0.48f), CircleShape)) {
            Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun CompactHomeSong(
    song: Song,
    isCurrent: Boolean,
    isPlaying: Boolean,
    onClick: () -> Unit,
    onMore: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = foxyColors()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(if (isCurrent) colors.accent.copy(alpha = 0.16f) else Color.Transparent)
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TrackArtwork(song = song, modifier = Modifier.size(54.dp))
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
            Text(it, color = foxyColors().accent, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable { onAction() }.padding(8.dp))
        }
    }
}

@Composable
private fun RoundAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(42.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.15f))
    ) {
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
