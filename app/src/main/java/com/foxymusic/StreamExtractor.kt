package com.foxymusic

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import android.util.Log
import okhttp3.Call
import okhttp3.Callback
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.CancellableCall
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request as NewPipeRequest
import org.schabi.newpipe.extractor.downloader.Response as NewPipeResponse
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.LinkedHashMap
import java.net.URLDecoder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

data class StreamResult(
    val url: String?,
    val error: String? = null,
    val source: String? = null,
    val bitrate: Int? = null,
    val codec: String? = null,
    val mimeType: String? = null,
    val sampleRate: Int? = null,
    val itag: Int? = null,
    val qualityLabel: String? = null,
)

private data class StreamFormat(
    val url: String,
    val bitrate: Int,
    val codec: String,
    val mimeType: String,
    val sampleRate: Int?,
    val itag: Int,
    val channelCount: Int?,
)

private data class QualityPreference(
    val maxBitrate: Int? = null,
    val targetBitrate: Int? = null,
)

private data class YouTubeClient(
    val name: String,
    val version: String,
    val apiKey: String,
    val userAgent: String,
    val clientNameHeader: String,
    val referer: String = "https://www.youtube.com/watch?v=",
    val origin: String = "https://www.youtube.com",
    val extra: JSONObject = JSONObject(),
    val thirdPartyEmbedUrl: String? = null
)

object StreamExtractor {
    private const val TAG = "FoxyStreamExtractor"

    const val STREAM_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

    @Volatile
    private var isNewPipeReady = false

    @Volatile
    private var httpClientSeed: String = ""

    @Volatile
    private var httpClient: OkHttpClient? = null

    private val videoClipResultCache = object : LinkedHashMap<String, StreamResult>(48, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, StreamResult>?): Boolean =
            size > 48
    }

    private fun httpClient(): OkHttpClient {
        val s = FoxySettings.state.value
        val seed = "${s.proxyEnabled}|${s.proxyEndpoint}"
        var c = httpClient
        if (c != null && seed == httpClientSeed) return c
        synchronized(this) {
            c = httpClient
            if (c != null && seed == httpClientSeed) return c
            val nb = OkHttpClient.Builder()
                .retryOnConnectionFailure(true)
                .connectionPool(okhttp3.ConnectionPool(12, 5, TimeUnit.MINUTES))
                .connectTimeout(7, TimeUnit.SECONDS)
                .readTimeout(12, TimeUnit.SECONDS)
            FoxyNetworking.applyProxy(nb)
            val built = nb.build()
            httpClient = built
            httpClientSeed = seed
            return built
        }
    }

    private val clients = listOf(
        YouTubeClient(
            name = "ANDROID_MUSIC",
            version = "8.11.52",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = "com.google.android.apps.youtube.music/8.11.52 (Linux; U; Android 13) gzip",
            clientNameHeader = "21",
            origin = "https://music.youtube.com",
            referer = "https://music.youtube.com/watch?v=",
            extra = JSONObject()
                .put("androidSdkVersion", 33)
                .put("osName", "Android")
                .put("osVersion", "13")
        ),
        YouTubeClient(
            name = "WEB_REMIX",
            version = "1.20260213.01.00",
            apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-KOIS0TpYA",
            userAgent = STREAM_USER_AGENT,
            clientNameHeader = "67",
            origin = "https://music.youtube.com",
            referer = "https://music.youtube.com/watch?v="
        ),
        YouTubeClient(
            name = "ANDROID_VR",
            version = "1.61.48",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12) gzip",
            clientNameHeader = "28",
            extra = JSONObject().put("androidSdkVersion", 32)
        ),
        YouTubeClient(
            name = "TVHTML5",
            version = "7.20260213.00.00",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = "Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15",
            clientNameHeader = "7",
            referer = "https://www.youtube.com/tv",
            extra = JSONObject()
                .put("clientScreen", "WATCH")
                .put("clientFormFactor", "UNKNOWN_FORM_FACTOR")
                .put("deviceMake", "Sony")
                .put("deviceModel", "PlayStation 4")
                .put("osName", "PlayStation 4")
        ),
        YouTubeClient(
            name = "WEB",
            version = "2.20250122.04.00",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
            clientNameHeader = "1"
        ),
        YouTubeClient(
            name = "MWEB",
            version = "2.20250122.04.00",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = STREAM_USER_AGENT,
            clientNameHeader = "2",
            referer = "https://m.youtube.com/watch?v="
        ),
        YouTubeClient(
            name = "ANDROID",
            version = "21.03.38",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = "com.google.android.youtube/21.03.36 (Linux; U; Android 13) gzip",
            clientNameHeader = "3",
            extra = JSONObject()
                .put("androidSdkVersion", 33)
                .put("osName", "Android")
                .put("osVersion", "13")
        ),
        YouTubeClient(
            name = "IOS",
            version = "21.03.1",
            apiKey = "AIzaSyD9--XzkNsjtHz8BebDKMzs4iS2fPU1eF4",
            userAgent = "com.google.ios.youtube/20.03.02 (iPhone16,2; U; CPU iOS 18_2_1 like Mac OS X)",
            clientNameHeader = "5",
            extra = JSONObject()
                .put("deviceModel", "iPhone16,2")
                .put("osName", "iOS")
                .put("osVersion", "18.2.1.22C161")
        ),
        YouTubeClient(
            name = "WEB_EMBEDDED_PLAYER",
            version = "1.20250121.00.00",
            apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            userAgent = STREAM_USER_AGENT,
            clientNameHeader = "56",
            referer = "https://www.youtube.com/embed/",
            extra = JSONObject().put("clientScreen", "EMBED"),
            thirdPartyEmbedUrl = "https://www.youtube.com/embed/"
        )
    )

    fun getStreamUrl(videoId: String): String? = getStreamResult(videoId).url

    fun getStreamResult(videoId: String): StreamResult =
        getStreamResult(videoId, FoxySettings.state.value.streamQualityTier)

    fun getVideoClipResult(
        videoId: String,
        title: String? = null,
        artist: String? = null,
    ): StreamResult =
        getVideoClipResult(videoId, 720, title, artist)

    fun getStreamResult(videoId: String, qualityTier: Int, searchQuery: String? = null): StreamResult {
        val tier = qualityTier.coerceIn(0, 4)
        val sourcePriority = FoxySettings.state.value.streamSourcePriority.coerceIn(0, 2)
        val maxBitrate = maxBitrateForTier(tier)
        val extractorErrors = mutableListOf<String>()
        var lastError: String? = null

        peekCachedStreamResult(videoId, tier, searchQuery)?.let { cached ->
            return cached.copy(source = cached.source ?: "cache")
        }

        val soundCloudRef = soundCloudRef(videoId)
        if (soundCloudRef != null) {
            when (val result = getSoundCloudStreamResult(soundCloudRef, maxBitrate, isUrl = true)) {
                is ExtractorAttempt.Success -> {
                    val stream = result.toStreamResult()
                    StreamUrlCache.put(videoId, tier, stream)
                    return stream
                }
                is ExtractorAttempt.Failure -> extractorErrors += "SoundCloud: ${result.message}"
            }
        }

        if (tier >= 3 && sourcePriority == 2 && !searchQuery.isNullOrBlank()) {
            when (val result = getSoundCloudStreamResult(searchQuery, maxBitrate, isUrl = false)) {
                is ExtractorAttempt.Success -> {
                    val stream = result.toStreamResult()
                    StreamUrlCache.put(videoId, tier, stream)
                    return stream
                }
                is ExtractorAttempt.Failure -> extractorErrors += "SoundCloud: ${result.message}"
            }
        }

        val clientOrder = clientsForTier(tier)
        val parallelCount = if (tier >= 3) 0 else 3.coerceAtMost(clientOrder.size)
        if (parallelCount > 0) {
            val pool = Executors.newFixedThreadPool(parallelCount)
            try {
                val futures = clientOrder.take(parallelCount).map { ytClient ->
                    pool.submit<StreamResult?> {
                        tryInnertubeClient(videoId, ytClient, maxBitrate, tier)
                    }
                }
                for (future in futures) {
                    try {
                        val attempt = future.get(10, TimeUnit.SECONDS)
                        if (attempt?.url != null) {
                            futures.forEach { it.cancel(true) }
                            return cacheAndReturn(
                                videoId,
                                tier,
                                maybeUpgradeUltraWithAlternateSource(
                                    videoId,
                                    tier,
                                    attempt,
                                    searchQuery,
                                    sourcePriority,
                                    maxBitrate,
                                ),
                            )
                        }
                        attempt?.error?.let {
                            lastError = it
                            extractorErrors += it
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Parallel Innertube attempt failed", e)
                    }
                }
            } finally {
                pool.shutdownNow()
            }
        }

        for (ytClient in clientOrder.drop(parallelCount)) {
            val attempt = tryInnertubeClient(videoId, ytClient, maxBitrate, tier)
            if (attempt.url != null) {
                return cacheAndReturn(
                    videoId,
                    tier,
                    maybeUpgradeUltraWithAlternateSource(
                        videoId,
                        tier,
                        attempt,
                        searchQuery,
                        sourcePriority,
                        maxBitrate,
                    ),
                )
            }
            attempt.error?.let {
                lastError = it
                extractorErrors += it
            }
        }

        lastError?.let { if (it !in extractorErrors) extractorErrors += it }
        when (val newPipeResult = getNewPipeStreamResult(videoId, maxBitrate)) {
            is ExtractorAttempt.Success -> {
                val result = newPipeResult.toStreamResult()
                val best = maybeUpgradeUltraWithAlternateSource(
                    videoId,
                    tier,
                    result,
                    searchQuery,
                    sourcePriority,
                    maxBitrate,
                )
                StreamUrlCache.put(videoId, tier, best)
                return best
            }
            is ExtractorAttempt.Failure -> {
                extractorErrors += "NewPipe: ${newPipeResult.message}"
                Log.w(TAG, "NewPipe failed: ${newPipeResult.message}", newPipeResult.throwable)
            }
        }

        if (tier >= 3 && sourcePriority == 1 && !searchQuery.isNullOrBlank()) {
            when (val result = getSoundCloudStreamResult(searchQuery, maxBitrate, isUrl = false)) {
                is ExtractorAttempt.Success -> {
                    val stream = result.toStreamResult()
                    StreamUrlCache.put(videoId, tier, stream)
                    return stream
                }
                is ExtractorAttempt.Failure -> {
                    extractorErrors += "SoundCloud: ${result.message}"
                    Log.w(TAG, "SoundCloud fallback failed: ${result.message}", result.throwable)
                }
            }
        }
        return StreamResult(null, extractorErrors.joinToString("\n").ifBlank { "Could not fetch stream URL" })
    }

    fun getVideoClipResult(
        videoId: String,
        targetHeight: Int,
        title: String? = null,
        artist: String? = null,
    ): StreamResult {
        val maxHeight = targetHeight.coerceIn(240, 1080)
        val cacheKey = listOf(videoId.trim(), maxHeight, title.orEmpty().trim(), artist.orEmpty().trim())
            .joinToString("|")
        synchronized(videoClipResultCache) {
            videoClipResultCache[cacheKey]?.let { return it.copy(source = it.source ?: "clip-cache") }
        }
        val extractorErrors = mutableListOf<String>()
        val clientOrder = clientsForTier(0)
        for (ytClient in clientOrder) {
            val attempt = tryInnertubeVideoClient(videoId, ytClient, maxHeight)
            if (attempt.url != null) {
                synchronized(videoClipResultCache) {
                    videoClipResultCache[cacheKey] = attempt
                }
                return attempt
            }
            attempt.error?.let { extractorErrors += it }
        }

        val relatedSongs = if (title.isNullOrBlank() && artist.isNullOrBlank()) {
            emptyList<Song>()
        } else {
            clipCandidateSongs(title, artist)
        }

        for (candidate in relatedSongs) {
            val candidateId = candidate.videoId.trim()
            if (candidateId.isBlank() || candidateId == videoId) continue
            for (ytClient in clientOrder) {
                val attempt = tryInnertubeVideoClient(candidateId, ytClient, maxHeight)
                if (attempt.url != null) {
                    synchronized(videoClipResultCache) {
                        videoClipResultCache[cacheKey] = attempt
                    }
                    return attempt
                }
                attempt.error?.let { extractorErrors += "Related candidate " + candidateId + ": " + it }
            }
        }

        return StreamResult(
            null,
            extractorErrors.joinToString("\n").ifBlank { "Could not fetch video clip stream" },
        )
    }

    fun peekCachedStreamResult(videoId: String, qualityTier: Int, searchQuery: String? = null): StreamResult? {
        val tier = qualityTier.coerceIn(0, 4)
        val sourcePriority = FoxySettings.state.value.streamSourcePriority.coerceIn(0, 2)
        val cached = StreamUrlCache.peekResult(videoId, tier) ?: return null
        val wantsSoundCloudFirst = tier >= 3 &&
            sourcePriority == 2 &&
            !searchQuery.isNullOrBlank() &&
            cached.source?.contains("SoundCloud", ignoreCase = true) != true
        val youtubeOnlyRejectsSoundCloud = sourcePriority == 0 &&
            cached.source?.contains("SoundCloud", ignoreCase = true) == true
        return if (wantsSoundCloudFirst || youtubeOnlyRejectsSoundCloud) null else cached
    }

    private fun cacheAndReturn(videoId: String, tier: Int, result: StreamResult): StreamResult {
        result.url?.let { StreamUrlCache.put(videoId, tier, result) }
        return result
    }

    private fun maybeUpgradeUltraWithAlternateSource(
        videoId: String,
        tier: Int,
        current: StreamResult,
        searchQuery: String?,
        sourcePriority: Int,
        maxBitrate: Int?,
    ): StreamResult {
        if (tier < 3 || searchQuery.isNullOrBlank()) return current
        if (current.isLosslessLike()) return current
        val alternate = when (val result = getSoundCloudStreamResult(searchQuery, maxBitrate, isUrl = false)) {
            is ExtractorAttempt.Success -> result.toStreamResult()
            is ExtractorAttempt.Failure -> {
                return current
            }
        }
        val alternateWins = alternate.ultraQualityScore() > current.ultraQualityScore()
        if (sourcePriority == 0 && !alternate.isLosslessLike() && !alternateWins) {
            return current
        }
        return if (alternateWins) alternate else current
    }

    private fun tryInnertubeClient(
        videoId: String,
        ytClient: YouTubeClient,
        maxBitrate: Int?,
        qualityTier: Int,
    ): StreamResult {
        return try {
            val executeAttempt = { includeAccountHeaders: Boolean ->
                val body = buildPlayerBody(videoId, ytClient)
                val request = Request.Builder()
                    .url("https://www.youtube.com/youtubei/v1/player?key=${ytClient.apiKey}")
                    .post(body.toString().toRequestBody("application/json".toMediaType()))
                    .addHeader("User-Agent", ytClient.userAgent)
                    .addHeader("Accept", "application/json")
                    .addHeader("Content-Type", "application/json")
                    .addHeader("Origin", ytClient.origin)
                    .addHeader("Referer", "${ytClient.referer}$videoId")
                    .addHeader("X-YouTube-Client-Name", ytClient.clientNameHeader)
                    .addHeader("X-YouTube-Client-Version", ytClient.version)
                    .apply {
                        if (includeAccountHeaders) addFoxyAccountHeaders(ytClient.origin)
                    }
                    .build()

                httpClient().newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        val err = "YouTube player request failed (${response.code})"
                        Log.w(TAG, "${ytClient.name} HTTP failed: ${response.code}")
                        return@use StreamResult(null, error = "${ytClient.name}: $err")
                    }

                    val responseStr = response.body?.string().orEmpty()
                    val json = JSONObject(responseStr)
                    val status = json.optJSONObject("playabilityStatus")
                    val playability = status?.optString("status").orEmpty()

                    if (playability.isNotBlank() && playability != "OK") {
                        val reason = status?.optString("reason").takeUnless { it.isNullOrBlank() }
                            ?.let { "${ytClient.name}: $it" }
                            ?: "${ytClient.name}: This video is not playable"
                        return@use StreamResult(null, error = reason)
                    }

                    val streamingData = json.optJSONObject("streamingData")
                    val stream = streamingData?.let {
                        pickBestPlayableStream(it, maxBitrate, qualityTier)
                    }
                    if (stream != null) {
                        return@use StreamResult(
                            stream.url,
                            source = ytClient.name,
                            bitrate = stream.bitrate.takeIf { it > 0 },
                            codec = stream.codec,
                            mimeType = stream.mimeType,
                            sampleRate = stream.sampleRate,
                            itag = stream.itag.takeIf { it > 0 },
                            qualityLabel = stream.qualityLabel(),
                        )
                    }

                    StreamResult(null, error = "${ytClient.name}: No direct audio stream was returned")
                }
            }

            return executeAttempt(false)
        } catch (e: Exception) {
            val msg = "${ytClient.name}: ${e.message ?: "Could not fetch stream URL"}"
            Log.w(TAG, "Innertube client failed: ${ytClient.name}", e)
            StreamResult(null, error = msg)
        }
    }

    private fun tryInnertubeVideoClient(
        videoId: String,
        ytClient: YouTubeClient,
        maxHeight: Int?,
    ): StreamResult {
        return try {
            val executeAttempt = { includeAccountHeaders: Boolean ->
                val body = buildPlayerBody(videoId, ytClient)
                val request = Request.Builder()
                    .url("https://www.youtube.com/youtubei/v1/player?key=${ytClient.apiKey}")
                    .post(body.toString().toRequestBody("application/json".toMediaType()))
                    .addHeader("User-Agent", ytClient.userAgent)
                    .addHeader("Accept", "application/json")
                    .addHeader("Content-Type", "application/json")
                    .addHeader("Origin", ytClient.origin)
                    .addHeader("Referer", "${ytClient.referer}$videoId")
                    .addHeader("X-YouTube-Client-Name", ytClient.clientNameHeader)
                    .addHeader("X-YouTube-Client-Version", ytClient.version)
                    .apply {
                        if (includeAccountHeaders) addFoxyAccountHeaders(ytClient.origin)
                    }
                    .build()

                httpClient().newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        val err = "YouTube player request failed (${response.code})"
                        Log.w(TAG, "${ytClient.name} video HTTP failed: ${response.code}")
                        return@use StreamResult(null, error = "${ytClient.name}: $err")
                    }

                    val responseStr = response.body?.string().orEmpty()
                    val json = JSONObject(responseStr)
                    val status = json.optJSONObject("playabilityStatus")
                    val playability = status?.optString("status").orEmpty()

                    if (playability.isNotBlank() && playability != "OK") {
                        val reason = status?.optString("reason").takeUnless { it.isNullOrBlank() }
                            ?.let { "${ytClient.name}: $it" }
                            ?: "${ytClient.name}: This video is not playable"
                        return@use StreamResult(null, error = reason)
                    }

                    val streamingData = json.optJSONObject("streamingData")
                    val stream = streamingData?.let { pickBestPlayableVideoStream(it, maxHeight) }
                    if (stream != null) {
                        val height = stream.optInt("height", 0).takeIf { it > 0 }
                        val quality = stream.optString("qualityLabel")
                            .takeIf { it.isNotBlank() }
                            ?: height?.let { "${it}p" }
                        return@use StreamResult(
                            stream.directUrl(),
                            source = ytClient.name,
                            bitrate = stream.optInt("bitrate", 0).takeIf { it > 0 },
                            codec = stream.optString("mimeType"),
                            mimeType = stream.optString("mimeType"),
                            itag = stream.optInt("itag", 0).takeIf { it > 0 },
                            qualityLabel = quality,
                        )
                    }

                    StreamResult(null, error = "${ytClient.name}: No video stream was returned")
                }
            }

            return executeAttempt(false)
        } catch (e: Exception) {
            val msg = "${ytClient.name}: ${e.message ?: "Could not fetch video clip URL"}"
            Log.w(TAG, "Innertube video client failed: ${ytClient.name}", e)
            StreamResult(null, error = msg)
        }
    }

    private fun buildPlayerBody(videoId: String, ytClient: YouTubeClient): JSONObject {
        val clientObj = JSONObject()
            .put("clientName", ytClient.name)
            .put("clientVersion", ytClient.version)
            .put("hl", "en")
            .put("gl", "US")
            .put("utcOffsetMinutes", 0)

        ytClient.extra.keys().forEach { key ->
            clientObj.put(key, ytClient.extra.get(key))
        }

        val body = JSONObject()
            .put("context", JSONObject().put("client", clientObj))
            .put("videoId", videoId)
            .put("contentCheckOk", true)
            .put("racyCheckOk", true)
            .put("playbackContext", JSONObject().put("contentPlaybackContext", JSONObject()))

        ytClient.thirdPartyEmbedUrl?.let { embedUrl ->
            body.getJSONObject("context")
                .put("thirdParty", JSONObject().put("embedUrl", "$embedUrl$videoId"))
        }

        return body
    }

    private fun qualityPreferenceForTier(tier: Int): QualityPreference = when (tier) {
        0 -> QualityPreference(maxBitrate = 96_000, targetBitrate = 48_000)
        1 -> QualityPreference(maxBitrate = 160_000, targetBitrate = 128_000)
        2 -> QualityPreference(maxBitrate = 256_000, targetBitrate = 220_000)
        3 -> QualityPreference(maxBitrate = 360_000, targetBitrate = 320_000)
        else -> QualityPreference(maxBitrate = null, targetBitrate = 1_000_000)
    }

    private fun maxBitrateForTier(tier: Int): Int? = qualityPreferenceForTier(tier).maxBitrate

    private fun clientsForTier(tier: Int): List<YouTubeClient> =
        if (tier >= 3) {
            listOfNotNull(
                clients.find { it.name == "ANDROID_MUSIC" },
                clients.find { it.name == "WEB_REMIX" },
                clients.find { it.name == "ANDROID" },
                clients.find { it.name == "IOS" },
                clients.find { it.name == "WEB" },
                clients.find { it.name == "MWEB" },
                clients.find { it.name == "ANDROID_VR" },
                clients.find { it.name == "TVHTML5" },
                clients.find { it.name == "WEB_EMBEDDED_PLAYER" },
            ).distinctBy { it.name }
        } else {
            clients
        }

    private fun pickBestPlayableStream(
        streamingData: JSONObject,
        maxBitrate: Int?,
        tier: Int,
    ): StreamFormat? {
        val candidates = mutableListOf<JSONObject>()
        streamingData.optJSONArray("adaptiveFormats")?.appendAudioFormatsTo(candidates)
        streamingData.optJSONArray("formats")?.appendAudioFormatsTo(candidates)
        val preference = qualityPreferenceForTier(tier)

        val sorted = candidates
            .sortedWith(
                compareByDescending<JSONObject> {
                    it.optInt("audioChannels", 2).coerceAtLeast(1) >= 2
                }
                    .thenByDescending { it.qualityPreferenceScore(preference, tier) }
                    .thenByDescending { it.codecScore() }
                    .thenByDescending { it.optInt("audioQualityRank") }
                    .thenByDescending { it.optInt("bitrate") }
                    .thenByDescending { it.itagScore() }
            )

        val filtered = if (maxBitrate == null) {
            sorted
        } else {
            sorted.filter { fmt ->
                val br = fmt.optInt("bitrate", 0)
                br == 0 || br <= maxBitrate
            }.ifEmpty { sorted }
        }

        filtered.firstNotNullOfOrNull { fmt ->
            val url = fmt.directUrl() ?: return@firstNotNullOfOrNull null
            StreamFormat(
                url = url,
                bitrate = fmt.optInt("bitrate", 0),
                codec = fmt.codecLabel(),
                mimeType = fmt.optString("mimeType"),
                sampleRate = fmt.optString("audioSampleRate").toIntOrNull(),
                itag = fmt.optInt("itag", 0),
                channelCount = fmt.optInt("audioChannels", 0).takeIf { it > 0 },
            )
        }?.let { return it }

        return streamingData.optString("hlsManifestUrl")
            .takeIf { it.isNotBlank() }
            ?.let {
                StreamFormat(
                    url = it,
                    bitrate = 0,
                    codec = "HLS",
                    mimeType = "application/x-mpegURL",
                    sampleRate = null,
                    itag = 0,
                    channelCount = null,
                )
            }
    }

    private fun JSONObject.qualityPreferenceScore(
        preference: QualityPreference,
        tier: Int,
    ): Int {
        val bitrate = optInt("bitrate", 0)
        if (tier >= 4) {
            val preferredCodecBonus = when {
                optString("mimeType").contains("flac", ignoreCase = true) -> 3_000_000
                optString("mimeType").contains("opus", ignoreCase = true) -> 2_400_000
                optString("mimeType").contains("aac", ignoreCase = true) ||
                    optString("mimeType").contains("mp4a", ignoreCase = true) -> 2_000_000
                else -> 0
            }
            val ultraFloorBonus = if (bitrate >= 320_000) 100_000_000 else 0
            return ultraFloorBonus + preferredCodecBonus + codecScore() * 100_000 + bitrate
        }
        if (bitrate <= 0) return 0
        val target = preference.targetBitrate ?: return bitrate
        return 1_000_000 - kotlin.math.abs(target - bitrate)
    }

    private fun JSONObject.codecScore(): Int {
        val mime = optString("mimeType")
        return when {
            mime.contains("flac", ignoreCase = true) -> 100
            mime.contains("alac", ignoreCase = true) -> 96
            mime.contains("wav", ignoreCase = true) -> 94
            mime.contains("pcm", ignoreCase = true) -> 92
            mime.contains("opus", ignoreCase = true) -> 40
            mime.contains("webm", ignoreCase = true) -> 30
            mime.contains("mp4a", ignoreCase = true) || mime.contains("aac", ignoreCase = true) -> 20
            mime.contains("mp4", ignoreCase = true) || mime.contains("m4a", ignoreCase = true) -> 10
            else -> 0
        }
    }

    private fun JSONObject.itagScore(): Int = when (optInt("itag", 0)) {
        774 -> 60
        251 -> 50
        250 -> 40
        249 -> 30
        140 -> 20
        else -> 0
    }

    private fun JSONObject.codecLabel(): String {
        val mime = optString("mimeType")
        return when {
            mime.contains("flac", ignoreCase = true) -> "FLAC Lossless"
            mime.contains("alac", ignoreCase = true) -> "ALAC Lossless"
            mime.contains("wav", ignoreCase = true) -> "WAV Lossless"
            mime.contains("pcm", ignoreCase = true) -> "PCM Lossless"
            mime.contains("opus", ignoreCase = true) -> "Opus"
            mime.contains("mp4a", ignoreCase = true) || mime.contains("aac", ignoreCase = true) -> "AAC"
            mime.contains("webm", ignoreCase = true) -> "WebM"
            mime.contains("mp4", ignoreCase = true) || mime.contains("m4a", ignoreCase = true) -> "M4A"
            else -> mime.substringBefore(";").ifBlank { "Audio" }
        }
    }

    private fun JSONArray.appendAudioFormatsTo(target: MutableList<JSONObject>) {
        for (index in 0 until length()) {
            val format = optJSONObject(index) ?: continue
            val mimeType = format.optString("mimeType")
            val hasAudio = mimeType.startsWith("audio/") || format.has("audioQuality")
            if (hasAudio) {
                val rank = when (format.optString("audioQuality")) {
                    "AUDIO_QUALITY_HI_RES_LOSSLESS" -> 6
                    "AUDIO_QUALITY_LOSSLESS" -> 5
                    "AUDIO_QUALITY_HIGH" -> 3
                    "AUDIO_QUALITY_MEDIUM" -> 2
                    "AUDIO_QUALITY_LOW" -> 1
                    else -> 0
                }
                format.put("audioQualityRank", rank)
                target.add(format)
            }
        }
    }

    private fun JSONArray.appendVideoFormatsTo(target: MutableList<JSONObject>) {
        for (index in 0 until length()) {
            val format = optJSONObject(index) ?: continue
            val mimeType = format.optString("mimeType")
            val hasVideo = mimeType.startsWith("video/") || format.optInt("height", 0) > 0
            if (!hasVideo) continue
            if (mimeType.startsWith("audio/")) continue
            target.add(format)
        }
    }

    private fun pickBestPlayableVideoStream(
        streamingData: JSONObject,
        maxHeight: Int?,
    ): JSONObject? {
        val candidates = mutableListOf<JSONObject>()
        streamingData.optJSONArray("formats")?.appendVideoFormatsTo(candidates)
        streamingData.optJSONArray("adaptiveFormats")?.appendVideoFormatsTo(candidates)
        if (candidates.isEmpty()) return null
        val target = maxHeight ?: 720
        val filtered = maxHeight?.let { limit ->
            candidates.filter { fmt ->
                val h = fmt.optInt("height", 0)
                h == 0 || h <= limit
            }.ifEmpty { candidates }
        } ?: candidates
        val ordered = filtered.sortedWith(
            compareBy<JSONObject>(
                { fmt ->
                    val h = fmt.optInt("height", 0).takeIf { it > 0 } ?: Int.MAX_VALUE
                    kotlin.math.abs(target - h)
                },
                { -it.optInt("height", 0) },
                { -it.optInt("bitrate", 0) },
                { -it.optInt("fps", 0) },
            )
        )
        return ordered.firstOrNull { it.directUrl() != null }
    }

    private fun JSONObject.directUrl(): String? {
        optString("url").takeIf { it.isNotBlank() }?.let { return it }

        val cipher = optString("signatureCipher").ifBlank { optString("cipher") }
        if (cipher.isBlank()) return null

        val parts = cipher.split("&")
            .mapNotNull {
                val splitAt = it.indexOf("=")
                if (splitAt <= 0) null else {
                    val key = URLDecoder.decode(it.substring(0, splitAt), "UTF-8")
                    val value = URLDecoder.decode(it.substring(splitAt + 1), "UTF-8")
                    key to value
                }
            }
            .toMap()

        val url = parts["url"].orEmpty()
        val signature = parts["sig"] ?: parts["signature"]
        val signatureParam = parts["sp"] ?: "signature"

        return when {
            url.isBlank() -> null
            signature.isNullOrBlank() -> url
            parts["s"].isNullOrBlank() -> "$url&$signatureParam=$signature"
            else -> null
        }
    }

    private fun getSoundCloudStreamResult(
        queryOrUrl: String,
        maxBitrate: Int?,
        isUrl: Boolean,
    ): ExtractorAttempt {
        return try {
            ensureNewPipe()
            val service = ServiceList.SoundCloud
            val streamUrl = if (isUrl) {
                queryOrUrl
            } else {
                val searchInfo = SearchInfo.getInfo(service, service.searchQHFactory.fromQuery(queryOrUrl))
                val candidate = searchInfo.relatedItems
                    .filterIsInstance<StreamInfoItem>()
                    .maxByOrNull { soundCloudMatchScore(queryOrUrl, it) }
                    ?: return ExtractorAttempt.Failure("No SoundCloud result for $queryOrUrl")
                val score = soundCloudMatchScore(queryOrUrl, candidate)
                if (score < 0.28) {
                    return ExtractorAttempt.Failure("No close SoundCloud match for $queryOrUrl")
                }
                candidate.url
            }
            getNewPipeServiceStreamResult(service, streamUrl, maxBitrate, "SoundCloud")
        } catch (e: Exception) {
            ExtractorAttempt.Failure("${e::class.java.simpleName}: ${e.message}", e)
        }
    }

    private fun getNewPipeStreamResult(videoId: String, maxBitrate: Int?): ExtractorAttempt =
        getNewPipeServiceStreamResult(
            ServiceList.YouTube,
            "https://www.youtube.com/watch?v=$videoId",
            maxBitrate,
            "NewPipe",
        )

    private fun getNewPipeServiceStreamResult(
        service: org.schabi.newpipe.extractor.StreamingService,
        url: String,
        maxBitrate: Int?,
        source: String,
    ): ExtractorAttempt {
        return try {
            ensureNewPipe()
            val streamInfo = StreamInfo.getInfo(
                service,
                url
            )

            val candidates = streamInfo.audioStreams.filter { !it.content.isNullOrBlank() }
            val filtered = if (maxBitrate == null) {
                candidates
            } else {
                candidates.filter { stream ->
                    val br = stream.averageBitrate ?: 0
                    br == 0 || br <= maxBitrate
                }.ifEmpty { candidates }
            }

            val audioStream = filtered.maxWithOrNull(
                compareBy(
                    { stream -> newPipeCodecScore(stream.format?.name) },
                    { stream -> stream.averageBitrate ?: 0 },
                )
            )

            val url = audioStream?.content
            if (url.isNullOrBlank()) {
                ExtractorAttempt.Failure(
                    "No audio streams. audio=${streamInfo.audioStreams.size}, video=${streamInfo.videoStreams.size}"
                )
            } else {
                ExtractorAttempt.Success(
                    url,
                    bitrate = audioStream.averageBitrate?.let { it * 1000 },
                    codec = audioStream.format?.name,
                    source = source,
                    qualityLabel = qualityLabel(
                        audioStream.format?.name,
                        audioStream.averageBitrate?.let { it * 1000 },
                    ),
                )
            }
        } catch (e: Exception) {
            ExtractorAttempt.Failure("${e::class.java.simpleName}: ${e.message}", e)
        }
    }

    private fun soundCloudRef(ref: String): String? {
        val trimmed = ref.trim()
        if (trimmed.startsWith("https://soundcloud.com/", ignoreCase = true)) return trimmed
        if (trimmed.startsWith("http://soundcloud.com/", ignoreCase = true)) return trimmed
        return null
    }

    private fun soundCloudMatchScore(query: String, item: StreamInfoItem): Double {
        val target = "${item.name} ${item.uploaderName}".normalizedSearchTokens()
        val source = query.normalizedSearchTokens()
        if (source.isEmpty() || target.isEmpty()) return 0.0
        val hits = source.count { it in target }
        val coverage = hits.toDouble() / source.size.toDouble()
        val titleBonus = if (item.name.normalizedSearchText() in query.normalizedSearchText() ||
            query.normalizedSearchText() in item.name.normalizedSearchText()
        ) {
            0.18
        } else {
            0.0
        }
        return coverage + titleBonus
    }

    private fun clipCandidateSongs(title: String?, artist: String?): List<Song> {
        val queries = clipSearchQueries(title, artist)
        if (queries.isEmpty()) return emptyList()

        val deduped = linkedMapOf<String, Song>()
        for (query in queries) {
            val batch = runCatching {
                runBlocking(Dispatchers.IO) {
                    YTMusicApi.videos(query).take(12)
                }
            }.getOrDefault(emptyList())
            for (song in batch) {
                val id = song.videoId.trim()
                if (id.isBlank()) continue
                deduped.putIfAbsent(id, song)
            }
        }

        return deduped.values
            .sortedByDescending { clipCandidateScore(it, title, artist) }
            .take(8)
    }

    private fun clipSearchQueries(title: String?, artist: String?): List<String> {
        val cleanTitle = title.orEmpty().trim()
        val cleanArtist = artist.orEmpty().trim()
        val queries = linkedSetOf<String>()

        fun add(query: String?) {
            val q = query.orEmpty().trim()
            if (q.isNotBlank()) queries += q
        }

        add(listOf(cleanTitle, cleanArtist).filter { it.isNotBlank() }.joinToString(" "))
        add(cleanTitle)
        add(cleanArtist)
        add("$cleanTitle official video")
        add("$cleanTitle official music video")
        add("$cleanTitle music video")
        add("$cleanTitle audio")
        add("$cleanArtist $cleanTitle")

        return queries.toList()
    }

    private fun clipCandidateScore(song: Song, title: String?, artist: String?): Double {
        val queryTitle = title.orEmpty().normalizedSearchText()
        val queryArtist = artist.orEmpty().normalizedSearchText()
        val candidateTitle = song.title.normalizedSearchText()
        val candidateArtist = song.artist.normalizedSearchText()
        val queryTokens = listOf(queryTitle, queryArtist)
            .joinToString(" ")
            .normalizedSearchTokens()
        val candidateTokens = "$candidateTitle $candidateArtist".normalizedSearchTokens()
        if (candidateTokens.isEmpty()) return 0.0

        val hits = queryTokens.count { it in candidateTokens }
        var score = if (queryTokens.isEmpty()) 0.0 else hits.toDouble() / queryTokens.size.toDouble()

        if (queryTitle.isNotBlank() && (
                candidateTitle.contains(queryTitle) ||
                    queryTitle.contains(candidateTitle)
                )
        ) {
            score += 0.30
        }
        if (queryArtist.isNotBlank() && (
                candidateArtist.contains(queryArtist) ||
                    queryArtist.contains(candidateArtist)
                )
        ) {
            score += 0.20
        }

        val bestTitle = "$candidateTitle $candidateArtist"
        score -= clipCandidatePenalty(bestTitle)
        if (candidateTitle.contains("official", ignoreCase = true)) {
            score += 0.08
        }
        if (candidateTitle.contains("video", ignoreCase = true)) {
            score += 0.04
        }

        return score
    }

    private fun clipCandidatePenalty(text: String): Double {
        val lowered = text.lowercase()
        val badTerms = listOf(
            "lyrics",
            "lyric",
            "cover",
            "live",
            "instrumental",
            "slowed",
            "speed up",
            "sped up",
            "nightcore",
            "remix",
            "edit",
            "reverb",
            "8d",
            "karaoke",
            "reaction",
            "tutorial",
        )
        val hits = badTerms.count { lowered.contains(it) }
        return when {
            hits <= 0 -> 0.0
            hits == 1 -> 0.25
            hits == 2 -> 0.45
            else -> 0.65
        }
    }

    private fun ExtractorAttempt.Success.toStreamResult(): StreamResult =
        StreamResult(
            url,
            source = source,
            bitrate = bitrate,
            codec = codec,
            qualityLabel = qualityLabel ?: qualityLabel(codec, bitrate),
        )

    private fun StreamFormat.qualityLabel(): String? = qualityLabel(codec, bitrate)

    private fun StreamResult.isLosslessLike(): Boolean =
        losslessCodecScore(codec ?: mimeType ?: qualityLabel) >= 90

    private fun StreamResult.ultraQualityScore(): Int {
        val codecPart = losslessCodecScore(codec ?: mimeType ?: qualityLabel)
            .takeIf { it > 0 }
            ?: lossyCodecScore(codec ?: mimeType ?: qualityLabel)
        return codecPart * 1_000_000 + (bitrate ?: 0)
    }

    private fun newPipeCodecScore(name: String?): Int =
        losslessCodecScore(name).takeIf { it > 0 } ?: lossyCodecScore(name)

    private fun losslessCodecScore(name: String?): Int {
        val s = name.orEmpty()
        return when {
            s.contains("flac", ignoreCase = true) -> 100
            s.contains("alac", ignoreCase = true) -> 96
            s.contains("wav", ignoreCase = true) -> 94
            s.contains("pcm", ignoreCase = true) -> 92
            else -> 0
        }
    }

    private fun lossyCodecScore(name: String?): Int {
        val s = name.orEmpty()
        return when {
            s.contains("opus", ignoreCase = true) -> 40
            s.contains("webm", ignoreCase = true) -> 30
            s.contains("aac", ignoreCase = true) || s.contains("mp4a", ignoreCase = true) -> 20
            s.contains("m4a", ignoreCase = true) || s.contains("mp4", ignoreCase = true) -> 10
            else -> 0
        }
    }

    private fun qualityLabel(codec: String?, bitrate: Int?): String? {
        val c = codec.orEmpty()
        val base = when {
            c.contains("flac", ignoreCase = true) -> "FLAC Lossless"
            c.contains("alac", ignoreCase = true) -> "ALAC Lossless"
            c.contains("wav", ignoreCase = true) -> "WAV Lossless"
            c.contains("pcm", ignoreCase = true) -> "PCM Lossless"
            c.isNotBlank() -> c
            else -> return null
        }
        return bitrate?.takeIf { it > 0 }?.let { "$base ${(it / 1000)} kbps" } ?: base
    }

    private fun ensureNewPipe() {
        if (isNewPipeReady) return
        synchronized(this) {
            if (!isNewPipeReady) {
                YoutubeParsingHelper.setConsentAccepted(true)
                NewPipe.init(FoxyNewPipeDownloader(httpClient()))
                isNewPipeReady = true
            }
        }
    }

    private fun Request.Builder.addFoxyAccountHeaders(origin: String): Request.Builder {
        val account = FoxyAccount.state.value
        if (account.cookie.isBlank()) return this
        addHeader("Cookie", account.cookie)
        addHeader("X-Origin", origin)
        account.cookie.sapisidHashHeader(origin)?.let { addHeader("Authorization", it) }
        return this
    }
}

private sealed class ExtractorAttempt {
    data class Success(
        val url: String,
        val bitrate: Int?,
        val codec: String?,
        val source: String = "NewPipe",
        val qualityLabel: String? = null,
    ) : ExtractorAttempt()
    data class Failure(val message: String, val throwable: Throwable? = null) : ExtractorAttempt()
}

private fun String.normalizedSearchText(): String =
    lowercase()
        .replace(Regex("""\([^)]*\)|\[[^]]*]"""), " ")
        .replace(Regex("""[^a-z0-9]+"""), " ")
        .trim()

private fun String.normalizedSearchTokens(): Set<String> =
    normalizedSearchText()
        .split(Regex("""\s+"""))
        .filter { it.length >= 2 && it !in setOf("official", "audio", "video", "lyrics", "lyric") }
        .toSet()

private class FoxyNewPipeDownloader(
    private val client: OkHttpClient
) : Downloader() {
    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: NewPipeRequest): NewPipeResponse {
        val response = client.newCall(request.toOkHttpRequest()).execute()
        if (response.code == 429) {
            response.close()
            throw ReCaptchaException("reCaptcha challenge requested", request.url())
        }

        return response.toNewPipeResponse()
    }

    override fun executeAsync(
        request: NewPipeRequest,
        callback: AsyncCallback?
    ): CancellableCall {
        val call = client.newCall(request.toOkHttpRequest())
        val cancellableCall = CancellableCall(call)

        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                cancellableCall.setFinished()
                callback?.onError(e)
            }

            override fun onResponse(call: Call, response: okhttp3.Response) {
                try {
                    if (response.code == 429) {
                        response.close()
                        callback?.onError(ReCaptchaException("reCaptcha challenge requested", request.url()))
                        return
                    }

                    callback?.onSuccess(response.toNewPipeResponse())
                } catch (e: Exception) {
                    callback?.onError(e)
                } finally {
                    cancellableCall.setFinished()
                }
            }
        })

        return cancellableCall
    }

    private fun NewPipeRequest.toOkHttpRequest(): okhttp3.Request {
        val requestBuilder = okhttp3.Request.Builder()
            .url(url())
            .method(httpMethod(), dataToSend()?.toRequestBody())
            .addHeader("User-Agent", StreamExtractor.STREAM_USER_AGENT)
            .addHeader("Accept-Language", "en-US,en;q=0.9")
            .addHeader("Cookie", "CONSENT=YES+cb")

        headers().forEach { (name, values) ->
            if (values.size > 1) {
                requestBuilder.removeHeader(name)
                values.forEach { value -> requestBuilder.addHeader(name, value) }
            } else if (values.size == 1) {
                requestBuilder.header(name, values[0])
            }
        }

        return requestBuilder.build()
    }

    private fun okhttp3.Response.toNewPipeResponse(): NewPipeResponse {
        val latestUrl = request.url.toString()
        val body = body?.string()
        val normalizedBody = normalizeResponseBody(latestUrl, body)
        return NewPipeResponse(
            code,
            message,
            headers.toMultimap(),
            normalizedBody,
            normalizedBody?.toByteArray(),
            latestUrl
        )
    }

    private fun normalizeResponseBody(url: String, body: String?): String? {
        if (!url.contains("returnyoutubedislikeapi.com", ignoreCase = true)) return body
        val trimmed = body?.trimStart().orEmpty()
        return if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            body
        } else {
            "{\"likes\":0,\"dislikes\":0,\"viewCount\":0}"
        }
    }
}
