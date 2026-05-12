package com.foxymusic

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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.Cached
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlaylistPlay
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Sort
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController

private val libraryTabs = listOf("Playlists", "Songs", "Albums", "Artists", "Downloads", "History")

private val libraryCards = listOf(
    LibraryCard("Liked Songs", Icons.Rounded.Favorite, "Songs you save", "profile", Color(0xFFFF7A45)),
    LibraryCard("Downloaded", Icons.Rounded.CheckCircle, "Offline music", "downloads", Color(0xFF55C7A4)),
    LibraryCard("Recently Played", Icons.Rounded.History, "Listening trail", "history", Color(0xFF8EA7FF)),
    LibraryCard("My Top Mix", Icons.Rounded.TrendingUp, "Smart collection", "stats", Color(0xFFE6B34A)),
    LibraryCard("Cached", Icons.Rounded.Cached, "Fast replay", "storage", Color(0xFF73D1E5)),
    LibraryCard("Artists", Icons.Rounded.Person, "People you follow", "search", Color(0xFFE97895))
)

private data class LibraryCard(
    val title: String,
    val icon: ImageVector,
    val subtitle: String,
    val route: String,
    val tint: Color
)

@Composable
fun LibraryScreen(navController: NavController? = null) {
    val settings by FoxySettings.state.collectAsState()
    val library by FoxyLibraryStore.state.collectAsState()
    val colors = foxyPalette()
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            item {
                LibraryHeader(library)
            }

            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(libraryTabs) { tab ->
                        MetroChip(label = tab, selected = tab == "Playlists")
                    }
                }
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.Sort, contentDescription = null, tint = colors.accent, modifier = Modifier.size(20.dp))
                    Text("Recently updated", color = colors.accent, fontSize = 15.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 6.dp))
                    Icon(Icons.Rounded.ArrowDownward, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.weight(1f))
                    Icon(Icons.Rounded.Search, contentDescription = "Search library", tint = Color.White, modifier = Modifier.size(28.dp))
                }
            }

            item {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    userScrollEnabled = false,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.height(590.dp)
                ) {
                    items(libraryCards) { card ->
                        LibraryGridCard(card = card, onClick = { navController?.navigate(card.route) })
                    }
                }
            }

            item {
                if (library.likedSongs.isNotEmpty()) {
                    MetroSectionTitle("Liked songs")
                    Spacer(modifier = Modifier.height(8.dp))
                    library.likedSongs.take(5).forEach { song ->
                        FoxySongRow(song = song, onClick = {})
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                }
                MetroIconTile(Icons.Rounded.PlaylistPlay, "Create smart playlist", "Build a playlist from mood, artist, or song seeds")
                Spacer(modifier = Modifier.height(90.dp))
            }
        }

        FloatingActionButton(
            onClick = { navController?.navigate("search") },
            containerColor = colors.accent,
            contentColor = Color.White,
            shape = CircleShape,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 24.dp, bottom = 108.dp)
                .size(64.dp)
        ) {
            Icon(Icons.Rounded.Add, contentDescription = "Create playlist", modifier = Modifier.size(30.dp))
        }
    }
}

@Composable
private fun LibraryHeader(library: FoxyLibraryState) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.linearGradient(listOf(Color(0xFF20332E), Color(0xFF111313))))
            .padding(18.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(colors.accent.copy(alpha = 0.22f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Rounded.Album, contentDescription = null, tint = colors.accent, modifier = Modifier.size(30.dp))
            }
            Column(modifier = Modifier.padding(start = 14.dp)) {
                Text("Your Library", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black)
                Text("${library.likedSongs.size} liked • ${library.savedSongs.size} saved • ${library.history.size} played", color = colors.muted, fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun LibraryGridCard(card: LibraryCard, onClick: () -> Unit) {
    val colors = foxyPalette()
    Column(modifier = Modifier.clickable { onClick() }) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(22.dp))
                .background(
                    Brush.linearGradient(
                        listOf(card.tint.copy(alpha = 0.72f), colors.surfaceHigh, Color.Black)
                    )
                )
                .padding(14.dp),
            contentAlignment = Alignment.BottomStart
        ) {
            Icon(card.icon, contentDescription = null, tint = Color.White, modifier = Modifier.align(Alignment.TopStart).size(42.dp))
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.46f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Rounded.PlaylistPlay, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(card.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(card.subtitle, color = colors.muted, fontSize = 12.sp, maxLines = 1)
    }
}
