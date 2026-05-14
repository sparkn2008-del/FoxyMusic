package com.foxymusic

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.getValue
import androidx.compose.runtime.Composable
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
    val library by FoxyLibraryStore.state
    val isDownloaded = library.isDownloaded(song)
    val isDownloading = FoxyDownloadManager.isDownloading(song.videoId)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {

            // Song Header
            Row(
                modifier = Modifier.padding(20.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TrackArtwork(song = song, modifier = Modifier.size(64.dp))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = song.title,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                    Text(
                        text = song.artist,
                        fontSize = 14.sp,
                        color = colors.muted
                    )
                }
            }

            Divider(color = colors.muted.copy(alpha = 0.25f), thickness = 1.dp)

            Spacer(Modifier.height(8.dp))

            // Simple Actions
            ActionItem(Icons.Rounded.PlayArrow, "Play") {
                MusicPlayer.play(context, song)
                onDismiss()
            }

            ActionItem(Icons.Rounded.QueuePlayNext, "Play Next") {
                MusicPlayer.enqueuePlayNext(song)
                onDismiss()
            }

            ActionItem(Icons.Rounded.QueueMusic, "Add to Queue") {
                MusicPlayer.addToQueue(song)
                onDismiss()
            }

            if (isDownloaded) {
                ActionItem(Icons.Rounded.Delete, "Remove download") {
                    FoxyDownloadManager.removeDownload(context, song)
                    onDismiss()
                }
            } else {
                ActionItem(Icons.Rounded.Download, if (isDownloading) "Downloading..." else "Download") {
                    if (!isDownloading) FoxyDownloadManager.downloadSong(context, song)
                onDismiss()
                }
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