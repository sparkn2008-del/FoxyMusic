package com.foxymusic

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Podcasts
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.navigation.NavController
import kotlinx.coroutines.launch

private val libraryTabs = listOf("Songs", "Playlists", "Albums", "Artists", "Podcasts", "Videos")

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryScreen(navController: NavController? = null) {
    val library by FoxyLibraryStore.state.collectAsState()
    val playerState by MusicPlayer.state.collectAsState()
    val colors = foxyPalette()
    val context = LocalContext.current
    val pagerState = rememberPagerState { libraryTabs.size }
    val scope = rememberCoroutineScope()
    var menuSong by remember { mutableStateOf<Song?>(null) }

    fun play(song: Song, queue: List<Song>) {
        MusicPlayer.playQueue(context, queue.ifEmpty { listOf(song) }, queue.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0))
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color.Black, colors.background)))
    ) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 12.dp)) {
            Text("Library", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Black)
            Text("Your liked, saved, downloaded, and recently played music.", color = colors.muted, fontSize = 13.sp)
        }

        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            LibraryTile(Icons.Rounded.Favorite, "Liked", "${library.likedSongs.size}", Modifier.weight(1f)) {
                library.likedSongs.firstOrNull()?.let { play(it, library.likedSongs) }
            }
            LibraryTile(Icons.Rounded.Download, "Downloads", "${library.downloadedSongs.size}", Modifier.weight(1f)) {
                navController?.navigate("downloads")
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            LibraryTile(Icons.Rounded.History, "History", "${library.history.size}", Modifier.weight(1f)) {
                library.history.firstOrNull()?.let { play(it, library.history) }
            }
            LibraryTile(Icons.Rounded.Search, "Find more", "Search", Modifier.weight(1f)) {
                navController?.navigate("search")
            }
        }

        ScrollableTabRow(
            selectedTabIndex = pagerState.currentPage,
            containerColor = Color.Transparent,
            contentColor = colors.accent,
            edgePadding = 18.dp
        ) {
            libraryTabs.forEachIndexed { index, title ->
                Tab(
                    selected = pagerState.currentPage == index,
                    onClick = { scope.launch { pagerState.animateScrollToPage(index) } },
                    text = { Text(title, fontWeight = FontWeight.Bold) }
                )
            }
        }

        HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { page ->
            when (page) {
                0 -> SongListTab(
                    title = "Liked songs",
                    songs = library.likedSongs.ifEmpty { library.savedSongs.ifEmpty { library.history } },
                    playerState = playerState,
                    onPlay = ::play,
                    onMore = { menuSong = it }
                )
                1 -> CollectionTab(Icons.Rounded.LibraryMusic, "Saved music", library.savedSongs, ::play, { menuSong = it })
                2 -> CollectionTab(Icons.Rounded.Album, "Albums from saved songs", library.savedSongs.distinctBy { it.album ?: it.artist }, ::play, { menuSong = it })
                3 -> CollectionTab(Icons.Rounded.Person, "Artists", library.history.distinctBy { it.artist }, ::play, { menuSong = it })
                4 -> EmptyLibraryTab(Icons.Rounded.Podcasts, "Podcasts will appear here after playback or saving.")
                5 -> CollectionTab(Icons.Rounded.Movie, "Videos", library.history, ::play, { menuSong = it })
            }
        }
    }

    menuSong?.let { SongActionMenu(song = it, onDismiss = { menuSong = null }) }
}

@Composable
private fun LibraryTile(icon: ImageVector, title: String, value: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = foxyPalette()
    Row(
        modifier = modifier
            .height(86.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Brush.linearGradient(listOf(colors.surfaceHigh, colors.surface)))
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(42.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.22f)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = colors.accent)
        }
        Column(Modifier.padding(start = 12.dp)) {
            Text(title, color = Color.White, fontWeight = FontWeight.Black, maxLines = 1)
            Text(value, color = colors.muted, fontSize = 12.sp, maxLines = 1)
        }
    }
}

@Composable
private fun SongListTab(
    title: String,
    songs: List<Song>,
    playerState: PlayerUiState,
    onPlay: (Song, List<Song>) -> Unit,
    onMore: (Song) -> Unit
) {
    val colors = foxyPalette()
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Text(title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 12.dp, bottom = 4.dp))
        }
        if (songs.isEmpty()) {
            item { EmptyLibraryMessage("Save or like songs to fill this page.") }
        } else {
            items(songs, key = { it.videoId }) { song ->
                val isCurrent = playerState.currentSong?.videoId == song.videoId
                FoxySongRow(
                    song = song,
                    isCurrent = isCurrent,
                    isPlaying = isCurrent && playerState.isPlaying,
                    onClick = { onPlay(song, songs) },
                    onMore = { onMore(song) }
                )
            }
        }
    }
}

@Composable
private fun CollectionTab(
    icon: ImageVector,
    title: String,
    songs: List<Song>,
    onPlay: (Song, List<Song>) -> Unit,
    onMore: (Song) -> Unit
) {
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Text(title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 12.dp)) }
        if (songs.isEmpty()) {
            item { EmptyLibraryTab(icon, "Nothing here yet.") }
        } else {
            items(songs, key = { it.videoId }) { song ->
                Row(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(foxyPalette().surface.copy(alpha = 0.7f)).clickable { onPlay(song, songs) }.padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TrackArtwork(song, Modifier.size(58.dp), 6)
                    Column(Modifier.padding(start = 12.dp).weight(1f)) {
                        Text(song.title, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, color = foxyPalette().muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(onClick = { onPlay(song, songs) }) { Icon(Icons.Rounded.PlayArrow, contentDescription = "Play", tint = foxyPalette().accent) }
                    IconButton(onClick = { onMore(song) }) { Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = foxyPalette().muted) }
                }
            }
        }
    }
}

@Composable
private fun EmptyLibraryTab(icon: ImageVector, message: String) {
    Box(Modifier.fillMaxSize().padding(28.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null, tint = foxyPalette().accent, modifier = Modifier.size(40.dp))
            Text(message, color = foxyPalette().muted, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

@Composable
private fun EmptyLibraryMessage(message: String) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(foxyPalette().surface).padding(20.dp), contentAlignment = Alignment.Center) {
        Text(message, color = foxyPalette().muted)
    }
}
