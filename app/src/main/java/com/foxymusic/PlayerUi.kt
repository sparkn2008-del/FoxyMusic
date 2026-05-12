package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

// Theme colors
val FoxyInk = MetroBlack
val FoxySurface = MetroSurface
val FoxySurfaceSoft = MetroSurfaceHigh
val FoxyAccent = MetroAccent
val FoxyMint = Color(0xFF98E6D1)
val FoxyMuted = MetroMuted

// =============================================
// HIGH QUALITY TRACK ARTWORK
// =============================================
@Composable
fun TrackArtwork(
    song: Song?,
    modifier: Modifier = Modifier,
    cornerRadius: Int = 24
) {
    val artworkUrls = remember(song?.videoId, song?.thumbnail) { song?.artworkCandidates() ?: emptyList() }
    var artworkIndex by remember { mutableStateOf(0) }
    val currentUrl = artworkUrls.getOrNull(artworkIndex).orEmpty()

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius.dp))
            .background(FoxySurfaceSoft),
        contentAlignment = Alignment.Center
    ) {
        if (currentUrl.isNotBlank()) {
            AsyncImage(
                model = currentUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                onError = {
                    if (artworkIndex < artworkUrls.lastIndex) {
                        artworkIndex++
                    }
                }
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.MusicNote,
                contentDescription = null,
                tint = FoxyAccent,
                modifier = Modifier.size(48.dp)
            )
        }
    }
}

fun Song.artworkCandidates(): List<String> {
    val candidates = mutableListOf<String>()

    if (videoId.isNotBlank() && !videoId.startsWith("demo")) {
        candidates += "https://i.ytimg.com/vi/$videoId/maxresdefault.jpg"
        candidates += "https://i.ytimg.com/vi/$videoId/hq720.jpg"
        candidates += "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
    }

    if (thumbnail.isNotBlank()) {
        val normalized = thumbnail
            .replace("http://", "https://")
            .replaceFirst("//", "https://")
        candidates += normalized
        candidates += normalized.upscaleYouTubeMusicArtwork()
    }

    return candidates.distinct().filter { it.isNotBlank() }
}

fun Song.bestArtworkUrl(): String = artworkCandidates().firstOrNull().orEmpty()
fun Song.bestPosterUrl(): String = bestArtworkUrl()

private fun String.upscaleYouTubeMusicArtwork(): String {
    val sizeMarker = indexOf("=w")
    return if (contains("ytimg.com", ignoreCase = true) && sizeMarker > 0) {
        substring(0, sizeMarker) + "=w720-h720-l90-rj"
    } else {
        this
    }
}

// =============================================
// MINI PLAYER
// =============================================
@Composable
fun PersistentMiniPlayer(
    state: PlayerUiState,
    onOpen: () -> Unit,
    onArtist: () -> Unit = {},
    onAdd: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val song = state.currentSong ?: return
    val settings by FoxySettings.state.collectAsState()
    val library by FoxyLibraryStore.state.collectAsState()
    val colors = foxyPalette()
    val isCompact = settings.compactPlayer

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = if (isCompact) 12.dp else 16.dp, vertical = 8.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surfaceHigh)
            .clickable { onOpen() }
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TrackArtwork(
                song = song,
                modifier = Modifier.size(if (isCompact) 48.dp else 56.dp),
                cornerRadius = 12
            )

            Spacer(modifier = Modifier.width(14.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = song.title,
                    color = Color.White,
                    fontSize = if (isCompact) 14.sp else 15.5.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = state.error ?: song.artist,
                    color = if (state.error != null) MaterialTheme.colorScheme.error else FoxyMuted,
                    fontSize = if (isCompact) 12.sp else 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!isCompact) {
                    MiniActionButton(Icons.Rounded.Person, onArtist)
                }
                MiniActionButton(
                    if (library.isLiked(song)) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder
                ) { FoxyLibraryStore.toggleLike(song) }
                MiniPlayButton(state)
            }
        }
    }
}

@Composable
private fun MiniActionButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit
) {
    IconButton(onClick = onClick, modifier = Modifier.padding(horizontal = 4.dp)) {
        Icon(icon, contentDescription = null, tint = FoxyMuted, modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun MiniPlayButton(state: PlayerUiState) {
    IconButton(
        onClick = { MusicPlayer.togglePlayPause() },
        enabled = !state.isBuffering && state.error == null,
        modifier = Modifier
            .size(52.dp)
            .clip(CircleShape)
            .background(Color.White)
    ) {
        if (state.isBuffering) {
            CircularProgressIndicator(color = MetroBlack, strokeWidth = 2.5.dp, modifier = Modifier.size(22.dp))
        } else {
            Icon(
                imageVector = if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = null,
                tint = MetroBlack,
                modifier = Modifier.size(28.dp)
            )
        }
    }
}

// =============================================
// FULL PLAYER
// =============================================
@Composable
fun FullPlayerSheet(
    state: PlayerUiState,
    onDismiss: () -> Unit
) {
    val song = state.currentSong ?: return
    val colors = foxyPalette()
    val library by FoxyLibraryStore.state.collectAsState()

    var position by remember(song.videoId) { mutableLongStateOf(MusicPlayer.currentPosition()) }
    var showSongMenu by remember { mutableStateOf(false) }
    var shuffleEnabled by remember { mutableStateOf(false) }
    var repeatEnabled by remember { mutableStateOf(false) }

    LaunchedEffect(song.videoId) {
        while (true) {
            position = MusicPlayer.currentPosition()
            delay(400)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
        ) {
            // Background
            AsyncImage(
                model = song.bestPosterUrl(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(680.dp)
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(680.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.65f), Color.Black.copy(alpha = 0.95f))
                        )
                    )
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp, vertical = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Now Playing",
                        color = FoxyMuted,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Main Artwork
                TrackArtwork(
                    song = song,
                    modifier = Modifier
                        .size(320.dp)
                        .shadow(30.dp, RoundedCornerShape(32.dp)),
                    cornerRadius = 32
                )

                Spacer(modifier = Modifier.height(32.dp))

                // Song Info
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = song.title,
                            color = Color.White,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            lineHeight = 28.sp
                        )
                        Text(
                            text = song.artist,
                            color = FoxyMuted,
                            fontSize = 16.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    IconButton(onClick = { FoxyLibraryStore.toggleLike(song) }) {
                        Icon(
                            if (library.isLiked(song)) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                            contentDescription = "Like",
                            tint = if (library.isLiked(song)) colors.accent else FoxyMuted,
                            modifier = Modifier.size(32.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(28.dp))

                // Progress
                PlayerProgress(position = position)

                Spacer(modifier = Modifier.height(24.dp))

                // Controls
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconToggleButton(checked = shuffleEnabled, onCheckedChange = { shuffleEnabled = it }) {
                        Icon(Icons.Rounded.Shuffle, null, tint = if (shuffleEnabled) FoxyAccent else FoxyMuted)
                    }

                    IconButton(onClick = { MusicPlayer.playPrevious() }, modifier = Modifier.size(52.dp)) {
                        Icon(Icons.Rounded.SkipPrevious, null, tint = FoxyMuted, modifier = Modifier.size(36.dp))
                    }

                    IconButton(
                        onClick = { MusicPlayer.togglePlayPause() },
                        enabled = !state.isBuffering && state.error == null,
                        modifier = Modifier
                            .size(78.dp)
                            .clip(CircleShape)
                            .background(FoxyAccent)
                    ) {
                        if (state.isBuffering) {
                            CircularProgressIndicator(
                                color = Color.White,
                                strokeWidth = 4.dp,
                                modifier = Modifier.size(32.dp)
                            )
                        } else {
                            Icon(
                                if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(42.dp)
                            )
                        }
                    }

                    IconButton(onClick = { MusicPlayer.playNext() }, modifier = Modifier.size(52.dp)) {
                        Icon(Icons.Rounded.SkipNext, null, tint = FoxyMuted, modifier = Modifier.size(36.dp))
                    }

                    IconToggleButton(checked = repeatEnabled, onCheckedChange = { repeatEnabled = it }) {
                        Icon(Icons.Rounded.Repeat, null, tint = if (repeatEnabled) FoxyAccent else FoxyMuted)
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))

                PlayerUtilityRow(song = song, library = library, onMore = { showSongMenu = true })
            }
        }
    }

    if (showSongMenu) {
        SongActionMenu(song = song, onDismiss = { showSongMenu = false })
    }
}

// Utility Row
@Composable
private fun PlayerUtilityRow(
    song: Song,
    library: FoxyLibraryState,
    onMore: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        PlayerUtilityButton(Icons.Rounded.QueueMusic, "Queue")
        PlayerUtilityButton(Icons.Rounded.Article, "Lyrics")
        PlayerUtilityButton(Icons.Rounded.Bedtime, "Sleep")
        PlayerUtilityButton(
            if (library.isSaved(song)) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
            if (library.isSaved(song)) "Saved" else "Save"
        ) { FoxyLibraryStore.toggleSaved(song) }
        PlayerUtilityButton(Icons.Rounded.MoreVert, "More", onMore)
    }
}

@Composable
private fun PlayerUtilityButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit = {}
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable { onClick() }
    ) {
        Box(
            modifier = Modifier
                .size(46.dp)
                .clip(CircleShape)
                .background(FoxySurface.copy(alpha = 0.7f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = label, tint = FoxyAccent, modifier = Modifier.size(23.dp))
        }
    }
}

@Composable
private fun PlayerProgress(position: Long) {
    val duration = MusicPlayer.duration().coerceAtLeast(0L)
    val sliderValue = if (duration > 0) position.toFloat().coerceIn(0f, duration.toFloat()) else 0f

    Slider(
        value = sliderValue,
        onValueChange = { MusicPlayer.seekTo(it.toLong()) },
        valueRange = 0f..duration.coerceAtLeast(1L).toFloat(),
        colors = SliderDefaults.colors(
            thumbColor = FoxyAccent,
            activeTrackColor = FoxyAccent,
            inactiveTrackColor = Color.White.copy(alpha = 0.2f)
        )
    )

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(formatMillis(position), color = FoxyMuted, fontSize = 12.sp)
        Text(formatMillis(duration), color = FoxyMuted, fontSize = 12.sp)
    }
}

private fun formatMillis(value: Long): String {
    val totalSeconds = (value / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "$minutes:${seconds.toString().padStart(2, '0')}"
}