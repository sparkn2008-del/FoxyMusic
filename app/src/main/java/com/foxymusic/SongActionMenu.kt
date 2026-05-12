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
import androidx.compose.ui.draw.clip
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
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        dragHandle = {
            Box(
                Modifier
                    .padding(vertical = 8.dp)
                    .width(36.dp)
                    .height(4.dp)
                    .clip(RoundedCornerShape(50))
                    .background(colors.muted.copy(alpha = 0.4f))
            )
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 20.dp)
        ) {
            // Song Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TrackArtwork(
                    song = song,
                    modifier = Modifier.size(60.dp),
                    cornerRadius = 12
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = song.title,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1
                    )
                    Text(
                        text = song.artist,
                        fontSize = 14.sp,
                        color = colors.muted,
                        maxLines = 1
                    )
                }
            }

            Divider(
                color = colors.muted.copy(alpha = 0.15f),
                thickness = 1.dp,
                modifier = Modifier.padding(horizontal = 20.dp)
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Download / Remove Download
            ActionItem(
                icon = if (isDownloaded) Icons.Rounded.Delete else Icons.Rounded.Download,
                title = if (isDownloaded) "Remove Download" else "Download",
                subtitle = if (isDownloaded) "Remove from device" else "Save for offline"
            ) {
                if (isDownloaded) {
                    FoxyLibraryStore.removeDownload(song)
                } else {
                    FoxyLibraryStore.downloadSong(context, song)
                }
                onDismiss()
            }

            ActionItem(Icons.Rounded.PlaylistAdd, "Add to playlist", "Save to your library") { onDismiss() }
            ActionItem(Icons.Rounded.QueueMusic, "Play next", "Add to current queue") {
                MusicPlayer.playNext(song)
                onDismiss()
            }
            ActionItem(Icons.Rounded.Share, "Share", "Share song link") { onDismiss() }
            ActionItem(Icons.Rounded.Info, "Song info", "View details") { onDismiss() }
        }
    }
}

@Composable
private fun ActionItem(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
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
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = colors.accent,
            modifier = Modifier.size(26.dp)
        )

        Spacer(modifier = Modifier.width(20.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 17.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    fontSize = 13.sp,
                    color = colors.muted
                )
            }
        }
    }
}