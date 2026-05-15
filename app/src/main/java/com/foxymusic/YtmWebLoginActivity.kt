package com.foxymusic

import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.android.material.progressindicator.LinearProgressIndicator

/**
 * In-app YouTube Music sign-in. Cookies stay in this process’s [CookieManager], so we can persist
 * [SAPISID] for Innertube (unlike signing in only in Chrome or the YTM app).
 */
class YtmWebLoginActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var status: TextView
    private lateinit var saveButton: MaterialButton
    private lateinit var progress: LinearProgressIndicator

    private var detectedCookie: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dm = resources.displayMetrics
        fun dp(v: Int) = (v * dm.density).toInt()

        val cookieManager = CookieManager.getInstance().apply {
            setAcceptCookie(true)
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val toolbar = MaterialToolbar(this).apply {
            title = getString(R.string.ytm_login_toolbar_title)
            setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material)
            setNavigationOnClickListener { finish() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }

        status = TextView(this).apply {
            text = getString(R.string.ytm_login_status_waiting)
            setTextColor(0xFFB0B0B0.toInt())
            textSize = 13f
            setPadding(dp(16), dp(6), dp(16), dp(4))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }

        progress = LinearProgressIndicator(this).apply {
            isIndeterminate = true
            visibility = android.view.View.VISIBLE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
        }

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                cookieManager.setAcceptThirdPartyCookies(this, true)
            }
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    this@YtmWebLoginActivity.progress.visibility = android.view.View.GONE
                    this@YtmWebLoginActivity.progress.isIndeterminate = false
                    refreshCookieState(cookieManager)
                }
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
            loadUrl("https://music.youtube.com/")
        }

        saveButton = MaterialButton(this).apply {
            text = getString(R.string.ytm_login_save)
            isEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMargins(dp(16), dp(8), dp(16), dp(24))
            }
            setOnClickListener { saveAndFinish() }
        }

        root.addView(toolbar)
        root.addView(progress)
        root.addView(status)
        root.addView(webView)
        root.addView(saveButton)
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) {
            refreshCookieState(CookieManager.getInstance())
        }
    }

    private fun refreshCookieState(cookieManager: CookieManager) {
        val raw = cookieManager.getCookie("https://music.youtube.com").orEmpty()
        val ok = raw.contains("SAPISID=")
        if (ok) {
            detectedCookie = raw
            status.text = getString(R.string.ytm_login_status_ready)
            saveButton.isEnabled = true
        } else {
            detectedCookie = null
            saveButton.isEnabled = false
            status.text = getString(R.string.ytm_login_status_waiting)
        }
    }

    private fun saveAndFinish() {
        val c = detectedCookie?.trim().orEmpty()
        if (c.isBlank() || !c.contains("SAPISID=")) return
        FoxyAccount.updateSession(c)
        FoxyFlutterBridge.notifyAccountSessionUpdated()
        finish()
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }
}
