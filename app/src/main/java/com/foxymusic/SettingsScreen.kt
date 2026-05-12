package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Accessibility
import androidx.compose.material.icons.rounded.BatterySaver
import androidx.compose.material.icons.rounded.BlurOn
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.DragIndicator
import androidx.compose.material.icons.rounded.Gesture
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.History
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen() {
    val settings by FoxySettings.state.collectAsState()
    val colors = foxyPalette()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        item {
            Spacer(modifier = Modifier.height(22.dp))
            Text("Settings", color = Color.White, fontSize = 32.sp, fontWeight = FontWeight.Bold)
            Text("Theme, player, privacy, and navigation controls.", color = FoxyMuted, fontSize = 14.sp)
        }

        item {
            SettingsSection("Appearance")
            ThemeModePicker(settings.themeMode)
            ToggleRow(Icons.Rounded.BlurOn, "Blur effects", "Transparent player surfaces", settings.blurEffects) {
                FoxySettings.update { current -> current.copy(blurEffects = it) }
            }
            ToggleRow(Icons.Rounded.AutoAwesome, "Song-based colors", "Player and key surfaces follow the current song thumbnail", settings.dynamicSongColors) {
                FoxySettings.update { current -> current.copy(dynamicSongColors = it) }
            }
            AccentPicker(selectedAccent = settings.accent, onAccentSelected = { selected ->
                FoxySettings.update { current -> current.copy(accentArgb = selected.toArgb()) }
            })
        }

        item {
            SettingsSection("App Appearance Customisation")
            IconSizePicker(settings.iconScale)
            BottomNavSizePicker(settings.bottomNavScale)
            ThemeModePicker(settings.themeMode)
            AccentPicker(selectedAccent = settings.accent, onAccentSelected = { selected ->
                FoxySettings.update { current -> current.copy(accentArgb = selected.toArgb()) }
            })
        }

        item {
            SettingsSection("Player")
            ToggleRow(Icons.Rounded.Palette, "Compact player mode", "Smaller mini player controls", settings.compactPlayer) {
                FoxySettings.update { current -> current.copy(compactPlayer = it) }
            }
            ToggleRow(Icons.Rounded.Gesture, "Gesture controls", "Swipe actions for playback", settings.gestureControls) {
                FoxySettings.update { current -> current.copy(gestureControls = it) }
            }
            SliderRow(
                icon = Icons.Rounded.DragIndicator,
                title = "Grid size",
                subtitle = "${settings.gridColumns} columns for albums and playlists",
                value = settings.gridColumns.toFloat(),
                onValueChange = { value ->
                    FoxySettings.update { current -> current.copy(gridColumns = value.toInt().coerceIn(2, 4)) }
                }
            )
        }

        item {
            SettingsSection("Navigation")
            ToggleRow(Icons.Rounded.Accessibility, "Top action buttons", "Show history, stats, and together buttons in the top bar", settings.showTopActions) {
                FoxySettings.update { current -> current.copy(showTopActions = it) }
            }
            ToggleRow(Icons.Rounded.Accessibility, "Bottom labels", "Show text labels under bottom navigation icons", settings.showBottomLabels) {
                FoxySettings.update { current -> current.copy(showBottomLabels = it) }
            }
        }

        item {
            SettingsSection("Smart Extras")
            StaticRow(Icons.Rounded.Timer, "Sleep timer", "Stop playback after a chosen time")
            ToggleRow(Icons.Rounded.History, "Save listening history", "Used for library history and local recommendations", settings.saveHistory) {
                FoxySettings.update { current -> current.copy(saveHistory = it) }
            }
            StaticRow(Icons.Rounded.Security, "Privacy controls", "Sign out clears WebView cookies and local account session")
            StaticRow(Icons.Rounded.BatterySaver, "Battery optimization", "Prefer lightweight playback UI")
            StaticRow(Icons.Rounded.Accessibility, "Accessibility", "Large touch targets and clear labels")
        }

        item {
            SettingsSection("Navigation order")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                listOf("Home", "Search", "Library", "Downloads", "Settings").forEach { label ->
                    FilterChip(
                        selected = label == "Home",
                        onClick = {},
                        label = { Text(label) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = colors.accent.copy(alpha = 0.2f),
                            selectedLabelColor = colors.accent,
                            labelColor = colors.muted,
                            containerColor = colors.surface
                        ),
                        border = FilterChipDefaults.filterChipBorder(
                            borderColor = Color.White.copy(alpha = 0.08f),
                            selectedBorderColor = colors.accent.copy(alpha = 0.35f)
                        )
                    )
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
        }
    }
}

@Composable
private fun SettingsSection(title: String) {
    val colors = foxyPalette()
    Text(title.uppercase(), color = colors.accent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    Spacer(modifier = Modifier.height(10.dp))
}

@Composable
private fun ToggleRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface)
            .clickable { onCheckedChange(!checked) }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingsIcon(icon)
        Column(modifier = Modifier.padding(start = 14.dp).weight(1f)) {
            Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = colors.muted, fontSize = 12.sp)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = colors.accent
            )
        )
    }
    Spacer(modifier = Modifier.height(10.dp))
}

@Composable
private fun StaticRow(icon: ImageVector, title: String, subtitle: String) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingsIcon(icon)
        Column(modifier = Modifier.padding(start = 14.dp)) {
            Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = colors.muted, fontSize = 12.sp)
        }
    }
    Spacer(modifier = Modifier.height(10.dp))
}

@Composable
private fun SliderRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    value: Float,
    onValueChange: (Float) -> Unit
) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface)
            .padding(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SettingsIcon(icon)
            Column(modifier = Modifier.padding(start = 14.dp)) {
                Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Text(subtitle, color = colors.muted, fontSize = 12.sp)
            }
        }
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = 2f..5f,
            steps = 2
        )
    }
}

@Composable
private fun AccentPicker(selectedAccent: Color, onAccentSelected: (Color) -> Unit) {
    val colors = foxyPalette()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column {
            Text("Custom accent color", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text("Preview the app accent palette", color = colors.muted, fontSize = 12.sp)
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .padding(start = 12.dp)
                .horizontalScroll(rememberScrollState())
        ) {
            listOf(
                Color(0xFFFF7A45),
                Color(0xFFFF4F6D),
                Color(0xFFE6B34A),
                Color(0xFF9BDB67),
                Color(0xFF55C7A4),
                Color(0xFF73D1E5),
                Color(0xFF8EA7FF),
                Color(0xFFB58CFF),
                Color(0xFFFF8BD1),
                Color(0xFFFFFFFF),
                Color(0xFF111313)
            ).forEach { color ->
                Box(
                    modifier = Modifier
                        .size(if (selectedAccent == color) 38.dp else 31.dp)
                        .clip(CircleShape)
                        .background(color)
                        .clickable { onAccentSelected(color) }
                )
            }
        }
    }
}

@Composable
private fun ThemeModePicker(themeMode: Int) {
    SettingChoiceRow(
        title = "Theme",
        subtitle = "Follow the phone theme or force light/dark",
        options = listOf("System Default", "Dark Mode", "Light Mode"),
        selectedIndex = themeMode,
        onSelect = { selected -> FoxySettings.update { it.copy(themeMode = selected) } }
    )
}

@Composable
private fun IconSizePicker(iconScale: Int) {
    SettingChoiceRow(
        title = "Icon size",
        subtitle = "Adjust app action and navigation icon scale",
        options = listOf("Small", "Medium", "Large"),
        selectedIndex = iconScale,
        onSelect = { selected -> FoxySettings.update { it.copy(iconScale = selected) } }
    )
}

@Composable
private fun BottomNavSizePicker(bottomNavScale: Int) {
    SettingChoiceRow(
        title = "Bottom tab size",
        subtitle = "Controls how chunky the bottom Home/Search/Library tabs feel",
        options = listOf("Small", "Medium", "Large"),
        selectedIndex = bottomNavScale,
        onSelect = { selected -> FoxySettings.update { it.copy(bottomNavScale = selected) } }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingChoiceRow(
    title: String,
    subtitle: String,
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit
) {
    val colors = foxyPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface)
            .padding(14.dp)
    ) {
        Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
        Text(subtitle, color = colors.muted, fontSize = 12.sp)
        Spacer(modifier = Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            options.forEachIndexed { index, label ->
                FilterChip(
                    selected = selectedIndex == index,
                    onClick = { onSelect(index) },
                    label = { Text(label, fontSize = 12.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = colors.accent.copy(alpha = 0.24f),
                        selectedLabelColor = Color.White,
                        labelColor = colors.muted,
                        containerColor = colors.surfaceHigh
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        borderColor = Color.White.copy(alpha = 0.08f),
                        selectedBorderColor = colors.accent.copy(alpha = 0.45f)
                    )
                )
            }
        }
    }
    Spacer(modifier = Modifier.height(10.dp))
}

@Composable
private fun SettingsIcon(icon: ImageVector) {
    val colors = foxyPalette()
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(colors.surfaceHigh),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(23.dp))
    }
}
