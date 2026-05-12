package com.foxymusic

import androidx.compose.runtime.collectAsState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun LoginScreen(onBack: () -> Unit = {}) {
    val colors = foxyPalette()
    var cookie by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Spacer(modifier = Modifier.height(12.dp))
        Icon(Icons.Rounded.Login, contentDescription = null, tint = colors.accent)
        Text("Connect YouTube Music", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Black)
        Text("Paste your YouTube Music cookie to enable personalized requests.", color = colors.muted)
        OutlinedTextField(
            value = cookie,
            onValueChange = { cookie = it },
            label = { Text("Cookie") },
            minLines = 4,
            modifier = Modifier.weight(1f)
        )
        Button(
            onClick = {
                FoxyAccount.updateSession(cookie)
                onBack()
            },
            enabled = cookie.isNotBlank()
        ) {
            Text("Save session")
        }
    }
}
