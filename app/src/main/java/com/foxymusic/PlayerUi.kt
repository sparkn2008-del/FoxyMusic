package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Article
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
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
import kotlin.math.abs

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

fun Song.artworkCandidates(): List<String> {
    val candidates = mutableListOf<String>()
    if (thumbnail.isNotBlank()) {
        val normalized = thumbnail.replace("http://", "https://").replaceFirst("//", "https://")
        candidates += normalized
        candidates += normalized.upscaleYouTubeMusicArtwork()
    }
    if (videoId.isNotBlank() && !videoId.startsWith("demo")) {
        candidates += "https://i.ytimg.com/vi/$videoId/maxresdefault.jpg"
        candidates += "https://i.ytimg.com/vi/$videoId/hq720.jpg"
        candidates += "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
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

@Composable
fun PersistentMiniPlayer(
    state: PlayerUiState,
    onOpen: () -> Unit,
    onArtist: () -> Unit = {},
    onAdd: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val song = state.currentSong ?: return
    val colors = foxyPalette()
    val library by FoxyLibraryStore.state.collectAsState()
    var dragTotal by remember { mutableStateOf(0f) }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .height(68.dp)
            .clip(RoundedCornerShape(34.dp))
            .background(colors.surfaceHigh)
            .pointerInput(state.queueIndex, state.queue.size) {
                detectHorizontalDragGestures(
                    onDragStart = { dragTotal = 0f },
                    onHorizontalDrag = { _, amount -> dragTotal += amount },
                    onDragEnd = {
                        when {
                            dragTotal < -90f -> MusicPlayer.playNext()
                            dragTotal > 90f -> MusicPlayer.playPrevious()
                        }
                        dragTotal = 0f
                    }
                )
            }
            .clickable { onOpen() }
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(2.dp)
                .align(Alignment.BottomCenter)
                .background(colors.pill)
        ) {
            val progress = (MusicPlayer.currentPosition().toFloat() / MusicPlayer.duration().coerceAtLeast(1L)).coerceIn(0f, 1f)
            Box(Modifier.fillMaxWidth(progress).height(2.dp).background(colors.accent))
        }
        Row(
            modifier = Modifier.fillMaxSize().padding(start = 8.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TrackArtwork(song, Modifier.size(52.dp), 26)
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Text(song.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(state.error ?: song.artist, color = if (state.error == null) colors.muted else Color(0xFFFF8A80), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            IconButton(onClick = { FoxyLibraryStore.toggleLike(song) }) {
                Icon(
                    if (library.isLiked(song)) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                    contentDescription = "Like",
                    tint = if (library.isLiked(song)) colors.accent else colors.muted
                )
            }
            IconButton(onClick = { MusicPlayer.togglePlayPause() }) {
                if (state.isBuffering) {
                    CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                } else {
                    Icon(if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, contentDescription = "Play", tint = Color.White)
                }
            }
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
    var showQueue by remember { mutableStateOf(false) }
    var showLyrics by remember { mutableStateOf(false) }
    var showSleep by remember { mutableStateOf(false) }
    var showAudio by remember { mutableStateOf(false) }

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
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(760.dp)
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .background(colors.background)
        ) {
            AsyncImage(
                model = song.bestPosterUrl(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().blur(34.dp)
            )
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.30f), colors.background, colors.background))))

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 22.dp, vertical = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Now playing", color = colors.muted, fontSize = 13.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                    }
                }

                Box(Modifier.fillMaxWidth().height(322.dp), contentAlignment = Alignment.Center) {
                    TrackArtwork(song, Modifier.size(360.dp).scale(1.32f).blur(18.dp), 28)
                    Box(Modifier.size(344.dp).background(Brush.radialGradient(listOf(Color.Transparent, colors.background.copy(alpha = 0.86f)))))
                    TrackArtwork(
                        song = song,
                        modifier = Modifier
                            .size(282.dp)
                            .shadow(28.dp, RoundedCornerShape(18.dp)),
                        cornerRadius = 18
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(song.title, color = Color.White, fontSize = 25.sp, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, color = colors.muted, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(onClick = { FoxyLibraryStore.toggleLike(song) }) {
                        Icon(
                            if (library.isLiked(song)) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                            contentDescription = "Like",
                            tint = if (library.isLiked(song)) colors.accent else Color.White
                        )
                    }
                }

                PlayerProgress(position)

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    PlayerRoundButton(Icons.Rounded.Shuffle, active = state.shuffleEnabled) { MusicPlayer.toggleShuffle() }
                    PlayerRoundButton(Icons.Rounded.SkipPrevious) { MusicPlayer.playPrevious() }
                    IconButton(
                        onClick = { MusicPlayer.togglePlayPause() },
                        modifier = Modifier.size(78.dp).clip(CircleShape).background(colors.accent)
                    ) {
                        if (state.isBuffering) {
                            CircularProgressIndicator(color = Color.White, strokeWidth = 4.dp, modifier = Modifier.size(32.dp))
                        } else {
                            Icon(if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, contentDescription = "Play", tint = Color.White, modifier = Modifier.size(42.dp))
                        }
                    }
                    PlayerRoundButton(Icons.Rounded.SkipNext) { MusicPlayer.playNext() }
                    PlayerRoundButton(
                        if (state.repeatMode == RepeatMode.One) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                        active = state.repeatMode != RepeatMode.Off
                    ) { MusicPlayer.cycleRepeatMode() }
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 22.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    UtilityPill(Icons.Rounded.QueueMusic, "Queue", showQueue) {
                        showQueue = !showQueue
                        showLyrics = false
                        showAudio = false
                    }
                    UtilityPill(Icons.Rounded.Article, "Lyrics", showLyrics) {
                        showLyrics = !showLyrics
                        showQueue = false
                        showAudio = false
                    }
                    UtilityPill(Icons.Rounded.Bedtime, "Sleep", false) { showSleep = true }
                    UtilityPill(Icons.Rounded.Tune, "Audio", showAudio) {
                        showAudio = !showAudio
                        showQueue = false
                        showLyrics = false
                    }
                    UtilityPill(Icons.Rounded.MoreHoriz, "More", false) { showSongMenu = true }
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    UtilityPill(
                        if (library.isSaved(song)) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                        if (library.isSaved(song)) "Saved" else "Save",
                        library.isSaved(song)
                    ) { FoxyLibraryStore.toggleSaved(song) }
                    UtilityPill(Icons.Rounded.Radio, "Radio", false) { MusicPlayer.startRadio(context, song) }
                    UtilityPill(Icons.Rounded.Add, "Queue", false) { MusicPlayer.addToQueue(song) }
                }

                if (showQueue) QueueCard(state)
                if (showLyrics) LyricsCard(song)
                if (showAudio) AudioCard()
                SongInfoCard(song)
                Spacer(Modifier.height(28.dp))
            }
        }
    }

    if (showSongMenu) SongActionMenu(song = song, onDismiss = { showSongMenu = false })
    if (showSleep) SleepDialog(onDismiss = { showSleep = false })
}

@Composable
private fun PlayerRoundButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    active: Boolean = false,
    onClick: () -> Unit
) {
    val colors = foxyPalette()
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(48.dp).clip(CircleShape).background(if (active) colors.accent.copy(alpha = 0.25f) else colors.surface.copy(alpha = 0.72f))
    ) {
        Icon(icon, contentDescription = null, tint = if (active) colors.accent else Color.White)
    }
}

@Composable
private fun UtilityPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    active: Boolean,
    onClick: () -> Unit
) {
    val colors = foxyPalette()
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { onClick() }) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(if (active) colors.accent.copy(alpha = 0.26f) else colors.surface),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = label, tint = if (active) colors.accent else colors.muted, modifier = Modifier.size(23.dp))
        }
        Text(label, color = colors.muted, fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp))
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
            inactiveTrackColor = Color.White.copy(alpha = 0.16f)
        ),
        modifier = Modifier.padding(top = 18.dp)
    )
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(formatMillis(position), color = FoxyMuted, fontSize = 12.sp)
        Text(formatMillis(duration), color = FoxyMuted, fontSize = 12.sp)
    }
}

@Composable
private fun QueueCard(state: PlayerUiState) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 22.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface.copy(alpha = 0.88f))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("Up next", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
        state.queue.forEachIndexed { index, song ->
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text((index + 1).toString(), color = if (index == state.queueIndex) colors.accent else colors.muted, fontSize = 12.sp, modifier = Modifier.width(24.dp))
                TrackArtwork(song, Modifier.size(42.dp), 4)
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    Text(song.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(song.artist, color = colors.muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconButton(onClick = { MusicPlayer.removeFromQueue(song) }, modifier = Modifier.size(36.dp)) {
                    Icon(Icons.Rounded.Close, contentDescription = "Remove", tint = colors.muted, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

@Composable
private fun AudioCard() {
    val colors = foxyPalette()
    var speed by remember { mutableStateOf(1f) }
    var pitch by remember { mutableStateOf(1f) }
    var volume by remember { mutableStateOf(1f) }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 22.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface.copy(alpha = 0.88f))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.VolumeUp, contentDescription = null, tint = colors.accent)
            Text("Playback controls", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(start = 8.dp))
        }
        Text("Speed ${"%.2f".format(speed)}x", color = colors.muted)
        Slider(value = speed, onValueChange = { speed = it; MusicPlayer.setPlaybackAdjustments(speed, pitch) }, valueRange = 0.5f..2f)
        Text("Pitch ${"%.2f".format(pitch)}x", color = colors.muted)
        Slider(value = pitch, onValueChange = { pitch = it; MusicPlayer.setPlaybackAdjustments(speed, pitch) }, valueRange = 0.5f..2f)
        Text("Volume ${(volume * 100).toInt()}%", color = colors.muted)
        Slider(value = volume, onValueChange = { volume = it; MusicPlayer.setVolume(volume) }, valueRange = 0f..1f)
    }
}

@Composable
private fun SongInfoCard(song: Song) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 22.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface.copy(alpha = 0.78f))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text("Track details", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
        Text(song.title, color = colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(song.artist, color = colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("Video ID ${song.videoId}", color = colors.muted, fontSize = 12.sp)
    }
}

@Composable
private fun LyricsCard(song: Song) {
    val colors = foxyPalette()
    var lyrics by remember(song.videoId) { mutableStateOf<String?>(null) }
    var loading by remember(song.videoId) { mutableStateOf(true) }

    LaunchedEffect(song.videoId) {
        loading = true
        lyrics = YTMusicApi.lyrics(song.videoId)
        loading = false
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 22.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface.copy(alpha = 0.88f))
            .padding(18.dp)
    ) {
        Text("Lyrics", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
        when {
            loading -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.padding(top = 16.dp).size(24.dp))
            lyrics != null -> Text(lyrics.orEmpty(), color = Color.White.copy(alpha = 0.88f), fontSize = 15.sp, lineHeight = 24.sp, modifier = Modifier.padding(top = 12.dp))
            else -> Text("No synced lyrics found for this track yet.", color = colors.muted, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
private fun SleepDialog(onDismiss: () -> Unit) {
    val colors = foxyPalette()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surfaceHigh,
        title = { Text("Sleep timer", color = Color.White, fontWeight = FontWeight.Black) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SleepOption("15 minutes") { MusicPlayer.scheduleSleepTimer(15); onDismiss() }
                SleepOption("30 minutes") { MusicPlayer.scheduleSleepTimer(30); onDismiss() }
                SleepOption("After current song") { MusicPlayer.sleepAfterCurrentSong(); onDismiss() }
                SleepOption("Cancel timer") { MusicPlayer.cancelSleepTimer(); onDismiss() }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } }
    )
}

@Composable
private fun SleepOption(label: String, onClick: () -> Unit) {
    Text(
        label,
        color = foxyPalette().accent,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable { onClick() }.padding(12.dp)
    )
}

private fun formatMillis(value: Long): String {
    val totalSeconds = (value / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "$minutes:${seconds.toString().padStart(2, '0')}"
}
