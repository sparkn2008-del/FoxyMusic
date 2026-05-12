package com.foxymusic

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongActionMenu(
    song: Song,
    onDismiss: () -> Unit
) {
    val colors = foxyPalette()
    val context = LocalContext.current
    val library by FoxyLibraryStore.state.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showDetails by remember { mutableStateOf(false) }
    var showAdjust by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TrackArtwork(song, Modifier.size(58.dp), 14)
                Column(modifier = Modifier.padding(start = 12.dp).weight(1f)) {
                    Text(song.title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(song.artist, color = colors.muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                ActionIcon(Icons.Rounded.Radio, "Radio", Modifier.weight(1f)) {
                    MusicPlayer.startRadio(context, song)
                    onDismiss()
                }
                ActionIcon(Icons.Rounded.Add, "Playlist", Modifier.weight(1f)) {
                    FoxyLibraryStore.toggleSaved(song)
                    MusicPlayer.addToQueue(song)
                    onDismiss()
                }
                ActionIcon(Icons.Rounded.ContentCopy, "Copy URL", Modifier.weight(1f)) {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("YouTube Music URL", song.youtubeUrl()))
                    onDismiss()
                }
            }

            ActionRow(Icons.Rounded.Album, "View album", "Open related album results") {
                openMusicSearch(context, "${song.title} ${song.artist} album")
                onDismiss()
            }
            ActionRow(Icons.Rounded.Person, "View artist", song.artist) {
                openMusicSearch(context, song.artist)
                onDismiss()
            }
            ActionRow(Icons.Rounded.Download, "Download song", "Save to Downloads in your library") {
                FoxyLibraryStore.download(song)
                onDismiss()
            }
            if (library.isDownloaded(song)) {
                ActionRow(Icons.Rounded.Delete, "Remove download", "Remove from Downloads") {
                    FoxyLibraryStore.removeDownload(song)
                    onDismiss()
                }
            }
            ActionRow(Icons.Rounded.Info, "Details", "Show song metadata") { showDetails = true }
            ActionRow(Icons.Rounded.Settings, "Adjust", "Speed and pitch controls") { showAdjust = true }
            Spacer(modifier = Modifier.height(20.dp))
        }
    }

    if (showDetails) {
        AlertDialog(
            onDismissRequest = { showDetails = false },
            containerColor = colors.surfaceHigh,
            title = { Text("Song details", color = Color.White, fontWeight = FontWeight.Black) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Title: ${song.title}", color = Color.White)
                    Text("Artist: ${song.artist}", color = colors.muted)
                    Text("Video ID: ${song.videoId}", color = colors.muted)
                    Text("URL: ${song.youtubeUrl()}", color = colors.muted)
                }
            },
            confirmButton = { TextButton(onClick = { showDetails = false }) { Text("Done") } }
        )
    }

    if (showAdjust) {
        var speed by remember { mutableFloatStateOf(1f) }
        var pitch by remember { mutableFloatStateOf(1f) }
        var volume by remember { mutableFloatStateOf(1f) }
        AlertDialog(
            onDismissRequest = { showAdjust = false },
            containerColor = colors.surfaceHigh,
            title = { Text("Adjust playback", color = Color.White, fontWeight = FontWeight.Black) },
            text = {
                Column {
                    Text("Speed ${"%.2f".format(speed)}x", color = Color.White)
                    Slider(value = speed, onValueChange = {
                        speed = it
                        MusicPlayer.setPlaybackAdjustments(speed, pitch)
                    }, valueRange = 0.5f..2f)
                    Text("Pitch ${"%.2f".format(pitch)}x", color = Color.White)
                    Slider(value = pitch, onValueChange = {
                        pitch = it
                        MusicPlayer.setPlaybackAdjustments(speed, pitch)
                    }, valueRange = 0.5f..2f)
                    Text("Volume ${(volume * 100).toInt()}%", color = Color.White)
                    Slider(value = volume, onValueChange = {
                        volume = it
                        MusicPlayer.setVolume(volume)
                    }, valueRange = 0f..1f)
                }
            },
            confirmButton = { TextButton(onClick = { showAdjust = false }) { Text("Done") } }
        )
    }
}

@Composable
private fun ActionIcon(icon: ImageVector, label: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = foxyPalette()
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(18.dp))
            .background(colors.surface)
            .clickable { onClick() }
            .padding(vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(icon, contentDescription = label, tint = colors.accent, modifier = Modifier.size(26.dp))
        Spacer(modifier = Modifier.height(6.dp))
        Text(label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun ActionRow(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(colors.surface)
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(25.dp))
        Column(modifier = Modifier.padding(start = 14.dp)) {
            Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = colors.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun openMusicSearch(context: Context, query: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://music.youtube.com/search?q=${Uri.encode(query)}"))
    runCatching { context.startActivity(intent) }
}

private fun Song.youtubeUrl(): String = "https://music.youtube.com/watch?v=$videoId"
