package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HomeHero(
    song: Song?,
    account: FoxyAccountState,
    loading: Boolean,
    error: String?,
    onPlay: () -> Unit,
    onRefresh: () -> Unit
) {
    val colors = foxyPalette()
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.linearGradient(listOf(colors.surfaceHigh, colors.surface)))
            .padding(18.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TrackArtwork(song = song, modifier = Modifier.size(92.dp), cornerRadius = 22)
            Column(modifier = Modifier.padding(start = 16.dp).weight(1f)) {
                Text(account.displayName, color = colors.muted, fontSize = 13.sp, maxLines = 1)
                Text(
                    text = song?.title ?: if (loading) "Loading your music" else "Ready when you are",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = error ?: song?.artist ?: "Pull down to refresh recommendations",
                    color = colors.muted,
                    fontSize = 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(
                onClick = if (song == null) onRefresh else onPlay,
                modifier = Modifier.clip(CircleShape).background(colors.accent)
            ) {
                Icon(Icons.Rounded.PlayArrow, contentDescription = "Play", tint = Color.White)
            }
        }
    }
}

@Composable
fun HomeSectionHeader(title: String, action: String? = null, onAction: () -> Unit = {}) {
    MetroSectionTitle(title = title, action = action, onAction = onAction)
}

@Composable
fun FoxySongRow(
    song: Song,
    onClick: () -> Unit,
    isCurrent: Boolean = false,
    isPlaying: Boolean = false,
    onMore: (() -> Unit)? = null
) {
    val colors = foxyPalette()
    MetroSongRow(
        song = song,
        modifier = Modifier.background(if (isCurrent) colors.accent.copy(alpha = 0.12f) else Color.Transparent),
        trailing = {
            if (isPlaying) {
                Icon(Icons.Rounded.PlayArrow, contentDescription = "Playing", tint = colors.accent, modifier = Modifier.size(24.dp))
            }
            if (onMore != null) {
                IconButton(onClick = onMore) {
                    Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = colors.muted)
                }
            }
        },
        onClick = onClick
    )
}

@Composable
fun RecommendationRail(
    section: RecommendationSection,
    onSongClick: (Song) -> Unit,
    onSongMore: (Song) -> Unit = {}
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MetroSectionTitle(section.title, modifier = Modifier.padding(horizontal = 18.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Spacer(Modifier.width(6.dp)) }
            items(section.songs, key = { it.videoId }) { song ->
                Box(
                    modifier = Modifier
                        .size(width = 142.dp, height = 204.dp)
                        .clip(RoundedCornerShape(6.dp))
                ) {
                    Column(Modifier.clickable { onSongClick(song) }) {
                        TrackArtwork(song = song, modifier = Modifier.fillMaxWidth().aspectRatio(1f), cornerRadius = 6)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(song.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, color = foxyPalette().muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(
                        onClick = { onSongMore(song) },
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .size(34.dp)
                            .background(Color.Black.copy(alpha = 0.45f), CircleShape)
                    ) {
                        Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = Color.White, modifier = Modifier.size(18.dp))
                    }
                }
            }
            item { Spacer(Modifier.width(6.dp)) }
        }
    }
}

@Composable
fun LibraryHeader(library: FoxyLibraryState) {
    val colors = foxyPalette()
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp)) {
        Text("Library", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Black)
        Text(
            "${library.likedSongs.size} liked - ${library.savedSongs.size} saved - ${library.downloadedSongs.size} downloads",
            color = colors.muted,
            fontSize = 13.sp
        )
    }
}
