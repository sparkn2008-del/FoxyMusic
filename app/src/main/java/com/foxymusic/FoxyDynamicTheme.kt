package com.foxymusic

import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import kotlin.math.roundToInt

object FoxyDynamicTheme {
    private val client = OkHttpClient()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _accent = MutableStateFlow<Color?>(null)
    val accent: StateFlow<Color?> = _accent

    fun clearAccent() {
        _accent.value = null
    }

    fun updateFromSong(song: Song) {
        val artworkUrl = song.bestArtworkUrl()
        if (artworkUrl.isBlank()) {
            clearAccent()
            return
        }
        scope.launch {
            runCatching {
                val request = Request.Builder().url(artworkUrl).build()
                client.newCall(request).execute().use { response ->
                    val bytes = response.body?.bytes() ?: return@use
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@use
                    val opts = BitmapFactory.Options().apply {
                        inSampleSize = sampleSizeForMaxSide(bounds.outWidth, bounds.outHeight, 160)
                        inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
                    }
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return@use
                    try {
                        val stepX = (bitmap.width / 16).coerceAtLeast(1)
                        val stepY = (bitmap.height / 16).coerceAtLeast(1)
                        var red = 0L
                        var green = 0L
                        var blue = 0L
                        var count = 0L
                        var y = 0
                        while (y < bitmap.height) {
                            var x = 0
                            while (x < bitmap.width) {
                                val pixel = bitmap.getPixel(x, y)
                                red += android.graphics.Color.red(pixel)
                                green += android.graphics.Color.green(pixel)
                                blue += android.graphics.Color.blue(pixel)
                                count++
                                x += stepX
                            }
                            y += stepY
                        }
                        if (count > 0) {
                            _accent.value = Color(
                                red = ((red / count) / 255f).boost(),
                                green = ((green / count) / 255f).boost(),
                                blue = ((blue / count) / 255f).boost()
                            )
                        }
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
        }
    }

    private fun Float.boost(): Float {
        val lifted = (this * 1.18f + 0.08f).coerceIn(0.18f, 1f)
        return (lifted * 255).roundToInt() / 255f
    }

    private fun sampleSizeForMaxSide(width: Int, height: Int, maxSidePx: Int): Int {
        var inSampleSize = 1
        val maxDim = maxOf(width, height).coerceAtLeast(1)
        while (maxDim / inSampleSize > maxSidePx) {
            inSampleSize *= 2
        }
        return inSampleSize.coerceAtLeast(1)
    }
}
