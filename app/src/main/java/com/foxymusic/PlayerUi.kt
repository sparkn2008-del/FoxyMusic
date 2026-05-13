package com.foxymusic

import android.os.Build
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.MarqueeAnimationMode
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.*
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.*
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.animation.AnimatedVisibility
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import android.widget.Toast

// ====================== Fullscreen player ======================

@Composable
fun PlayerScreen(song: Song?, isPlaying: Boolean) {
    val colors = foxyPalette()
    val settings by FoxySettings.state.collectAsState()
    val playerState by MusicPlayer.state.collectAsState()
    val sleepTimer by MusicPlayer.sleepTimerState.collectAsState()
    val library by FoxyLibraryStore.state
    val context = LocalContext.current
    var queueExpanded by remember { mutableStateOf(false) }
    var lyricsOpen by remember { mutableStateOf(false) }
    var lyricLines by remember { mutableStateOf<List<LyricLine>>(emptyList()) }
    var showSleepDialog by remember { mutableStateOf(false) }
    var sleepClock by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(sleepTimer.mode) {
        while (sleepTimer.mode == SleepTimerMode.AfterMinutes) {
            delay(1000)
            sleepClock = System.currentTimeMillis()
        }
    }

    LaunchedEffect(song?.videoId, settings.lyricsPreferLrclib) {
        lyricsOpen = false
        val s = song ?: run {
            lyricLines = emptyList()
            return@LaunchedEffect
        }
        lyricLines = withContext(Dispatchers.IO) {
            runCatching { LyricsRepository.fetchSyncedLines(s) }.getOrDefault(emptyList())
        }
    }

    val durationMs = playerState.durationMs.coerceAtLeast(1L)
    val progress = (playerState.positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
    val positionMs = playerState.positionMs
    val liked = song?.let { s -> library.likedSongs.any { it.videoId == s.videoId } } == true

    Box(modifier = Modifier.fillMaxSize()) {
        PlayerArtworkBackdrop(
            artworkUrl = song?.highQualityArtworkUrl().orEmpty(),
            blurEnabled = settings.blurEffects
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(12.dp))

            // Large square artwork / cover
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp)
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(28.dp))
                    .background(colors.surfaceHigh)
            ) {
                CoilImageWithFallback(
                    url = song?.bestArtworkUrl().orEmpty(),
                    modifier = Modifier.fillMaxSize(),
                    cornerRadius = 28.dp
                )
            }

            Spacer(Modifier.height(28.dp))

            Text(
                text = song?.title ?: "—",
                color = Color.White,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .basicMarquee(iterations = Int.MAX_VALUE, animationMode = MarqueeAnimationMode.WhileFocused)
                    .focusable()
            )
            Text(
                text = song?.artist.orEmpty(),
                color = colors.muted,
                fontSize = 15.sp,
                maxLines = 1,
                textAlign = TextAlign.Center,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp)
                    .basicMarquee(iterations = Int.MAX_VALUE, animationMode = MarqueeAnimationMode.WhileFocused)
                    .focusable()
            )

            AnimatedVisibility(visible = lyricsOpen) {
                SyncedLyricsPanel(
                    lines = lyricLines,
                    positionMs = positionMs,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 120.dp, max = 240.dp)
                        .padding(top = 16.dp)
                )
            }

            Spacer(Modifier.height(if (lyricsOpen) 12.dp else 28.dp))

            PlayerProgress(
                progress = progress,
                onProgressChange = { p ->
                    MusicPlayer.seekTo((p * durationMs).toLong())
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = playerState.durationMs > 750L
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(formatPlaybackTime(positionMs), color = colors.muted, fontSize = 12.sp)
                Text(formatPlaybackTime(durationMs), color = colors.muted, fontSize = 12.sp)
            }

            Spacer(Modifier.height(20.dp))

            FoxyMainTransportRow(isPlaying = isPlaying, ui = playerState)

            Spacer(Modifier.height(22.dp))

            val sleepLabel = when (sleepTimer.mode) {
                SleepTimerMode.Off -> "Sleep timer"
                SleepTimerMode.AfterCurrentTrack -> "Sleep: after track"
                SleepTimerMode.AfterMinutes -> {
                    val m = ((sleepTimer.fireAtEpochMs - sleepClock) / 60_000L).toInt().coerceAtLeast(0)
                    if (m <= 0) "Sleep: ending…" else "Sleep: ${m}m left"
                }
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                UtilityPill(
                    Icons.Rounded.QueueMusic,
                    if (queueExpanded) "Hide queue" else "Queue",
                    onClick = { queueExpanded = !queueExpanded },
                    Modifier.weight(1f)
                )
                UtilityPill(
                    Icons.Rounded.Bedtime,
                    sleepLabel,
                    onClick = { showSleepDialog = true },
                    Modifier.weight(1f)
                )
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
            ) {
                UtilityPill(
                    Icons.Rounded.Lyrics,
                    if (lyricsOpen) "Hide lyrics" else "Lyrics",
                    onClick = {
                        if (lyricLines.isEmpty()) {
                            Toast.makeText(context, "No synced lyrics found (try LRCLIB or captions).", Toast.LENGTH_SHORT).show()
                        } else {
                            lyricsOpen = !lyricsOpen
                        }
                    },
                    Modifier.weight(1f)
                )
                UtilityPill(
                    if (liked) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                    if (liked) "Liked" else "Like",
                    onClick = { song?.let { FoxyLibraryStore.toggleLiked(it) } },
                    Modifier.weight(1f)
                )
            }

            if (showSleepDialog) {
                AlertDialog(
                    onDismissRequest = { showSleepDialog = false },
                    containerColor = colors.surfaceHigh,
                    titleContentColor = Color.White,
                    textContentColor = Color.White,
                    title = { Text("Sleep timer", fontWeight = FontWeight.Bold) },
                    text = {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            if (sleepTimer.mode != SleepTimerMode.Off) {
                                TextButton(onClick = {
                                    MusicPlayer.cancelSleepTimer()
                                    showSleepDialog = false
                                }) {
                                    Text("Turn off", color = colors.accent)
                                }
                            }
                            TextButton(onClick = {
                                MusicPlayer.sleepAfterCurrentSong()
                                showSleepDialog = false
                                Toast.makeText(context, "Playback will stop after this track.", Toast.LENGTH_SHORT).show()
                            }) {
                                Text("When current track ends", color = Color.White)
                            }
                            listOf(5, 15, 30, 45, 60).forEach { minutes ->
                                TextButton(onClick = {
                                    MusicPlayer.scheduleSleepTimer(minutes)
                                    showSleepDialog = false
                                    Toast.makeText(context, "Sleeping in $minutes minutes.", Toast.LENGTH_SHORT).show()
                                }) {
                                    Text("$minutes minutes", color = Color.White)
                                }
                            }
                        }
                    },
                    confirmButton = {
                        TextButton(onClick = { showSleepDialog = false }) {
                            Text("Cancel", color = colors.muted)
                        }
                    }
                )
            }

            AnimatedVisibility(visible = queueExpanded) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 280.dp)
                        .padding(top = 12.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(colors.surface)
                ) {
                    itemsIndexed(playerState.queue, key = { _, s -> s.videoId }) { index, track ->
                        val current = index == playerState.queueIndex
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(if (current) colors.accent.copy(alpha = 0.14f) else Color.Transparent)
                                .clickable {
                                    MusicPlayer.skipToQueueIndex(context, index)
                                    queueExpanded = false
                                }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "${index + 1}",
                                color = colors.muted,
                                fontSize = 13.sp,
                                modifier = Modifier.width(28.dp)
                            )
                            Column(Modifier.weight(1f)) {
                                Text(track.title, color = Color.White, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(track.artist, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun PlayerArtworkBackdrop(artworkUrl: String, blurEnabled: Boolean) {
    val colors = foxyPalette()
    val context = LocalContext.current
    Box(Modifier.fillMaxSize()) {
        if (artworkUrl.isNotBlank()) {
            val imgMod = Modifier
                .matchParentSize()
                .graphicsLayer {
                    scaleX = 1.22f
                    scaleY = 1.22f
                }
                .then(
                    if (blurEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Modifier.blur(52.dp)
                    } else {
                        Modifier
                    }
                )
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(artworkUrl)
                    .crossfade(false)
                    .allowHardware(true)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = imgMod
            )
        } else {
            Box(Modifier.fillMaxSize().background(colors.background))
        }
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.42f),
                            Color.Black.copy(alpha = 0.74f),
                            colors.background.copy(alpha = 0.94f)
                        )
                    )
                )
        )
    }
}

@Composable
private fun SyncedLyricsPanel(
    lines: List<LyricLine>,
    positionMs: Long,
    modifier: Modifier = Modifier
) {
    val colors = foxyPalette()
    val listState = rememberLazyListState()
    val activeIndex = remember(positionMs, lines) {
        if (lines.isEmpty()) 0
        else lines.indexOfLast { it.timeMs <= positionMs + 480L }.coerceAtLeast(0).coerceAtMost(lines.lastIndex)
    }
    LazyColumn(
        state = listState,
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color.Black.copy(alpha = 0.35f))
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        itemsIndexed(lines, key = { i, line -> "${line.timeMs}_$i" }) { i, line ->
            val active = i == activeIndex
            Text(
                text = line.text,
                color = if (active) Color.White else colors.muted.copy(alpha = 0.85f),
                fontSize = if (active) 17.sp else 15.sp,
                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
            )
        }
    }
}

@Composable
private fun FoxyMainTransportRow(isPlaying: Boolean, ui: PlayerUiState) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(96.dp)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        IconButton(onClick = { MusicPlayer.toggleShuffle() }) {
            Icon(
                Icons.Rounded.Shuffle,
                contentDescription = "Shuffle",
                tint = if (ui.shuffleEnabled) colors.accent else colors.muted,
                modifier = Modifier.size(28.dp)
            )
        }
        IconButton(onClick = { MusicPlayer.playPrevious() }) {
            Icon(
                Icons.Rounded.SkipPrevious,
                contentDescription = "Previous",
                tint = Color.White,
                modifier = Modifier.size(40.dp)
            )
        }
        FilledIconButton(
            onClick = { MusicPlayer.togglePlayPause() },
            modifier = Modifier.size(76.dp),
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = Color.White.copy(alpha = 0.14f),
                contentColor = Color.White
            ),
            shape = CircleShape
        ) {
            Icon(
                imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = "Play",
                modifier = Modifier.size(52.dp)
            )
        }
        IconButton(onClick = { MusicPlayer.playNext() }) {
            Icon(
                Icons.Rounded.SkipNext,
                contentDescription = "Next",
                tint = Color.White,
                modifier = Modifier.size(40.dp)
            )
        }
        IconButton(onClick = { MusicPlayer.cycleRepeatMode() }) {
            val tint = when (ui.repeatMode) {
                RepeatMode.Off -> colors.muted
                RepeatMode.All, RepeatMode.One -> colors.accent
            }
            Icon(
                imageVector = if (ui.repeatMode == RepeatMode.One) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                contentDescription = "Repeat",
                tint = tint,
                modifier = Modifier.size(28.dp)
            )
        }
    }
}

// ====================== Mini player ======================

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PersistentMiniPlayer(
    state: PlayerUiState,
    onOpen: () -> Unit,
    onPlayPause: () -> Unit = { MusicPlayer.togglePlayPause() }
) {
    val song = state.currentSong
    if (song == null) {
        Spacer(Modifier.height(0.dp))
        return
    }

    val colors = foxyPalette()
    val scope = rememberCoroutineScope()
    val offsetX = remember { Animatable(0f) }
    val offsetY = remember { Animatable(0f) }

    val settings by FoxySettings.state.collectAsState()
    val library by FoxyLibraryStore.state
    val liked = library.likedSongs.any { it.videoId == song.videoId }
    val dur = state.durationMs.coerceAtLeast(1L)
    val progress = (state.positionMs.toFloat() / dur.toFloat()).coerceIn(0f, 1f)

    val animatedProgress by animateFloatAsState(
        targetValue = progress,
        animationSpec = ProgressIndicatorDefaults.ProgressAnimationSpec,
        label = "mini_player_progress"
    )

    val verticalSwipeModifier =
        if (settings.gestureControls) {
            Modifier.pointerInput(Unit) {
                detectVerticalDragGestures(
                    onVerticalDrag = { change: PointerInputChange, dragAmount: Float ->
                        if (offsetY.value + dragAmount > 0) {
                            scope.launch {
                                change.consume()
                                offsetY.snapTo(offsetY.value + dragAmount * 1.65f)
                            }
                        }
                    },
                    onDragCancel = {
                        scope.launch { offsetY.animateTo(0f) }
                    },
                    onDragEnd = {
                        scope.launch {
                            if (offsetY.value > 70f) {
                                MusicPlayer.pause()
                            }
                            offsetY.animateTo(0f)
                        }
                    }
                )
            }
        } else {
            Modifier
        }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
    Card(
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surfaceHigh.copy(alpha = 0.92f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(if (settings.compactPlayer) 52.dp else 60.dp)
            .offset { IntOffset(0, offsetY.value.roundToInt()) }
            .then(verticalSwipeModifier)
    ) {
        Box(Modifier.fillMaxSize()) {
            Row(
                Modifier
                    .fillMaxSize()
                    .padding(start = 8.dp, end = 4.dp, top = 2.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .weight(1f)
                        .offset { IntOffset(offsetX.value.roundToInt(), 0) }
                        .then(
                            if (settings.gestureControls) {
                                Modifier.pointerInput(Unit) {
                                    detectHorizontalDragGestures(
                                        onHorizontalDrag = { change: PointerInputChange, dragAmount: Float ->
                                            scope.launch {
                                                change.consume()
                                                offsetX.snapTo(offsetX.value + dragAmount * 2f)
                                            }
                                        },
                                        onDragCancel = {
                                            scope.launch {
                                                when {
                                                    offsetX.value > 200f -> MusicPlayer.playPrevious()
                                                    offsetX.value < -120f -> MusicPlayer.playNext()
                                                }
                                                offsetX.animateTo(0f)
                                            }
                                        },
                                        onDragEnd = {
                                            scope.launch {
                                                when {
                                                    offsetX.value > 200f -> MusicPlayer.playPrevious()
                                                    offsetX.value < -120f -> MusicPlayer.playNext()
                                                }
                                                offsetX.animateTo(0f)
                                            }
                                        }
                                    )
                                }
                            } else {
                                Modifier
                            }
                        )
                        .clickable(onClick = onOpen)
                ) {
                    MiniArtworkThumb(song = song, colors = colors, thumbDp = if (settings.compactPlayer) 36.dp else 44.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            song.title,
                            color = Color.White,
                            style = MaterialTheme.typography.labelLarge,
                            maxLines = 1,
                            modifier = Modifier
                                .fillMaxWidth()
                                .basicMarquee(
                                    iterations = Int.MAX_VALUE,
                                    animationMode = MarqueeAnimationMode.Immediately
                                )
                                .focusable()
                        )
                        Text(
                            song.artist,
                            color = colors.muted,
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 1,
                            modifier = Modifier
                                .fillMaxWidth()
                                .basicMarquee(
                                    iterations = Int.MAX_VALUE,
                                    animationMode = MarqueeAnimationMode.Immediately
                                )
                                .focusable()
                        )
                    }
                }

                Spacer(Modifier.width(15.dp))

                IconButton(onClick = { FoxyLibraryStore.toggleLiked(song) }) {
                    Icon(
                        if (liked) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                        contentDescription = "Like",
                        tint = if (liked) colors.accent else colors.muted
                    )
                }

                Spacer(Modifier.width(15.dp))

                Crossfade(targetState = state.isBuffering, label = "mini_buf") { buffering ->
                    if (buffering) {
                        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(
                                Modifier.size(18.dp),
                                color = Color.LightGray,
                                strokeWidth = 3.dp
                            )
                        }
                    } else {
                        IconButton(onClick = onPlayPause, modifier = Modifier.size(48.dp)) {
                            Icon(
                                if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                                contentDescription = "Play",
                                tint = colors.accent,
                                modifier = Modifier.size(30.dp)
                            )
                        }
                    }
                }
            }

            LinearProgressIndicator(
                progress = { animatedProgress },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(2.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = colors.accent,
                trackColor = Color.White.copy(alpha = 0.08f),
                strokeCap = StrokeCap.Round,
                drawStopIndicator = {}
            )
        }
    }
    }
}

@Composable
private fun MiniArtworkThumb(song: Song, colors: FoxyPalette, thumbDp: androidx.compose.ui.unit.Dp = 44.dp) {
    val url = song.highQualityArtworkUrl()
    val r = (thumbDp.value * 0.22f).dp
    val context = LocalContext.current
    if (url.isBlank()) {
        Box(
            Modifier
                .size(thumbDp)
                .clip(RoundedCornerShape(r))
                .background(colors.pill),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Rounded.MusicNote, null, tint = colors.muted, modifier = Modifier.size((thumbDp.value * 0.5f).dp))
        }
    } else {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(url)
                .crossfade(true)
                .allowHardware(true)
                .build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(thumbDp)
                .clip(RoundedCornerShape(r))
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun FullPlayerSheet(state: PlayerUiState, onDismiss: () -> Unit) {
    val colors = foxyPalette()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.background,
        dragHandle = {
            BottomSheetDefaults.DragHandle(
                modifier = Modifier.padding(vertical = 8.dp),
                color = colors.muted.copy(alpha = 0.5f)
            )
        }
    ) {
        PlayerScreen(
            song = state.currentSong,
            isPlaying = state.isPlaying
        )
    }
}

// ====================== Reusable Components ======================

@Composable
fun PlayerProgress(
    progress: Float,
    onProgressChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    val colors = foxyPalette()

    Slider(
        value = progress.coerceIn(0f, 1f),
        onValueChange = onProgressChange,
        enabled = enabled,
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
            .clip(RoundedCornerShape(12.dp))
            .background(color = colors.surfaceHigh.copy(alpha = 0.88f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = colors.accent,
            modifier = Modifier.size(20.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(text, color = Color.White, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun CoilImage(
    url: String,
    modifier: Modifier = Modifier
) {
    CoilImageWithFallback(url, modifier, cornerRadius = 16.dp)
}

@Composable
private fun CoilImageWithFallback(
    url: String,
    modifier: Modifier = Modifier,
    cornerRadius: androidx.compose.ui.unit.Dp = 16.dp
) {
    val colors = foxyPalette()
    val shape = RoundedCornerShape(cornerRadius)
    val context = LocalContext.current
    if (url.isBlank()) {
        Box(
            modifier = modifier
                .clip(shape)
                .background(colors.pill),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Rounded.MusicNote, null, tint = colors.muted.copy(alpha = 0.5f), modifier = Modifier.size(48.dp))
        }
    } else {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(url)
                .crossfade(true)
                .allowHardware(true)
                .build(),
            contentDescription = null,
            modifier = modifier.clip(shape),
            contentScale = ContentScale.Crop
        )
    }
}

private fun formatPlaybackTime(ms: Long): String {
    val totalSec = (ms / 1000).coerceAtLeast(0)
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
