package com.foxymusic

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

object FoxyDynamicTheme {
    private val client = OkHttpClient()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var appContext: Context? = null

    private val _accent = MutableStateFlow<Color?>(null)
    val accent: StateFlow<Color?> = _accent

    /**
     * JPEG written from embedded or fetched artwork so Flutter can show mini-player / NP art
     * offline for downloaded tracks (see [com.foxymusic.FoxyFlutterBridge]).
     */
    private val _offlineArtworkPath = MutableStateFlow<String?>(null)
    val offlineArtworkPath: StateFlow<String?> = _offlineArtworkPath.asStateFlow()

    /**
     * Increments whenever artwork accent is recomputed so Flutter can refresh theme even if the
     * new [Color] equals the previous one (StateFlow would otherwise skip an emission).
     */
    private val _paletteEpoch = MutableStateFlow(0)
    val paletteEpoch: StateFlow<Int> = _paletteEpoch.asStateFlow()

    fun bindContext(context: Context) {
        appContext = context.applicationContext
    }

    private fun bumpPaletteEpoch() {
        _paletteEpoch.value = _paletteEpoch.value + 1
    }

    fun clearAccent() {
        _accent.value = null
        _offlineArtworkPath.value = null
        bumpPaletteEpoch()
    }

    fun updateFromSong(song: Song) {
        scope.launch {
            runCatching {
                withContext(Dispatchers.Main.immediate) {
                    _offlineArtworkPath.value = null
                    bumpPaletteEpoch()
                }
                val ctx = appContext
                val localFile = song.localPath?.trim()?.takeIf { it.isNotEmpty() }?.let { File(it) }
                    ?.takeIf { it.isFile && it.length() > 0L }

                val bitmap: Bitmap? = when {
                    localFile != null -> decodeEmbeddedAlbumArt(localFile)
                        ?: decodeBitmapFromHttp(song.bestArtworkUrl())
                    else -> decodeBitmapFromHttp(song.bestArtworkUrl())
                        ?: decodeBitmapFromFileUri(song.bestArtworkUrl())
                }

                if (bitmap == null) {
                    withContext(Dispatchers.Main.immediate) {
                        if (stillCurrentSong(song.videoId)) {
                            _accent.value = null
                            bumpPaletteEpoch()
                        }
                    }
                    return@launch
                }

                val square = centerSquareBitmap(bitmap)
                try {
                    val color = dominantColorFrom(square)
                    withContext(Dispatchers.Main.immediate) {
                        if (stillCurrentSong(song.videoId)) {
                            _accent.value = color
                            bumpPaletteEpoch()
                        }
                    }
                    if (ctx != null && song.isDownloaded && song.videoId.isNotBlank()) {
                        runCatching {
                            val dir = File(ctx.cacheDir, "foxy_player_art").apply { mkdirs() }
                            val out = File(dir, "${song.videoId}.jpg")
                            val thumb = scaleBitmapMaxSide(square, 512)
                            FileOutputStream(out).use { fos ->
                                thumb.compress(Bitmap.CompressFormat.JPEG, 88, fos)
                            }
                            if (thumb !== square) {
                                thumb.recycle()
                            }
                            withContext(Dispatchers.Main.immediate) {
                                if (stillCurrentSong(song.videoId)) {
                                    _offlineArtworkPath.value = out.absolutePath
                                    bumpPaletteEpoch()
                                }
                            }
                        }
                    }
                } finally {
                    square.recycle()
                    if (square !== bitmap) {
                        bitmap.recycle()
                    }
                }
            }
        }
    }

    private fun stillCurrentSong(videoId: String): Boolean {
        val cur = MusicPlayer.state.value.currentSong ?: return false
        return cur.videoId == videoId
    }

    private fun decodeEmbeddedAlbumArt(file: File): Bitmap? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(file.absolutePath)
            val pic = r.embeddedPicture ?: return null
            BitmapFactory.decodeByteArray(pic, 0, pic.size)
        } catch (_: Exception) {
            null
        } finally {
            runCatching { r.release() }
        }
    }

    private fun decodeBitmapFromHttp(url: String): Bitmap? {
        val u = url.trim()
        if (!u.startsWith("http", ignoreCase = true)) return null
        return runCatching {
            val request = Request.Builder().url(u).build()
            client.newCall(request).execute().use { response ->
                val bytes = response.body?.bytes() ?: return@use null
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    return@use null
                }
                val opts = BitmapFactory.Options().apply {
                    inSampleSize = sampleSizeForMaxSide(bounds.outWidth, bounds.outHeight, 160)
                    inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
                }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            }
        }.getOrNull()
    }

    private fun decodeBitmapFromFileUri(url: String): Bitmap? {
        val u = url.trim()
        if (!u.startsWith("file:", ignoreCase = true)) return null
        val path = runCatching { Uri.parse(u).path }.getOrNull().orEmpty()
        if (path.isBlank()) return null
        val f = File(path)
        if (!f.isFile || f.length() <= 0L) return null
        return BitmapFactory.decodeFile(f.absolutePath)
    }

    private fun dominantColorFrom(bitmap: Bitmap): Color {
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
        check(count > 0)
        return Color(
            red = ((red / count) / 255f).boost(),
            green = ((green / count) / 255f).boost(),
            blue = ((blue / count) / 255f).boost()
        )
    }

    private fun Float.boost(): Float {
        val lifted = (this * 1.18f + 0.08f).coerceIn(0.18f, 1f)
        return (lifted * 255).roundToInt() / 255f
    }

    /** Center-crop to square so Flutter mini-player art is not stretched. */
    private fun centerSquareBitmap(source: Bitmap): Bitmap {
        val side = minOf(source.width, source.height).coerceAtLeast(1)
        if (source.width == side && source.height == side) return source
        val x = ((source.width - side) / 2).coerceAtLeast(0)
        val y = ((source.height - side) / 2).coerceAtLeast(0)
        return Bitmap.createBitmap(source, x, y, side, side)
    }

    private fun scaleBitmapMaxSide(source: Bitmap, maxSidePx: Int): Bitmap {
        val maxDim = maxOf(source.width, source.height)
        if (maxDim <= maxSidePx) return source
        val scale = maxSidePx.toFloat() / maxDim.toFloat()
        val w = (source.width * scale).roundToInt().coerceAtLeast(1)
        val h = (source.height * scale).roundToInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, w, h, true)
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
