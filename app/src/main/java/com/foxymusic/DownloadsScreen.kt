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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CloudDone
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun DownloadsScreen(navController: androidx.navigation.NavController? = null) {
    val colors = foxyPalette()
    val context = LocalContext.current
    val library by FoxyLibraryStore.state.collectAsState()
    val playerState by MusicPlayer.state.collectAsState()
    var menuSong by remember { mutableStateOf<Song?>(null) }

    fun play(song: Song) {
        val queue = library.downloadedSongs.ifEmpty { listOf(song) }
        MusicPlayer.playQueue(context, queue, queue.indexOfFirst { it.videoId == song.videoId }.coerceAtLeast(0))
    }

    Box(modifier = Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black, colors.background)))) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Spacer(modifier = Modifier.height(12.dp))
                Text("Downloads", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Black)
                Text("${library.downloadedSongs.size} songs ready offline", color = colors.muted, fontSize = 13.sp)
                Spacer(modifier = Modifier.height(8.dp))
            }

            if (library.downloadProgress.isNotEmpty()) {
                item {
                    Column(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(colors.surfaceHigh).padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text("Downloading", color = Color.White, fontWeight = FontWeight.Black)
                        library.downloadProgress.forEach { (videoId, progress) ->
                            val song = (library.savedSongs + library.likedSongs + library.history).firstOrNull { it.videoId == videoId }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(34.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                                    Icon(Icons.Rounded.Download, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                                }
                                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                                    Text(song?.title ?: "Preparing song", color = Color.White, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    LinearProgressIndicator(progress = progress, color = colors.accent, trackColor = colors.pill, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
                                }
                                Text("${(progress * 100).toInt()}%", color = colors.muted, fontSize = 12.sp, modifier = Modifier.padding(start = 10.dp))
                            }
                        }
                    }
                }
            }

            if (library.downloadedSongs.isEmpty()) {
                item {
                    Column(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(colors.surface).padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Rounded.Download, contentDescription = null, tint = colors.accent, modifier = Modifier.size(38.dp))
                        Spacer(modifier = Modifier.height(10.dp))
                        Text("No downloaded songs yet", color = Color.White, fontWeight = FontWeight.Bold)
                        Text("Use any song menu to save tracks here.", color = colors.muted, fontSize = 12.sp)
                    }
                }
            } else {
                items(library.downloadedSongs, key = { it.videoId }) { song ->
                    val isCurrent = playerState.currentSong?.videoId == song.videoId
                    DownloadRow(
                        song = song,
                        isCurrent = isCurrent,
                        isPlaying = isCurrent && playerState.isPlaying,
                        onPlay = { play(song) },
                        onMore = { menuSong = song }
                    )
                }
            }

            item { Spacer(modifier = Modifier.height(96.dp)) }
        }

        menuSong?.let { SongActionMenu(song = it, onDismiss = { menuSong = null }) }
    }
}

@Composable
private fun DownloadRow(song: Song, isCurrent: Boolean, isPlaying: Boolean, onPlay: () -> Unit, onMore: () -> Unit) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(if (isCurrent) colors.accent.copy(alpha = 0.13f) else colors.surface.copy(alpha = 0.72f))
            .clickable { onPlay() }
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TrackArtwork(song, Modifier.size(58.dp), 6)
        Column(Modifier.padding(start = 12.dp).weight(1f)) {
            Text(song.title, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.CloudDone, contentDescription = null, tint = colors.accent, modifier = Modifier.size(14.dp))
                Text(song.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 4.dp))
            }
        }
        IconButton(onClick = onPlay) {
            Icon(if (isPlaying) Icons.Rounded.CloudDone else Icons.Rounded.PlayArrow, contentDescription = "Play", tint = colors.accent)
        }
        IconButton(onClick = onMore) {
            Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = colors.muted)
        }
    }
}
