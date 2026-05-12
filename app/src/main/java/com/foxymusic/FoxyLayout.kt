package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Shared corner radii and screen chrome for the app. */
object FoxyLayout {
    val card = 16.dp
    val tile = 12.dp
    val chip = 24.dp
    val sheetTop = 20.dp
    val bottomBar = 20.dp
}

@Composable
fun Modifier.foxyRootBackground(): Modifier {
    val p = foxyPalette()
    return this.then(
        Modifier.background(
            Brush.verticalGradient(
                colors = listOf(
                    Color(0xFF000000),
                    Color(0xFF0A0A0A),
                    p.background
                )
            )
        )
    )
}

@Composable
fun FoxyScreenBackdrop(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val p = foxyPalette()
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF000000), Color(0xFF101010), p.background)
                )
            ),
        content = content
    )
}

fun Modifier.foxyCardClip(): Modifier = clip(RoundedCornerShape(FoxyLayout.card))
