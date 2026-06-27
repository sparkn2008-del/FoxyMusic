package com.foxymusic

import android.content.Context
import android.content.SharedPreferences
import android.webkit.CookieManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.security.MessageDigest

data class FoxyAccountState(
    val cookie: String = "",
    val name: String = "",
    val email: String = "",
    val avatarUrl: String = "",
    val pageId: String = "",
) {
    val isSignedIn: Boolean
        get() = cookie.parseCookies().containsKey("SAPISID")

    val displayName: String
        get() = name.ifBlank { if (isSignedIn) "YouTube Music" else "Guest listener" }
}

object FoxyAccount {
    private const val PREFS = "foxy_account"
    private const val KEY_COOKIE = "cookie"
    private const val KEY_NAME = "name"
    private const val KEY_EMAIL = "email"
    private const val KEY_AVATAR = "avatar"
    private const val KEY_PAGE_ID = "page_id"

    private var prefs: SharedPreferences? = null
    private val _state = MutableStateFlow(FoxyAccountState())
    val state: StateFlow<FoxyAccountState> = _state

    fun init(context: Context) {
        prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _state.value = FoxyAccountState(
            cookie = prefs?.getString(KEY_COOKIE, "").orEmpty(),
            name = prefs?.getString(KEY_NAME, "").orEmpty(),
            email = prefs?.getString(KEY_EMAIL, "").orEmpty(),
            avatarUrl = prefs?.getString(KEY_AVATAR, "").orEmpty(),
            pageId = prefs?.getString(KEY_PAGE_ID, "").orEmpty(),
        )
    }

    fun updateSession(
        cookie: String,
        name: String = "",
        email: String = "",
        avatarUrl: String = "",
        pageId: String = "",
    ) {
        val merged = FoxyAccountState(
            cookie = cookie,
            name = name.ifBlank { _state.value.name },
            email = email.ifBlank { _state.value.email },
            avatarUrl = avatarUrl.ifBlank { _state.value.avatarUrl },
            pageId = pageId.ifBlank { _state.value.pageId },
        )
        prefs?.edit()
            ?.putString(KEY_COOKIE, merged.cookie)
            ?.putString(KEY_NAME, merged.name)
            ?.putString(KEY_EMAIL, merged.email)
            ?.putString(KEY_AVATAR, merged.avatarUrl)
            ?.putString(KEY_PAGE_ID, merged.pageId)
            ?.apply()
        StreamUrlCache.clear()
        _state.value = merged
    }

    fun updateProfile(name: String, email: String, avatarUrl: String, pageId: String = "") {
        _state.update { current ->
            val updated = current.copy(
                name = name.ifBlank { current.name },
                email = email.ifBlank { current.email },
                avatarUrl = avatarUrl.ifBlank { current.avatarUrl },
                pageId = pageId.ifBlank { current.pageId },
            )
            prefs?.edit()
                ?.putString(KEY_NAME, updated.name)
                ?.putString(KEY_EMAIL, updated.email)
                ?.putString(KEY_AVATAR, updated.avatarUrl)
                ?.putString(KEY_PAGE_ID, updated.pageId)
                ?.apply()
            updated
        }
    }

    fun signOut() {
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        prefs?.edit()?.clear()?.apply()
        StreamUrlCache.clear()
        _state.value = FoxyAccountState()
    }
}

fun String.parseCookies(): Map<String, String> {
    if (isBlank()) return emptyMap()
    return split(";")
        .mapNotNull { part ->
            val trimmed = part.trim()
            val index = trimmed.indexOf("=")
            if (index <= 0) null else trimmed.substring(0, index) to trimmed.substring(index + 1)
        }
        .toMap()
}

fun String.sapisidHashHeader(origin: String = "https://music.youtube.com"): String? {
    val sapisid = parseCookies()["SAPISID"] ?: return null
    val timestamp = System.currentTimeMillis() / 1000
    val source = "$timestamp $sapisid $origin"
    val hash = MessageDigest.getInstance("SHA-1")
        .digest(source.toByteArray())
        .joinToString("") { "%02x".format(it) }
    return "SAPISIDHASH ${timestamp}_$hash"
}
