package com.foxymusic

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// ====================== Foxy Color System ======================

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

/** Default accent — YouTube Music–style red. */
val FoxyAccent = Color(0xFFFF1744)
val FoxyMint = Color(0xFF69F0AE)
val FoxySurface = Color(0xFF121212)
val FoxySurfaceSoft = Color(0xFF1A1A1A)
val FoxyPill = Color(0xFF242424)
val FoxyMuted = Color(0xFF8A8A8A)

val LocalFoxyColors = staticCompositionLocalOf<FoxyColors> {
    error("FoxyColors not provided! Wrap your UI with FoxyMusicTheme")
}

val FoxyTypography = Typography(
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 34.sp
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp
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
        onPrimary = Color.Black,
    )

    CompositionLocalProvider(LocalFoxyColors provides colors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = FoxyTypography,
            content = content
        )
    }
}

// ==================== Easy Access ====================

@Composable
fun foxyColors(): FoxyColors = LocalFoxyColors.current

@Composable
fun foxyPalette(): FoxyPalette {
    val customization by FoxySettings.state.collectAsState()
    val dynamicAccent by FoxyDynamicTheme.accent.collectAsState()
    val systemDark = isSystemInDarkTheme()
    return customization.palette(dynamicAccent, systemDark)
}

// Direct color access (for convenience)
val FoxyAccentColor: Color
    @Composable get() = foxyColors().accent

val FoxyMintColor: Color
    @Composable get() = foxyColors().mint

val FoxyMutedColor: Color
    @Composable get() = foxyColors().muted