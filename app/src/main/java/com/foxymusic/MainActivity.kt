package com.foxymusic

import android.Manifest
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * App entry: full Flutter UI in [lib/main.dart]. Kotlin playback, account, and
 * library logic stay behind [FoxyFlutterBridge] on the same channels used by Flutter.
 */
class MainActivity : FlutterActivity() {

    private var bridge: FoxyFlutterBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FoxySettings.init(applicationContext)
        FoxyAccount.init(applicationContext)
        FoxyLibraryStore.init(applicationContext)
        FoxyUserPlaylists.init(applicationContext)
        MusicPlayer.init(applicationContext)
        FoxyMedia3Downloads.ensureInitialized(applicationContext)

        val b = FoxyFlutterBridge(this)
        bridge = b
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FoxyFlutterChannels.METHOD_CHANNEL)
            .setMethodCallHandler(b)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FoxyFlutterChannels.EVENT_CHANNEL)
            .setStreamHandler(b)
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
