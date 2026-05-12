package com.foxymusic

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongActionMenu(
    song: Song,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val colors = foxyPalette()

    val library by FoxyLibraryStore.state.collectAsState()
    val isDownloaded = library.isDownloaded(song)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {

            // Header
            Row(
                modifier = Modifier.padding(20.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TrackArtwork(song = song, modifier = Modifier.size(64.dp))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(song.title, fontWeight = FontWeight.SemiBold, color = Color.White, fontSize = 17.sp)
                    Text(song.artist, color = colors.muted, fontSize = 14.sp)
                }
            }

            Divider(color = colors.muted.copy(alpha = 0.2f), thickness = 1.dp)

            Spacer(Modifier.height(8.dp))

            ActionItem(Icons.Rounded.PlayArrow, "Play") {
                MusicPlayer.play(context, song)
                onDismiss()
            }

            ActionItem(Icons.Rounded.QueuePlayNext, "Play Next") {
                MusicPlayer.playNext(song)
                onDismiss()
            }

            ActionItem(Icons.Rounded.QueueMusic, "Add to Queue") {
                MusicPlayer.addToQueue(song)
                onDismiss()
            }

            ActionItem(
                if (isDownloaded) Icons.Rounded.Delete else Icons.Rounded.Download,
                if (isDownloaded) "Remove Download" else "Download"
            ) {
                if (isDownloaded) {
                    FoxyLibraryStore.removeDownload(song, context)
                } else {
                    FoxyLibraryStore.downloadSong(context, song)
                }
                onDismiss()
            }

            ActionItem(Icons.Rounded.PlaylistAdd, "Add to Playlist") { onDismiss() }
            ActionItem(Icons.Rounded.Share, "Share") { onDismiss() }
        }
    }
}

@Composable
private fun ActionItem(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit
) {
    val colors = foxyPalette()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = colors.accent, modifier = Modifier.size(26.dp))
        Spacer(Modifier.width(20.dp))
        Text(title, color = Color.White, fontSize = 17.sp)
    }
}