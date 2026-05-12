package com.foxymusic

import android.Manifest
import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }

        FoxySettings.init(applicationContext)
        FoxyAccount.init(applicationContext)
        FoxyLibraryStore.init(applicationContext)
        MusicPlayer.init(applicationContext)

        setContent {
            FoxyMusicTheme {
                Surface(color = MaterialTheme.colorScheme.background) {
                    FoxyMusicApp()
                }
            }
        }
    }
}
