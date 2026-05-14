package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest

@Composable
fun TrackArtwork(
    song: Song?,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 12.dp,
    onClick: () -> Unit = {}
) {
    val colors = foxyColors()
    val shape = RoundedCornerShape(cornerRadius)
    val context = LocalContext.current
    val url = song?.highQualityArtworkUrl().orEmpty()

    Box(
        modifier = modifier
            .clip(shape)
            .clickable { onClick() }
            .background(colors.pill, shape),
        contentAlignment = Alignment.Center
    ) {
        if (url.isNotBlank()) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(url)
                    .crossfade(true)
                    .allowHardware(true)
                    .build(),
                contentDescription = song?.title,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }

        if (url.isBlank()) {
            Icon(
                Icons.Rounded.MusicNote,
                contentDescription = null,
                tint = colors.muted.copy(alpha = 0.6f),
                modifier = Modifier.size(32.dp)
            )
        }
    }
}
