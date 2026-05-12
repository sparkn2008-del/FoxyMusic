package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun DownloadsScreen(navController: androidx.navigation.NavController? = null) {
    val colors = foxyPalette()
    val library by FoxyLibraryStore.state.collectAsState()
    var menuSong by remember { mutableStateOf<Song?>(null) }

    Box(modifier = Modifier.fillMaxSize().background(colors.background)) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Spacer(modifier = Modifier.height(12.dp))
                Text("Downloads", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Black)
                Text("${library.downloadedSongs.size} songs saved in your library", color = colors.muted, fontSize = 13.sp)
                Spacer(modifier = Modifier.height(10.dp))
            }

            if (library.downloadedSongs.isEmpty()) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(24.dp))
                            .background(colors.surface)
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Rounded.Download, contentDescription = null, tint = colors.accent)
                        Spacer(modifier = Modifier.height(10.dp))
                        Text("No downloaded songs yet", color = Color.White, fontWeight = FontWeight.Bold)
                        Text("Use the song menu to save tracks here.", color = colors.muted, fontSize = 12.sp)
                    }
                }
            } else {
                items(library.downloadedSongs, key = { it.videoId }) { song ->
                    FoxySongRow(song = song, onClick = {}, isCurrent = false, isPlaying = false)
                }
            }
        }

        menuSong?.let { SongActionMenu(song = it, onDismiss = { menuSong = null }) }
    }
}
