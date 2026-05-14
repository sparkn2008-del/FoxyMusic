package com.foxymusic

import android.content.Context
import android.content.Intent

/**
 * Best-effort Flutter launcher without compile-time Flutter dependency.
 *
 * If Flutter embedding classes are packaged later, this can launch
 * `io.flutter.embedding.android.FlutterActivity`.
 */
object FoxyFlutterLauncher {
    fun canLaunch(context: Context): Boolean = true

    fun launchHomePlayer(context: Context): Boolean {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
    }
}

