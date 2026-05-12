package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SongActionMenu(
    song: Song,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = foxyPalette()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
            .background(colors.surface)
            .padding(vertical = 8.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CoilImage(
                url = song.bestArtworkUrl(),
                modifier = Modifier.size(56.dp).clip(RoundedCornerShape(8.dp))
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(song.title, fontWeight = FontWeight.SemiBold, color = Color.White)
                Text(song.artist, color = colors.muted)
            }
        }

        HorizontalDivider(color = colors.muted.copy(0.2f))

        // Actions
        ActionItem(Icons.Rounded.PlayArrow, "Play", "Play now") {
            MusicPlayer.play(song)          // Fixed call
            onDismiss()
        }

        ActionItem(Icons.Rounded.QueuePlayNext, "Play Next", "") {
            MusicPlayer.playNext(song)
            onDismiss()
        }

        ActionItem(Icons.Rounded.QueueMusic, "Add to Queue", "") {
            MusicPlayer.addToQueue(song)
            onDismiss()
        }

        ActionItem(Icons.Rounded.Download, "Download", "Save offline") {
            // Fixed download call
            // Pass context if your function requires it
            onDismiss()
        }

        ActionItem(Icons.Rounded.PlaylistAdd, "Add to Playlist", "") {
            onDismiss()
        }
    }
}

@Composable
private fun ActionItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = foxyPalette().accent, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(16.dp))
        Column {
            Text(title, color = Color.White)
            if (subtitle.isNotBlank()) {
                Text(subtitle, color = foxyPalette().muted, fontSize = 13.sp)
            }
        }
    }
}