package com.foxymusic

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import android.util.Log
import okhttp3.Call
import okhttp3.Callback
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.downloader.CancellableCall
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request as NewPipeRequest
import org.schabi.newpipe.extractor.downloader.Response as NewPipeResponse
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLDecoder
import java.util.concurrent.TimeUnit

data class StreamResult(
    val url: String?,
    val error: String? = null,
    val source: String? = null
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

    private val client = OkHttpClient.Builder()
        .retryOnConnectionFailure(true)
        .connectionPool(okhttp3.ConnectionPool(10, 5, TimeUnit.MINUTES))
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(18, TimeUnit.SECONDS)
        .build()

    @Volatile
    private var isNewPipeReady = false

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

    fun getStreamResult(videoId: String): StreamResult {
        val extractorErrors = mutableListOf<String>()
        var lastError: String? = null

        for (ytClient in clients) {
            try {
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
                    .addFoxyAccountHeaders(ytClient.origin)
                    .build()

                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        lastError = "YouTube player request failed (${response.code})"
                        Log.w(TAG, "${ytClient.name} HTTP failed: ${response.code}")
                        return@use
                    }

                    val responseStr = response.body?.string().orEmpty()
                    val json = JSONObject(responseStr)
                    val status = json.optJSONObject("playabilityStatus")
                    val playability = status?.optString("status").orEmpty()

                    if (playability.isNotBlank() && playability != "OK") {
                        lastError = status?.optString("reason").takeUnless { it.isNullOrBlank() }
                            ?.let { "${ytClient.name}: $it" }
                            ?: "${ytClient.name}: This video is not playable"
                        return@use
                    }

                    val streamingData = json.optJSONObject("streamingData")
                    val streamUrl = streamingData?.let(::pickBestPlayableUrl)
                    if (!streamUrl.isNullOrBlank()) {
                        Log.d(TAG, "${ytClient.name} stream selected: ${streamUrl.take(80)}")
                        return StreamResult(streamUrl, source = ytClient.name)
                    }

                    lastError = "${ytClient.name}: No direct audio stream was returned"
                }
            } catch (e: Exception) {
                lastError = "${ytClient.name}: ${e.message ?: "Could not fetch stream URL"}"
                Log.w(TAG, "Innertube client failed: ${ytClient.name}", e)
            }
        }

        lastError?.let { extractorErrors += it }
        when (val newPipeResult = getNewPipeStreamResult(videoId)) {
            is ExtractorAttempt.Success -> {
                Log.d(TAG, "NewPipe stream selected: ${newPipeResult.url.take(80)}")
                return StreamResult(newPipeResult.url, source = "NewPipe")
            }
            is ExtractorAttempt.Failure -> {
                extractorErrors += "NewPipe: ${newPipeResult.message}"
                Log.w(TAG, "NewPipe failed: ${newPipeResult.message}", newPipeResult.throwable)
            }
        }
        return StreamResult(null, extractorErrors.joinToString("\n").ifBlank { "Could not fetch stream URL" })
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

    private fun pickBestPlayableUrl(streamingData: JSONObject): String? {
        val candidates = mutableListOf<JSONObject>()
        streamingData.optJSONArray("adaptiveFormats")?.appendAudioFormatsTo(candidates)
        streamingData.optJSONArray("formats")?.appendAudioFormatsTo(candidates)

        candidates
            .sortedWith(
                compareByDescending<JSONObject> { it.optInt("audioQualityRank") }
                    .thenByDescending { it.optInt("bitrate") }
            )
            .firstNotNullOfOrNull { it.directUrl() }
            ?.let { return it }

        return streamingData.optString("hlsManifestUrl").takeIf { it.isNotBlank() }
    }

    private fun JSONArray.appendAudioFormatsTo(target: MutableList<JSONObject>) {
        for (index in 0 until length()) {
            val format = optJSONObject(index) ?: continue
            val mimeType = format.optString("mimeType")
            val hasAudio = mimeType.startsWith("audio/") || format.has("audioQuality")
            if (hasAudio) {
                val rank = when (format.optString("audioQuality")) {
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

    private fun getNewPipeStreamResult(videoId: String): ExtractorAttempt {
        return try {
            ensureNewPipe()
            val streamInfo = StreamInfo.getInfo(
                NewPipe.getService(0),
                "https://www.youtube.com/watch?v=$videoId"
            )

            val audioStream = streamInfo.audioStreams
                .filter { !it.content.isNullOrBlank() }
                .maxByOrNull { it.averageBitrate ?: 0 }

            val url = audioStream?.content
            if (url.isNullOrBlank()) {
                ExtractorAttempt.Failure(
                    "No audio streams. audio=${streamInfo.audioStreams.size}, video=${streamInfo.videoStreams.size}"
                )
            } else {
                ExtractorAttempt.Success(url)
            }
        } catch (e: Exception) {
            ExtractorAttempt.Failure("${e::class.java.simpleName}: ${e.message}", e)
        }
    }

    private fun ensureNewPipe() {
        if (isNewPipeReady) return
        synchronized(this) {
            if (!isNewPipeReady) {
                YoutubeParsingHelper.setConsentAccepted(true)
                NewPipe.init(FoxyNewPipeDownloader(client))
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
    data class Success(val url: String) : ExtractorAttempt()
    data class Failure(val message: String, val throwable: Throwable? = null) : ExtractorAttempt()
}

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
