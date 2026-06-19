package com.foxymusic

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.random.Random

data class FoxyRecognitionResult(
    val trackId: String,
    val title: String,
    val artist: String,
    val album: String? = null,
    val coverArtUrl: String? = null,
    val coverArtHqUrl: String? = null,
    val genre: String? = null,
    val releaseDate: String? = null,
    val label: String? = null,
    val lyrics: List<String> = emptyList(),
    val shazamUrl: String? = null,
    val appleMusicUrl: String? = null,
    val spotifyUrl: String? = null,
    val isrc: String? = null,
    val youtubeVideoId: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "trackId" to trackId,
        "title" to title,
        "artist" to artist,
        "album" to album,
        "coverArtUrl" to coverArtUrl,
        "coverArtHqUrl" to coverArtHqUrl,
        "genre" to genre,
        "releaseDate" to releaseDate,
        "label" to label,
        "lyrics" to lyrics,
        "shazamUrl" to shazamUrl,
        "appleMusicUrl" to appleMusicUrl,
        "spotifyUrl" to spotifyUrl,
        "isrc" to isrc,
        "youtubeVideoId" to youtubeVideoId,
    )
}

sealed class FoxyRecognitionStatus {
    data object Ready : FoxyRecognitionStatus()
    data object Listening : FoxyRecognitionStatus()
    data object Processing : FoxyRecognitionStatus()
    data class Success(val result: FoxyRecognitionResult) : FoxyRecognitionStatus()
    data class NoMatch(val message: String = "No matches found") : FoxyRecognitionStatus()
    data class Error(val message: String) : FoxyRecognitionStatus()

    fun toMap(): Map<String, Any?> = when (this) {
        Ready -> mapOf("state" to "ready")
        Listening -> mapOf("state" to "listening")
        Processing -> mapOf("state" to "processing")
        is Success -> mapOf("state" to "success", "result" to result.toMap())
        is NoMatch -> mapOf("state" to "noMatch", "message" to message)
        is Error -> mapOf("state" to "error", "message" to message)
    }
}

object FoxyRecognition {
    private const val RECORDING_SAMPLE_RATE = 44_100
    private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
    private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    private const val RECORDING_DURATION_MS = 12_000L
    private const val MIN_REQUEST_INTERVAL_MS = 1_000L
    private const val CACHE_DURATION_MS = 5 * 60 * 1000L
    private const val MAX_RETRIES = 3
    private const val INITIAL_RETRY_DELAY_MS = 1_500L

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val requestMutex = Mutex()
    private val resultCache = ConcurrentHashMap<String, Pair<Long, FoxyRecognitionResult>>()
    private val client = OkHttpClient.Builder().build()
    private var activeJob: Job? = null
    private var lastRequestAt = 0L

    private val _state = MutableStateFlow<FoxyRecognitionStatus>(FoxyRecognitionStatus.Ready)
    val state: StateFlow<FoxyRecognitionStatus> = _state.asStateFlow()

    private val userAgents = listOf(
        "Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TQ3A.230805.001)",
        "Dalvik/2.1.0 (Linux; U; Android 12; SM-G991B Build/SP1A.210812.016)",
        "Dalvik/2.1.0 (Linux; U; Android 14; Pixel 8 Pro Build/AP1A.240505.004)",
    )

    private val timezones = listOf(
        "Asia/Kolkata",
        "Europe/London",
        "America/New_York",
        "Asia/Tokyo",
    )

    fun hasRecordPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    fun start(context: Context) {
        if (activeJob?.isActive == true) return
        if (!hasRecordPermission(context)) {
            _state.value = FoxyRecognitionStatus.Error("Microphone permission not granted")
            return
        }
        activeJob = scope.launch {
            _state.value = FoxyRecognitionStatus.Listening
            val next = runCatching { recognizeBlocking(context.applicationContext) }
                .fold(
                    onSuccess = { it },
                    onFailure = {
                        FoxyRecognitionStatus.Error(it.message ?: "Recognition failed")
                    },
                )
            _state.value = next
        }
    }

    suspend fun stop() {
        activeJob?.cancelAndJoin()
        activeJob = null
        _state.value = FoxyRecognitionStatus.Ready
    }

    fun reset() {
        activeJob?.cancel()
        activeJob = null
        _state.value = FoxyRecognitionStatus.Ready
    }

    @SuppressLint("MissingPermission")
    private suspend fun recognizeBlocking(context: Context): FoxyRecognitionStatus =
        withContext(Dispatchers.IO) {
            val audioData = recordAudio()
            _state.value = FoxyRecognitionStatus.Processing

            val resampled = AudioResampler.resample(
                decodedAudio = DecodedAudio(
                    data = audioData,
                    channelCount = 1,
                    sampleRate = RECORDING_SAMPLE_RATE,
                    pcmEncoding = AUDIO_FORMAT,
                ),
                outputSampleRate = VibraSignature.REQUIRED_SAMPLE_RATE,
            ).getOrElse {
                return@withContext FoxyRecognitionStatus.Error(
                    "Failed to resample audio: ${it.message}",
                )
            }

            require(
                resampled.channelCount == 1 &&
                    resampled.sampleRate == VibraSignature.REQUIRED_SAMPLE_RATE &&
                    resampled.pcmEncoding == AudioFormat.ENCODING_PCM_16BIT &&
                    ByteOrder.nativeOrder() == ByteOrder.LITTLE_ENDIAN &&
                    resampled.data.isNotEmpty() &&
                    resampled.data.size % 2 == 0,
            ) { "Invalid audio format for fingerprint generation" }

            val signature = try {
                VibraSignature.fromI16(resampled.data)
            } catch (e: Exception) {
                return@withContext FoxyRecognitionStatus.Error(
                    "Failed to generate fingerprint: ${e.message}",
                )
            }

            val sampleDurationMs =
                (resampled.data.size / 2) * 1000L / VibraSignature.REQUIRED_SAMPLE_RATE
            val cacheKey = signature.hashCode().toString()
            cachedResult(cacheKey)?.let {
                return@withContext FoxyRecognitionStatus.Success(it)
            }

            val result = runCatching {
                performRecognitionWithRetry(signature, sampleDurationMs)
            }.fold(
                onSuccess = { FoxyRecognitionStatus.Success(it) },
                onFailure = { e ->
                    val message = e.message ?: "Recognition failed"
                    if (message.contains("No match", ignoreCase = true)) {
                        FoxyRecognitionStatus.NoMatch(
                            "No matches found. Try again with clearer audio.",
                        )
                    } else {
                        FoxyRecognitionStatus.Error(message)
                    }
                },
            )
            if (result is FoxyRecognitionStatus.Success) {
                resultCache[cacheKey] = System.currentTimeMillis() to result.result
                FoxyRecognitionHistory.add(result.result)
            }
            return@withContext result
        }

    private suspend fun performRecognitionWithRetry(
        signature: String,
        sampleDurationMs: Long,
    ): FoxyRecognitionResult {
        var lastError: Exception? = null
        repeat(MAX_RETRIES) { attempt ->
            try {
                enforceRateLimit()
                return performRecognition(signature, sampleDurationMs)
            } catch (e: Exception) {
                lastError = e
                if (attempt < MAX_RETRIES - 1) {
                    delay(INITIAL_RETRY_DELAY_MS * (1 shl attempt))
                }
            }
        }
        throw lastError ?: IllegalStateException("Recognition failed")
    }

    private suspend fun performRecognition(
        signature: String,
        sampleDurationMs: Long,
    ): FoxyRecognitionResult = withContext(Dispatchers.IO) {
        val timestamp = System.currentTimeMillis() / 1000
        val uuid1 = UUID.randomUUID().toString().uppercase()
        val uuid2 = UUID.randomUUID().toString()
        val body = JSONObject().apply {
            put(
                "geolocation",
                JSONObject().apply {
                    put("altitude", Random.nextDouble() * 400 + 100)
                    put("latitude", Random.nextDouble() * 180 - 90)
                    put("longitude", Random.nextDouble() * 360 - 180)
                },
            )
            put(
                "signature",
                JSONObject().apply {
                    put("samplems", sampleDurationMs)
                    put("timestamp", timestamp)
                    put("uri", signature)
                },
            )
            put("timestamp", timestamp)
            put("timezone", timezones.random())
        }
        val request = Request.Builder()
            .url(
                "https://amp.shazam.com/discovery/v5/en/US/android/-/tag/$uuid1/$uuid2" +
                    "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3&sharehub=true&video=v3",
            )
            .header("User-Agent", userAgents.random())
            .header("Content-Language", "en_US")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                when (response.code) {
                    404 -> throw IllegalStateException("No match found")
                    429 -> throw IllegalStateException("Too many requests")
                    in 500..599 -> throw IllegalStateException(
                        "Shazam service temporarily unavailable",
                    )
                    else -> throw IllegalStateException(
                        "Recognition failed (error ${response.code})",
                    )
                }
            }
            val root = JSONObject(response.body?.string().orEmpty())
            parseRecognitionResult(root)
                ?: throw IllegalStateException("No match found")
        }
    }

    private fun parseRecognitionResult(root: JSONObject): FoxyRecognitionResult? {
        val track = root.optJSONObject("track") ?: return null
        val sections = track.optJSONArray("sections")
        var album: String? = null
        var label: String? = null
        var releaseDate: String? = null
        val lyrics = ArrayList<String>()
        var youtubeVideoId: String? = null

        for (i in 0 until (sections?.length() ?: 0)) {
            val section = sections?.optJSONObject(i) ?: continue
            when (section.optString("type")) {
                "SONG" -> {
                    val metadata = section.optJSONArray("metadata")
                    for (j in 0 until (metadata?.length() ?: 0)) {
                        val item = metadata?.optJSONObject(j) ?: continue
                        when (item.optString("title")) {
                            "Album" -> album = item.optString("text").ifBlank { null }
                            "Label" -> label = item.optString("text").ifBlank { null }
                            "Released" -> {
                                releaseDate = item.optString("text").ifBlank { null }
                            }
                        }
                    }
                }
                "LYRICS" -> {
                    val lines = section.optJSONArray("text")
                    for (j in 0 until (lines?.length() ?: 0)) {
                        val line = lines?.optString(j).orEmpty().trim()
                        if (line.isNotEmpty()) lyrics.add(line)
                    }
                }
            }
        }

        val hub = track.optJSONObject("hub")
        val appleMusicUrl = hub?.optJSONArray("options").findProviderActionUri("apple")
        val spotifyUrl = hub?.optJSONArray("providers").findProviderActionUri("spotify")
        youtubeVideoId = hub?.optJSONArray("options").findYoutubeVideoId()

        val images = track.optJSONObject("images")
        val coverArtUrl = images?.optString("coverart")?.trim().orEmpty().ifBlank { null }
        val coverArtHqUrl = images?.optString("coverarthq")?.trim().orEmpty().ifBlank { null }
        val genre = track.optJSONObject("genres")?.optString("primary")?.trim().orEmpty()
            .ifBlank { null }
        return FoxyRecognitionResult(
            trackId = track.optString("key").ifBlank {
                root.optString("tagid").ifBlank { UUID.randomUUID().toString() }
            },
            title = track.optString("title").ifBlank { return null },
            artist = track.optString("subtitle").ifBlank { "Unknown artist" },
            album = album,
            coverArtUrl = coverArtUrl,
            coverArtHqUrl = coverArtHqUrl,
            genre = genre,
            releaseDate = releaseDate,
            label = label,
            lyrics = lyrics.take(8),
            shazamUrl = track.optString("url").ifBlank { null },
            appleMusicUrl = appleMusicUrl,
            spotifyUrl = spotifyUrl,
            isrc = track.optString("isrc").ifBlank { null },
            youtubeVideoId = youtubeVideoId,
        )
    }

    private fun JSONObject?.optString(key: String): String? {
        val value = this?.optString(key).orEmpty().trim()
        return value.ifBlank { null }
    }

    private fun org.json.JSONArray?.findProviderActionUri(providerNeedle: String): String? {
        if (this == null) return null
        for (i in 0 until length()) {
            val item = optJSONObject(i) ?: continue
            val providerName = item.optString("providername")
            val caption = item.optString("caption")
            if (
                providerName.contains(providerNeedle, ignoreCase = true) ||
                    caption.contains(providerNeedle, ignoreCase = true)
            ) {
                val actions = item.optJSONArray("actions")
                for (j in 0 until (actions?.length() ?: 0)) {
                    val uri = actions?.optJSONObject(j)?.optString("uri").orEmpty().trim()
                    if (uri.isNotEmpty()) return uri
                }
            }
        }
        return null
    }

    private fun org.json.JSONArray?.findYoutubeVideoId(): String? {
        if (this == null) return null
        for (i in 0 until length()) {
            val item = optJSONObject(i) ?: continue
            if (!item.optString("type").contains("video", ignoreCase = true)) continue
            val actions = item.optJSONArray("actions")
            for (j in 0 until (actions?.length() ?: 0)) {
                val uri = actions?.optJSONObject(j)?.optString("uri").orEmpty().trim()
                if (uri.isEmpty()) continue
                val fromQuery = uri.substringAfter("v=", "").substringBefore('&')
                if (fromQuery.length == 11) return fromQuery
                val fromTail = uri.substringAfterLast('/')
                if (fromTail.length == 11) return fromTail
            }
        }
        return null
    }

    private suspend fun enforceRateLimit() {
        requestMutex.withLock {
            val now = System.currentTimeMillis()
            val waitMs = MIN_REQUEST_INTERVAL_MS - (now - lastRequestAt)
            if (waitMs > 0) delay(waitMs)
            lastRequestAt = System.currentTimeMillis()
        }
    }

    private fun cachedResult(cacheKey: String): FoxyRecognitionResult? {
        val cached = resultCache[cacheKey] ?: return null
        if (System.currentTimeMillis() - cached.first > CACHE_DURATION_MS) {
            resultCache.remove(cacheKey)
            return null
        }
        return cached.second
    }

    @SuppressLint("MissingPermission")
    private suspend fun recordAudio(): ByteArray = withContext(Dispatchers.IO) {
        val minBuffer = AudioRecord.getMinBufferSize(
            RECORDING_SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
        )
        val bufferSize = maxOf(minBuffer, 4096)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            RECORDING_SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize,
        )
        val buffer = ByteArray(bufferSize)
        val out = ByteArrayOutputStream()
        val startAt = System.currentTimeMillis()
        try {
            recorder.startRecording()
            while (System.currentTimeMillis() - startAt < RECORDING_DURATION_MS && isActive) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read > 0) out.write(buffer, 0, read)
            }
        } finally {
            runCatching { recorder.stop() }
            recorder.release()
        }
        out.toByteArray()
    }
}
