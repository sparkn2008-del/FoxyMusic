package com.foxymusic

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SearchScreen() {
    val colors = foxyPalette()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Song>>(emptyList()) }
    var keywordSections by remember { mutableStateOf<List<RecommendationSection>>(emptyList()) }
    var menuSong by remember { mutableStateOf<Song?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var loadingVideoId by remember { mutableStateOf<String?>(null) }
    val playerState by MusicPlayer.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    LaunchedEffect(query) {
        val typed = query.trim()
        if (typed.length >= 2 && results.isEmpty() && !isLoading) {
            delay(450)
            val suggestions = withContext(Dispatchers.IO) {
                runCatching { YTMusicApi.search(typed).take(10) }.getOrDefault(emptyList())
            }
            if (query.trim() == typed && results.isEmpty()) {
                keywordSections = suggestions.takeIf { it.isNotEmpty() }
                    ?.let { listOf(RecommendationSection("Suggestions for $typed", it)) }
                    ?: emptyList()
            }
        } else if (typed.isBlank() && results.isEmpty()) {
            keywordSections = emptyList()
        }
    }

    fun runSearch(searchText: String = query) {
        if (searchText.isBlank() || isLoading) return
        query = searchText
        isLoading = true
        scope.launch {
            val songs = withContext(Dispatchers.IO) {
                runCatching { YTMusicApi.search(searchText.trim()) }.getOrElse { emptyList() }
            }
            results = songs
            keywordSections = withContext(Dispatchers.IO) {
                val base = searchText.trim()
                listOf(
                    "More like $base" to "$base songs",
                    "$base playlists" to "$base playlist",
                    "$base radio" to "$base mix"
                ).mapNotNull { (title, queryText) ->
                    val related = runCatching { YTMusicApi.search(queryText).take(8) }.getOrDefault(emptyList())
                    related.takeIf { it.isNotEmpty() }?.let { RecommendationSection(title, it) }
                }
            }
            isLoading = false
            if (songs.isEmpty()) {
                snackbarHostState.showSnackbar("No songs found. Try another search.")
            }
        }
    }

    fun playSong(song: Song) {
        loadingVideoId = song.videoId
        scope.launch {
            withContext(Dispatchers.IO) {
                MusicPlayer.playQueue(context, results.ifEmpty { listOf(song) }, results.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0))
            }
            loadingVideoId = null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(colors.surfaceHigh, colors.background),
                    endY = 650f
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp)
        ) {
            Spacer(modifier = Modifier.height(10.dp))
            SearchField(
                query = query,
                onQueryChange = { query = it },
                onSearch = { runSearch() }
            )
            Spacer(modifier = Modifier.height(10.dp))
            if (results.isNotEmpty()) SearchTypeTabs()
            Spacer(modifier = Modifier.height(10.dp))

            when {
                isLoading -> LoadingSearch()
                results.isEmpty() -> if (keywordSections.isNotEmpty()) {
                    LazyColumn(modifier = Modifier.weight(1f)) {
                        items(keywordSections, key = { it.title }) { section ->
                            KeywordRail(section = section, onSongClick = { playSong(it) })
                        }
                    }
                } else {
                    EmptySearch()
                }
                else -> LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    item {
                        Text("Top results", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black)
                    }
                    items(results, key = { it.videoId }) { song ->
                        val isCurrent = playerState.currentSong?.videoId == song.videoId
                        SongItem(
                            song = song,
                            isCurrent = isCurrent,
                            isPlaying = isCurrent && playerState.isPlaying,
                            isLoading = loadingVideoId == song.videoId || (isCurrent && playerState.isBuffering),
                            onClick = { playSong(song) },
                            onMore = { menuSong = song }
                        )
                        Divider(color = Color.White.copy(alpha = 0.05f), thickness = 0.5.dp)
                    }
                    items(keywordSections, key = { it.title }) { section ->
                        KeywordRail(section = section, onSongClick = { playSong(it) })
                    }
                }
            }

            Spacer(modifier = Modifier.height(10.dp))
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 12.dp)
        )

        menuSong?.let { song ->
            SongActionMenu(song = song, onDismiss = { menuSong = null })
        }
    }
}

@Composable
private fun SearchTypeTabs() {
    val tabs = listOf("All", "Songs", "Videos", "Albums", "Artists", "Playlists", "Featured playlists", "Podcasts", "Episodes")
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(tabs) { tab -> MetroChip(tab, selected = tab == "All") }
    }
}

@Composable
private fun KeywordRail(section: RecommendationSection, onSongClick: (Song) -> Unit) {
    val colors = foxyPalette()
    Column(modifier = Modifier.padding(top = 14.dp)) {
        Text(section.title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
        Spacer(modifier = Modifier.height(6.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            section.songs.take(6).forEach { song ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { onSongClick(song) }
                        .padding(horizontal = 2.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.TrendingUp, contentDescription = null, tint = colors.muted, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(song.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Icon(Icons.Rounded.PlayArrow, contentDescription = "Play", tint = colors.accent, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}

@Composable
private fun SuggestionChip(
    suggestion: SearchSuggestion,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(FoxySurface)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Rounded.Search, contentDescription = null, tint = FoxyAccent, modifier = Modifier.size(16.dp))
        Spacer(modifier = Modifier.width(6.dp))
        Text(suggestion.label, color = Color.White, fontSize = 13.sp)
    }
}

@Composable
private fun VoiceSearchChip() {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(FoxyAccent.copy(alpha = 0.16f))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Rounded.Mic, contentDescription = null, tint = FoxyAccent, modifier = Modifier.size(16.dp))
        Spacer(modifier = Modifier.width(6.dp))
        Text("Voice", color = FoxyAccent, fontSize = 13.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit
) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        leadingIcon = {
            Icon(Icons.Rounded.Search, contentDescription = null, tint = FoxyMuted)
        },
        placeholder = { Text("Songs, artists, albums...", color = FoxyMuted) },
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = FoxySurface,
            unfocusedContainerColor = FoxySurface,
            focusedTextColor = Color.White,
            unfocusedTextColor = Color.White,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            cursorColor = FoxyAccent,
        ),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
        singleLine = true
    )
}

@Composable
private fun LoadingSearch() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(color = FoxyAccent)
    }
}

@Composable
private fun EmptySearch() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 42.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(CircleShape)
                .background(FoxySurfaceSoft),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = FoxyAccent, modifier = Modifier.size(34.dp))
        }
        Spacer(modifier = Modifier.height(14.dp))
        Text("Your next repeat is waiting", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Text("Search for a track, artist, or album.", color = FoxyMuted, fontSize = 14.sp)
    }
}

@Composable
fun SongItem(
    song: Song,
    isCurrent: Boolean,
    isPlaying: Boolean,
    isLoading: Boolean,
    onClick: () -> Unit,
    onMore: () -> Unit = {}
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .background(if (isCurrent) FoxyAccent.copy(alpha = 0.12f) else Color.Transparent)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TrackArtwork(song = song, modifier = Modifier.size(54.dp), cornerRadius = 12)
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = song.title,
                color = if (isCurrent) Color.White else Color(0xFFF4F6FA),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = song.artist,
                color = FoxyMuted,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(modifier = Modifier.width(10.dp))
        when {
            isLoading -> CircularProgressIndicator(color = FoxyAccent, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
            isPlaying -> Icon(Icons.Rounded.GraphicEq, contentDescription = "Playing", tint = FoxyMint, modifier = Modifier.size(24.dp))
            else -> IconButton(onClick = onMore) {
                Icon(Icons.Rounded.MoreVert, contentDescription = "Song menu", tint = FoxyMuted, modifier = Modifier.size(24.dp))
            }
        }
    }
}
