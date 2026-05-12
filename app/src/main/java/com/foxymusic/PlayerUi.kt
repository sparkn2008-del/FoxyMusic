package com.foxymusic

import androidx.compose.foundation.background
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ====================== Main Player UI ======================

@Composable
fun PlayerScreen(song: Song?, isPlaying: Boolean, progress: Float, onProgressChange: (Float) -> Unit) {
    val colors = foxyPalette()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))

        // Artwork
        Box(
            modifier = Modifier
                .size(280.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(colors.surfaceHigh)
        ) {
            CoilImage(
                url = song?.bestArtworkUrl() ?: "",
                modifier = Modifier.fillMaxSize()
            )
        }

        Spacer(modifier = Modifier.height(48.dp))

        // Song Info
        Text(
            text = song?.title ?: "No Song Playing",
            fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = song?.artist ?: "",
            fontSize = 16.sp,
            color = colors.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Progress Bar
        PlayerProgress(
            progress = progress,
            onProgressChange = onProgressChange
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Time
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("0:00", color = colors.muted, fontSize = 12.sp)
            Text(song?.duration ?: "--:--", color = colors.muted, fontSize = 12.sp)
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Controls
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { MusicPlayer.previous() }) {
                Icon(Icons.Rounded.SkipPrevious, contentDescription = "Previous", tint = Color.White, modifier = Modifier.size(32.dp))
            }

            IconButton(onClick = { MusicPlayer.togglePlayPause() }) {
                Icon(
                    if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = "Play/Pause",
                    tint = Color.White,
                    modifier = Modifier.size(64.dp)
                )
            }

            IconButton(onClick = { MusicPlayer.next() }) {
                Icon(Icons.Rounded.SkipNext, contentDescription = "Next", tint = Color.White, modifier = Modifier.size(32.dp))
            }
        }

        Spacer(modifier = Modifier.height(40.dp))

        // Utility Pills
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            UtilityPill(Icons.Rounded.QueueMusic, "Queue") { }
            UtilityPill(Icons.Rounded.Lyrics, "Lyrics") { }
            UtilityPill(Icons.Rounded.FavoriteBorder, "Like") { }
        }
    }
}

// ====================== Persistent Mini Player ======================

@Composable
fun PersistentMiniPlayer(
    song: Song?,
    isPlaying: Boolean,
    progress: Float,
    onClick: () -> Unit,
    onPlayPause: () -> Unit
) {
    if (song == null) return

    val colors = foxyPalette()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(72.dp)
            .background(colors.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CoilImage(
            url = song.bestArtworkUrl(),
            modifier = Modifier.size(48.dp).clip(RoundedCornerShape(8.dp))
        )

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = song.title,
                color = Color.White,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = song.artist,
                color = colors.muted,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        IconButton(onClick = onPlayPause) {
            Icon(
                if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = null,
                tint = colors.accent
            )
        }
    }
}

// ====================== Reusable Components ======================

@Composable
fun PlayerProgress(
    progress: Float,
    onProgressChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = foxyPalette()

    Slider(
        value = progress,
        onValueChange = onProgressChange,
        modifier = modifier,
        colors = SliderDefaults.colors(
            thumbColor = colors.accent,
            activeTrackColor = colors.accent,
            inactiveTrackColor = colors.muted.copy(alpha = 0.3f)
        )
    )
}

@Composable
fun UtilityPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = foxyPalette()

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(colors.surfaceHigh)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = colors.accent,
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(text, color = Color.White, fontSize = 13.sp)
    }
}

// ====================== Helper Image Composable ======================

@Composable
fun CoilImage(
    url: String,
    modifier: Modifier = Modifier
) {
    // You can replace this with actual Coil implementation
    Box(modifier = modifier.background(Color.DarkGray))
}