package com.foxymusic

import android.content.Context
import android.content.pm.PackageManager
import okhttp3.Request
import org.json.JSONObject

data class UpdateCheckResult(
    val ok: Boolean,
    val updateAvailable: Boolean,
    val installedVersionName: String,
    val installedVersionCode: Int,
    val latestTag: String,
    val htmlUrl: String,
    val downloadUrl: String,
    val releaseNotes: String,
    val error: String?,
) {
    fun toFlutterMap(): Map<String, Any?> = mapOf(
        "ok" to ok,
        "updateAvailable" to updateAvailable,
        "installedVersionName" to installedVersionName,
        "installedVersionCode" to installedVersionCode,
        "latestTag" to latestTag,
        "tagName" to latestTag,
        "htmlUrl" to htmlUrl,
        "downloadUrl" to downloadUrl,
        "body" to releaseNotes,
        "error" to (error ?: ""),
    )
}

object FoxyGithubUpdate {

    private const val LATEST =
        "https://api.github.com/repos/sparkn2008-del/FoxyMusic/releases/latest"

    fun installedVersion(context: Context): Pair<String, Int> {
        val pm = context.packageManager
        val pkg = context.packageName
        return try {
            @Suppress("DEPRECATION")
            val info = pm.getPackageInfo(pkg, 0)
            val name = info.versionName.orEmpty().ifBlank { "?" }
            val code = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                info.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                info.versionCode
            }
            name to code
        } catch (_: PackageManager.NameNotFoundException) {
            "?" to 0
        }
    }

    /**
     * Fetches GitHub latest release and compares [tag_name] to the installed [versionName].
     * SimpMusic-style: volume crossfade is separate; this is APK update discovery only.
     */
    fun checkForUpdate(context: Context): UpdateCheckResult {
        val (installedName, installedCode) = installedVersion(context)
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
                    return@use UpdateCheckResult(
                        ok = false,
                        updateAvailable = false,
                        installedVersionName = installedName,
                        installedVersionCode = installedCode,
                        latestTag = "",
                        htmlUrl = "",
                        downloadUrl = "",
                        releaseNotes = "",
                        error = "HTTP ${resp.code}",
                    )
                }
                val json = JSONObject(body)
                val tag = json.optString("tag_name", "").trim()
                val html = json.optString("html_url", "")
                val notes = json.optString("body", "")
                var apkUrl = ""
                val assets = json.optJSONArray("assets")
                if (assets != null) {
                    var arm64 = ""
                    var anyApk = ""
                    for (i in 0 until assets.length()) {
                        val a = assets.optJSONObject(i) ?: continue
                        val name = a.optString("name", "")
                        val url = a.optString("browser_download_url", "")
                        if (!name.endsWith(".apk", ignoreCase = true) || url.isBlank()) continue
                        anyApk = url
                        if (name.contains("arm64", ignoreCase = true)) {
                            arm64 = url
                            break
                        }
                    }
                    apkUrl = arm64.ifBlank { anyApk }
                }
                val newer = tag.isNotBlank() &&
                    compareVersionLabels(tag, installedName) > 0
                UpdateCheckResult(
                    ok = true,
                    updateAvailable = newer,
                    installedVersionName = installedName,
                    installedVersionCode = installedCode,
                    latestTag = tag,
                    htmlUrl = html,
                    downloadUrl = apkUrl,
                    releaseNotes = notes,
                    error = null,
                )
            }
        }.getOrElse {
            UpdateCheckResult(
                ok = false,
                updateAvailable = false,
                installedVersionName = installedName,
                installedVersionCode = installedCode,
                latestTag = "",
                htmlUrl = "",
                downloadUrl = "",
                releaseNotes = "",
                error = it.message ?: "network",
            )
        }
    }

    internal fun parseVersionParts(raw: String): List<Int> {
        val digits = Regex("""(\d+)""")
            .findAll(raw)
            .map { it.value.toInt() }
            .toList()
        return when {
            digits.isEmpty() -> listOf(0, 0, 0)
            digits.size == 1 -> listOf(digits[0], 0, 0)
            digits.size == 2 -> listOf(digits[0], digits[1], 0)
            else -> digits.take(3)
        }
    }

    /** Positive if [latest] is newer than [installed]. */
    fun compareVersionLabels(latest: String, installed: String): Int {
        val a = parseVersionParts(latest)
        val b = parseVersionParts(installed)
        for (i in 0 until 3) {
            val c = a[i].compareTo(b[i])
            if (c != 0) return c
        }
        return 0
    }
}
