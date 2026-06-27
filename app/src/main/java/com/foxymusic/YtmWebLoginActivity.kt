package com.foxymusic

import android.app.AlertDialog
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.Menu
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.setPadding
import androidx.lifecycle.lifecycleScope
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.progressindicator.LinearProgressIndicator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * In-app YouTube Music sign-in. Like SimpMusic, this page captures the WebView
 * YouTube Music cookie, saves automatically after login, and exposes a manual
 * cookie fallback from the top bar.
 */
class YtmWebLoginActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var status: TextView
    private lateinit var progress: LinearProgressIndicator

    private var detectedCookie: String? = null
    private var saved = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK

        val dm = resources.displayMetrics
        fun dp(v: Int) = (v * dm.density).toInt()

        val cookieManager = CookieManager.getInstance().apply {
            setAcceptCookie(true)
            removeAllCookies(null)
            flush()
        }

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        progress = LinearProgressIndicator(this).apply {
            isIndeterminate = true
            visibility = View.VISIBLE
            trackColor = 0x33000000
            setIndicatorColor(Color.WHITE)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(2),
            )
        }

        webView = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.userAgentString =
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                cookieManager.setAcceptThirdPartyCookies(this, true)
            }
            webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                    this@YtmWebLoginActivity.progress.visibility =
                        if (newProgress >= 100 || saved) View.GONE else View.VISIBLE
                    this@YtmWebLoginActivity.progress.isIndeterminate = newProgress <= 5
                    if (newProgress in 6..99) {
                        this@YtmWebLoginActivity.progress.progress = newProgress
                    }
                }
            }
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    this@YtmWebLoginActivity.progress.visibility = View.GONE
                    refreshCookieState(cookieManager)
                }
            }
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            loadUrl(LOGIN_URL)
        }
        root.addView(webView)

        val chrome = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xF0000000.toInt(), 0xB8000000.toInt(), 0x00000000),
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(132),
                Gravity.TOP,
            )
        }

        val toolbar = MaterialToolbar(this).apply {
            title = getString(R.string.ytm_login_toolbar_title)
            setTitleTextColor(Color.WHITE)
            setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material)
            setNavigationOnClickListener { finish() }
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(0, statusBarHeight(), 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(64) + statusBarHeight(),
            )
            menu.add(Menu.NONE, MENU_COOKIE, Menu.NONE, getString(R.string.ytm_login_manual_cookie))
                .setIcon(android.R.drawable.ic_menu_edit)
                .setShowAsAction(MenuItemShowAsAction)
            setOnMenuItemClickListener {
                if (it.itemId == MENU_COOKIE) {
                    showManualCookieDialog()
                    true
                } else {
                    false
                }
            }
        }

        chrome.addView(toolbar)
        chrome.addView(progress)
        root.addView(chrome)

        status = TextView(this).apply {
            text = getString(R.string.ytm_login_status_waiting)
            setTextColor(0xFFEDEDED.toInt())
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(dp(16))
            background = rounded(0xD9111111.toInt(), dp(18), 0x22FFFFFF)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ).apply {
                setMargins(dp(18), 0, dp(18), dp(22))
            }
        }
        root.addView(status)

        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) refreshCookieState(CookieManager.getInstance())
    }

    private fun refreshCookieState(cookieManager: CookieManager) {
        if (saved) return
        val raw = listOf(
            "https://music.youtube.com",
            "https://youtube.com",
            "https://www.youtube.com",
        ).joinToString("; ") { cookieManager.getCookie(it).orEmpty() }
        val ok = raw.contains("SAPISID=")
        if (ok) {
            detectedCookie = raw
            status.text = getString(R.string.ytm_login_status_ready)
            saveAndFinish(raw, auto = true)
        } else {
            detectedCookie = null
            status.text = getString(R.string.ytm_login_status_waiting)
        }
    }

    private fun showManualCookieDialog() {
        val input = EditText(this).apply {
            minLines = 3
            maxLines = 6
            hint = "SAPISID=..."
            setSingleLine(false)
        }
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.ytm_login_manual_cookie))
            .setMessage(getString(R.string.ytm_login_manual_cookie_hint))
            .setView(input)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.ytm_login_save) { _, _ ->
                saveAndFinish(input.text?.toString().orEmpty(), auto = false)
            }
            .show()
    }

    private fun saveAndFinish(cookieOverride: String? = null, auto: Boolean = false) {
        if (saved) return
        val c = cookieOverride?.trim().takeUnless { it.isNullOrBlank() }
            ?: detectedCookie?.trim().orEmpty()
        if (c.isBlank() || !c.contains("SAPISID=")) {
            Toast.makeText(this, R.string.ytm_login_invalid_cookie, Toast.LENGTH_SHORT).show()
            return
        }
        saved = true
        progress.visibility = View.VISIBLE
        progress.isIndeterminate = true
        status.text = if (auto) {
            getString(R.string.ytm_login_status_saving)
        } else {
            getString(R.string.ytm_login_status_saving_manual)
        }
        lifecycleScope.launch {
            val profile = withContext(Dispatchers.IO) {
                YTMusicAuthApi.fetchAccountProfiles(c).firstOrNull()
            }
            FoxyAccount.updateSession(
                cookie = c,
                name = profile?.name.orEmpty(),
                email = profile?.email.orEmpty(),
                avatarUrl = profile?.avatarUrl.orEmpty(),
                pageId = profile?.pageId.orEmpty(),
            )
            FoxyFlutterBridge.notifyAccountSessionUpdated()
            progress.visibility = View.GONE
            status.text = getString(R.string.ytm_login_status_saved)
            delay(500)
            finish()
        }
    }

    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else 0
    }

    private fun rounded(color: Int, radius: Int, stroke: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius.toFloat()
            setStroke(1, stroke)
        }

    private companion object {
        const val LOGIN_URL =
            "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F"
        const val MENU_COOKIE = 1001
        const val MenuItemShowAsAction = 2
    }
}
