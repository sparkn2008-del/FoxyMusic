package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

// Keep your existing color vals
val FoxyInk = MetroBlack
val FoxySurface = MetroSurface
val FoxySurfaceSoft = MetroSurfaceHigh
val FoxyAccent = MetroAccent
val FoxyMint = Color(0xFF98E6D1)
val FoxyMuted = MetroMuted

@Composable
fun TrackArtwork(
    song: Song?,
    modifier: Modifier = Modifier,
    cornerRadius: Int = 24
) {
    // Your existing implementation (kept)
    val artworkUrls = remember(song?.videoId, song?.thumbnail) { song?.artworkCandidates() ?: emptyList() }
    var artworkIndex by remember(song?.videoId) { mutableStateOf(0) }
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
                    if (artworkIndex < artworkUrls.lastIndex) artworkIndex++
                }
            )
        } else {
            Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = FoxyAccent, modifier = Modifier.size(42.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullPlayerSheet(
    state: PlayerUiState,
    onDismiss: () -> Unit
) {
    val song = state.currentSong ?: return
    val colors = foxyPalette()
    val context = LocalContext.current
    val library by FoxyLibraryStore.state.collectAsState()

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    var position by remember(song.videoId) { mutableLongStateOf(MusicPlayer.currentPosition()) }
    var showSongMenu by remember { mutableStateOf(false) }
    var showLyrics by remember { mutableStateOf(false) }

    val scrollState = rememberScrollState()

    // Auto-scroll to top when opened
    LaunchedEffect(sheetState.isVisible) {
        if (sheetState.isVisible) scrollState.scrollTo(0)
    }

    LaunchedEffect(song.videoId) {
        while (true) {
            position = MusicPlayer.currentPosition()
            delay(450)
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.Transparent,
        dragHandle = null
    ) {
        Box(modifier = Modifier.fillMaxSize().background(colors.background)) {
            // Blurred Background
            AsyncImage(
                model = song.bestPosterUrl(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().blur(40.dp)
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(0.45f), colors.background)))
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Header
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("NOW PLAYING", color = colors.muted, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                    }
                }

                Spacer(Modifier.height(20.dp))

                // Large Artwork - SimpMusic Style
                Box(
                    modifier = Modifier
                        .size(340.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .shadow(30.dp, RoundedCornerShape(20.dp))
                ) {
                    TrackArtwork(song, Modifier.fillMaxSize(), cornerRadius = 20)
                }

                Spacer(Modifier.height(32.dp))

                // Title & Artist
                Text(
                    song.title,
                    color = Color.White,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                Text(song.artist, color = colors.muted, fontSize = 17.sp)

                Spacer(Modifier.height(24.dp))

                // Progress Bar (use your existing one if available)
                PlayerProgress(position = position, duration = MusicPlayer.duration())

                Spacer(Modifier.height(20.dp))

                // Playback Controls
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { MusicPlayer.toggleShuffle() }) {
                        Icon(Icons.Rounded.Shuffle, null, tint = if (state.shuffleEnabled) colors.accent else Color.White)
                    }
                    IconButton(onClick = { MusicPlayer.playPrevious() }) {
                        Icon(Icons.Rounded.SkipPrevious, null, tint = Color.White, modifier = Modifier.size(32.dp))
                    }

                    IconButton(
                        onClick = { MusicPlayer.togglePlayPause() },
                        modifier = Modifier.size(82.dp).clip(CircleShape).background(colors.accent)
                    ) {
                        if (state.isBuffering) {
                            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(36.dp))
                        } else {
                            Icon(
                                if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                                null,
                                tint = Color.White,
                                modifier = Modifier.size(46.dp)
                            )
                        }
                    }

                    IconButton(onClick = { MusicPlayer.playNext() }) {
                        Icon(Icons.Rounded.SkipNext, null, tint = Color.White, modifier = Modifier.size(32.dp))
                    }
                    IconButton(onClick = { MusicPlayer.cycleRepeatMode() }) {
                        Icon(
                            if (state.repeatMode == RepeatMode.One) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                            null,
                            tint = if (state.repeatMode != RepeatMode.Off) colors.accent else Color.White
                        )
                    }
                }

                Spacer(Modifier.height(28.dp))

                // Action Buttons
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    UtilityPill(
                        icon = if (library.isDownloaded(song)) Icons.Rounded.Delete else Icons.Rounded.Download,
                        label = if (library.isDownloaded(song)) "Remove" else "Download"
                    ) {
                        if (library.isDownloaded(song)) FoxyLibraryStore.removeDownload(song)
                        else FoxyLibraryStore.downloadSong(context, song)
                    }

                    UtilityPill(Icons.Rounded.Article, "Lyrics") { showLyrics = !showLyrics }
                    UtilityPill(Icons.Rounded.QueueMusic, "Queue") { /* TODO */ }
                    UtilityPill(Icons.Rounded.MoreHoriz, "More") { showSongMenu = true }
                }

                if (showLyrics) LyricsCard(song)

                Spacer(Modifier.height(100.dp))
            }
        }
    }

    if (showSongMenu) SongActionMenu(song = song, onDismiss = { showSongMenu = false })
}

// Simple Lyrics Card
@Composable
fun LyricsCard(song: Song) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface.copy(0.95f))
            .padding(20.dp)
    ) {
        Text("Lyrics", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Spacer(Modifier.height(12.dp))
        Text("Lyrics will appear here...", color = colors.muted, fontSize = 16.sp)
    }
}
fun Song.artworkCandidates(): List<String> {
    val candidates = mutableListOf<String>()
    if (thumbnail.isNotBlank()) candidates.add(thumbnail)
    if (videoId.isNotBlank()) {
        candidates.add("https://i.ytimg.com/vi/$videoId/maxresdefault.jpg")
        candidates.add("https://i.ytimg.com/vi/$videoId/hq720.jpg")
        candidates.add("https://i.ytimg.com/vi/$videoId/hqdefault.jpg")
    }
    return candidates.distinct()
}

fun Song.bestArtworkUrl(): String = artworkCandidates().firstOrNull().orEmpty()
fun Song.bestPosterUrl(): String = bestArtworkUrl()