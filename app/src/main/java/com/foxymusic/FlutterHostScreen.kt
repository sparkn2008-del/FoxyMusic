package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun FlutterHostScreen() {
    val colors = foxyPalette()
    val context = LocalContext.current
    val status = remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Flutter UI Host", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Black)
        Text(
            "This route is wired for add-to-app migration. It launches FlutterActivity if Flutter embedding is present.",
            color = colors.muted
        )
        Spacer(Modifier.height(6.dp))
        Button(onClick = {
            val ok = FoxyFlutterLauncher.launchHomePlayer(context)
            status.value = if (ok) {
                "Launched Flutter activity."
            } else {
                "Flutter embedding not found in app build yet."
            }
        }) {
            Text("Open Flutter Home + Player")
        }
        if (status.value.isNotBlank()) {
            Text(status.value, color = colors.muted)
        }
    }
}

