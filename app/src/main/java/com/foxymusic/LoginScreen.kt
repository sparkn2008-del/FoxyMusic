package com.foxymusic

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun LoginScreen(onBack: () -> Unit) {
    val colors = foxyPalette()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var signedIn by remember { mutableStateOf(FoxyAccount.state.value.isSignedIn) }
    var status by remember { mutableStateOf("Sign in with your YouTube Music account.") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = "Back", tint = Color.White)
            }
            Text("Connect YouTube Music", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Text(status, color = colors.muted, modifier = Modifier.padding(horizontal = 22.dp))
        Spacer(modifier = Modifier.height(10.dp))
        Box(modifier = Modifier.weight(1f)) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { viewContext ->
                    CookieManager.getInstance().setAcceptCookie(true)
                    WebView(viewContext).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView?, url: String?) {
                                val cookie = CookieManager.getInstance()
                                    .getCookie("https://music.youtube.com")
                                    .orEmpty()
                                if ("SAPISID" in cookie.parseCookies()) {
                                    FoxyAccount.updateSession(cookie)
                                    signedIn = true
                                    status = "Signed in. Personal recommendations are ready."
                                    scope.launch {
                                        val profile = withContext(Dispatchers.IO) {
                                            runCatching { YTMusicApi.accountInfo() }.getOrNull()
                                        }
                                        profile?.let {
                                            FoxyAccount.updateProfile(it.name, it.email, it.avatarUrl)
                                        }
                                    }
                                }
                            }
                        }
                        loadUrl("https://music.youtube.com")
                    }
                }
            )
            if (signedIn) {
                Button(
                    onClick = onBack,
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(22.dp)
                        .fillMaxWidth()
                ) {
                    Icon(Icons.Rounded.CheckCircle, contentDescription = null)
                    Text("Return to FoxyMusic", modifier = Modifier.padding(start = 8.dp))
                }
            }
        }
    }
}
