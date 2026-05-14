package com.foxymusic

import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Login
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * YouTube Music login that does NOT require the user to manually paste cookies.
 *
 * We open an in-app WebView, then detect login completion by checking for `SAPISID`
 * in CookieManager cookies. Once detected, we save the session into [FoxyAccount].
 */
@Composable
fun LoginScreen(onBack: () -> Unit = {}) {
    val colors = foxyPalette()
    var readyToSave by remember { mutableStateOf(false) }
    var detectedCookie by remember { mutableStateOf<String?>(null) }

    val cookieManager = CookieManager.getInstance().apply {
        setAcceptCookie(true)
    }

    val context = LocalContext.current
    val webView = remember { WebView(context) }

    DisposableEffect(Unit) {
        onDispose {
            webView.destroy()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Spacer(modifier = Modifier.height(12.dp))
        Icon(Icons.Rounded.Login, contentDescription = null, tint = colors.accent)
        Text(
            "Connect YouTube Music",
            color = Color.White,
            fontSize = 28.sp,
            fontWeight = FontWeight.Black
        )
        Text(
            "Sign in in the browser. We'll detect your login and connect automatically.",
            color = colors.muted
        )

        AndroidView(
            factory = {
                webView.apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView?, url: String?) {
                            super.onPageFinished(view, url)
                            val cookies = cookieManager.getCookie("https://music.youtube.com").orEmpty()
                            if (cookies.contains("SAPISID=")) {
                                detectedCookie = cookies
                                readyToSave = true
                            }
                        }
                    }
                    loadUrl("https://music.youtube.com/")
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .weight(1f)
        )

        Button(
            onClick = {
                val cookie = detectedCookie
                if (!cookie.isNullOrBlank()) {
                    FoxyAccount.updateSession(cookie)
                }
                onBack()
            },
            enabled = readyToSave
        ) {
            Text("Save session")
        }
    }
}
