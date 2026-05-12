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

    fun updateFromSong(song: Song) {
        val artworkUrl = song.bestArtworkUrl()
        if (artworkUrl.isBlank()) return
        scope.launch {
            runCatching {
                val request = Request.Builder().url(artworkUrl).build()
                client.newCall(request).execute().use { response ->
                    val bytes = response.body?.bytes() ?: return@use
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@use
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
                }
            }
        }
    }

    private fun Float.boost(): Float {
        val lifted = (this * 1.18f + 0.08f).coerceIn(0.18f, 1f)
        return (lifted * 255).roundToInt() / 255f
    }
}
