package com.foxymusic

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val FoxyColorScheme = darkColorScheme(
    primary = Color(0xFFFF6B35),
    secondary = Color(0xFFFFA500),
    background = Color(0xFF0A0A0A),
    surface = Color(0xFF161616),
    onPrimary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun FoxyMusicTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = FoxyColorScheme,
        content = content
    )
}