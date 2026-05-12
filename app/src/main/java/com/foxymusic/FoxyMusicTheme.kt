package com.foxymusic

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// ==================== Foxy Color System ====================

data class FoxyColors(
    val accent: Color,
    val mint: Color,
    val surface: Color,
    val surfaceSoft: Color,
    val pill: Color,
    val muted: Color,
    val textPrimary: Color = Color.White,
    val textSecondary: Color = Color(0xFFB0B0B0)
)

val FoxyAccent = Color(0xFFFF4D94)
val FoxyMint = Color(0xFF00E5B8)
val FoxySurface = Color(0xFF0F0F0F)
val FoxySurfaceSoft = Color(0xFF1A1A1A)
val FoxyPill = Color(0xFF252525)
val FoxyMuted = Color(0xFF888888)

val LocalFoxyColors = staticCompositionLocalOf<FoxyColors> {
    error("No FoxyColors provided")
}

val FoxyTypography = Typography(
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 22.sp
    )
)

@Composable
fun FoxyMusicTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colors = FoxyColors(
        accent = FoxyAccent,
        mint = FoxyMint,
        surface = FoxySurface,
        surfaceSoft = FoxySurfaceSoft,
        pill = FoxyPill,
        muted = FoxyMuted
    )

    val colorScheme = darkColorScheme(
        primary = FoxyAccent,
        secondary = FoxyMint,
        background = FoxySurface,
        surface = FoxySurface,
        surfaceVariant = FoxySurfaceSoft,
        onBackground = Color.White,
        onSurface = Color.White,
    )

    CompositionLocalProvider(LocalFoxyColors provides colors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = FoxyTypography,
            content = content
        )
    }
}

// Helper functions
@Composable
fun foxyColors(): FoxyColors = LocalFoxyColors.current