package com.foxymusic

import okhttp3.Request
import org.json.JSONObject

object FoxyGithubUpdate {

    private const val LATEST =
        "https://api.github.com/repos/sparkn2008-del/FoxyMusic/releases/latest"

    fun checkLatest(): Map<String, Any?> {
        val client = FoxyNetworking.streamingClient()
        val req = Request.Builder()
            .url(LATEST)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "FoxyMusic-Android")
            .build()
        return runCatching {
            client.newCall(req).execute().use { resp ->
                val body = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    return@runCatching mapOf(
                        "ok" to false,
                        "error" to "HTTP ${resp.code}",
                        "tagName" to "",
                        "htmlUrl" to "",
                        "downloadUrl" to ""
                    )
                }
                val json = JSONObject(body)
                val tag = json.optString("tag_name", "")
                val html = json.optString("html_url", "")
                var apkUrl = ""
                val assets = json.optJSONArray("assets")
                if (assets != null) {
                    for (i in 0 until assets.length()) {
                        val a = assets.optJSONObject(i) ?: continue
                        val name = a.optString("name", "")
                        val url = a.optString("browser_download_url", "")
                        if (name.endsWith(".apk", ignoreCase = true) && url.isNotBlank()) {
                            apkUrl = url
                            break
                        }
                    }
                }
                mapOf(
                    "ok" to true,
                    "tagName" to tag,
                    "htmlUrl" to html,
                    "downloadUrl" to apkUrl,
                    "body" to json.optString("body", "")
                )
            }
        }.getOrElse {
            mapOf(
                "ok" to false,
                "error" to (it.message ?: "network"),
                "tagName" to "",
                "htmlUrl" to "",
                "downloadUrl" to ""
            )
        }
    }
}
