package com.foxymusic

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * App entry: full Flutter UI in [lib/main.dart]. Kotlin playback, account, and
 * library logic stay behind [FoxyFlutterBridge] on the same channels used by Flutter.
 */
class MainActivity : FlutterFragmentActivity() {

    private var bridge: FoxyFlutterBridge? = null
    private var pendingHomeBgResult: MethodChannel.Result? = null
    private var pendingLocalAudioResult: MethodChannel.Result? = null
    private var pendingLocalFolderResult: MethodChannel.Result? = null
    private var pendingRecognitionResult: MethodChannel.Result? = null

    private val pickHomeBackgroundLauncher =
        registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
            val pending = pendingHomeBgResult
            pendingHomeBgResult = null
            if (pending == null) return@registerForActivityResult
            if (uri == null) {
                pending.success(mapOf("ok" to false, "cancelled" to true))
                return@registerForActivityResult
            }
            val path = FoxyHomeBackground.saveFromUri(applicationContext, uri)
            if (path != null) {
                FoxySettings.update { it.copy(homeBackgroundEnabled = true) }
                bridge?.emitAppearanceChanged()
                pending.success(mapOf("ok" to true, "path" to path))
            } else {
                pending.error("pick_failed", "Could not save image", null)
            }
        }

    private val requestMediaPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                launchHomeBackgroundPicker()
            } else {
                pendingHomeBgResult?.error(
                    "permission_denied",
                    "Storage permission is required to choose a background image",
                    null,
                )
                pendingHomeBgResult = null
            }
        }

    private val importLocalAudioLauncher =
        registerForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris: List<Uri> ->
            val pending = pendingLocalAudioResult
            pendingLocalAudioResult = null
            if (pending == null) return@registerForActivityResult
            if (uris.isEmpty()) {
                pending.success(mapOf("ok" to false, "cancelled" to true, "imported" to 0))
                return@registerForActivityResult
            }
            lifecycleScope.launch {
                val response = withContext(Dispatchers.IO) {
                    FoxyLocalMusic.importUris(applicationContext, uris)
                }
                bridge?.emitLibraryDownloadsChangedEvent()
                pending.success(response)
            }
        }

    private val importLocalFolderLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? ->
            val pending = pendingLocalFolderResult
            pendingLocalFolderResult = null
            if (pending == null) return@registerForActivityResult
            if (uri == null) {
                pending.success(mapOf("ok" to false, "cancelled" to true, "imported" to 0))
                return@registerForActivityResult
            }
            runCatching {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            lifecycleScope.launch {
                val response = withContext(Dispatchers.IO) {
                    FoxyLocalMusic.importFolder(applicationContext, uri)
                }
                bridge?.emitLibraryDownloadsChangedEvent()
                pending.success(response)
            }
        }

    private val requestRecordAudioPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val pending = pendingRecognitionResult
            pendingRecognitionResult = null
            if (pending == null) return@registerForActivityResult
            if (granted) {
                bridge?.startRecognition()
                pending.success(mapOf("ok" to true))
            } else {
                pending.error(
                    "permission_denied",
                    "Microphone permission is required for music recognition",
                    null,
                )
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FoxySettings.init(applicationContext)
        FoxyAccount.init(applicationContext)

        lifecycleScope.launch(Dispatchers.IO) {
            FoxyLibraryStore.init(applicationContext)
            FoxyRecognitionHistory.init(applicationContext)
            FoxyUserPlaylists.init(applicationContext)
            MusicPlayer.init(applicationContext)
            FoxyMedia3Downloads.ensureInitialized(applicationContext)
        }

        val b = FoxyFlutterBridge(this)
        bridge = b
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FoxyFlutterChannels.METHOD_CHANNEL)
            .setMethodCallHandler(b)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FoxyFlutterChannels.EVENT_CHANNEL)
            .setStreamHandler(b)
    }

    fun pickHomeBackground(result: MethodChannel.Result) {
        pendingHomeBgResult = result
        val permission = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                Manifest.permission.READ_MEDIA_IMAGES
            else -> Manifest.permission.READ_EXTERNAL_STORAGE
        }
        when (ContextCompat.checkSelfPermission(this, permission)) {
            PackageManager.PERMISSION_GRANTED -> launchHomeBackgroundPicker()
            else -> requestMediaPermissionLauncher.launch(permission)
        }
    }

    fun clearHomeBackground(result: MethodChannel.Result) {
        FoxyHomeBackground.clear(applicationContext)
        FoxySettings.update { it.copy(homeBackgroundEnabled = false) }
        bridge?.emitAppearanceChanged()
        result.success(mapOf("ok" to true))
    }

    fun importLocalAudio(result: MethodChannel.Result) {
        pendingLocalAudioResult = result
        importLocalAudioLauncher.launch("audio/*")
    }

    fun importLocalFolder(result: MethodChannel.Result) {
        pendingLocalFolderResult = result
        importLocalFolderLauncher.launch(null)
    }

    fun startRecognition(result: MethodChannel.Result) {
        pendingRecognitionResult = result
        when (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
        ) {
            PackageManager.PERMISSION_GRANTED -> {
                pendingRecognitionResult = null
                bridge?.startRecognition()
                result.success(mapOf("ok" to true))
            }
            else -> requestRecordAudioPermissionLauncher.launch(
                Manifest.permission.RECORD_AUDIO,
            )
        }
    }

    fun restartApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
        finishAffinity()
        Runtime.getRuntime().exit(0)
    }

    private fun launchHomeBackgroundPicker() {
        pickHomeBackgroundLauncher.launch("image/*")
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
