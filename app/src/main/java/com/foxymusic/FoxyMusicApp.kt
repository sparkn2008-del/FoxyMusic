package com.foxymusic

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage

data class AppDestination(
    val route: String,
    val label: String,
    val icon: ImageVector
)

private val bottomDestinations = listOf(
    AppDestination("home", "Home", Icons.Rounded.Home),
    AppDestination("search", "Search", Icons.Rounded.Search),
    AppDestination("library", "Library", Icons.Rounded.LibraryMusic),
    AppDestination("profile", "Me", Icons.Rounded.Person)
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FoxyMusicApp() {
    val navController = rememberNavController()
    val currentBackStack by navController.currentBackStackEntryAsState()
    val currentRoute = currentBackStack?.destination?.route ?: "home"
    val playerState by MusicPlayer.state.collectAsState()
    val settings by FoxySettings.state.collectAsState()
    val account by FoxyAccount.state.collectAsState()
    val colors = foxyPalette()
    val iconSize = when (settings.bottomNavScale) {
        0 -> 21.dp
        2 -> 29.dp
        else -> 25.dp
    }
    val navHeight = when (settings.bottomNavScale) {
        0 -> 68.dp
        2 -> 88.dp
        else -> 78.dp
    }
    var showPlayerSheet by remember { mutableStateOf(false) }
    var showAccountSheet by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.background,
        topBar = {
            if (currentRoute in bottomDestinations.map { it.route }) {
                MetroTopBar(
                    title = if (currentRoute == "home") "FoxyMusic" else bottomDestinations.first { it.route == currentRoute }.label,
                    showActions = settings.showTopActions,
                    onHistory = { navController.navigateSingleTop("history") },
                    onStats = { navController.navigateSingleTop("stats") },
                    onTogether = { navController.navigateSingleTop("settings_player") },
                    onProfile = { showAccountSheet = true },
                    account = account
                )
            }
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .background(colors.background)
                    .padding(bottom = 6.dp)
            ) {
                PersistentMiniPlayer(
                    state = playerState,
                    onOpen = { showPlayerSheet = true },
                    onArtist = { navController.navigateSingleTop("history") },
                    onAdd = { navController.navigateSingleTop("library") }
                )
                NavigationBar(
                    containerColor = colors.background,
                    tonalElevation = 0.dp,
                    modifier = Modifier.height(navHeight)
                ) {
                    bottomDestinations.forEach { destination ->
                        NavigationBarItem(
                            selected = currentRoute == destination.route,
                            onClick = { navController.navigateSingleTop(destination.route) },
                            icon = { Icon(destination.icon, contentDescription = destination.label, modifier = Modifier.size(iconSize)) },
                            label = if (settings.showBottomLabels) {
                                {
                                    Text(
                                        destination.label,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = if (settings.bottomNavScale == 0) 11.sp else 13.sp
                                    )
                                }
                            } else {
                                null
                            },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = Color.White,
                                selectedTextColor = Color.White,
                                indicatorColor = colors.accent.copy(alpha = 0.42f),
                                unselectedIconColor = colors.muted,
                                unselectedTextColor = colors.muted
                            )
                        )
                    }
                }
            }
        }
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier.padding(paddingValues)
        ) {
            composable("home") { HomeScreen(onPlayAll = { navController.navigateSingleTop("search") }) }
            composable("search") { SearchScreen() }
            composable("library") { LibraryScreen(navController) }
            composable("profile") { ProfileScreen(navController) }
            composable("history") { HistoryScreen(navController) }
            composable("stats") { StatsScreen(navController) }
            composable("downloads") { DownloadsScreen(navController) }
            composable("settings") { SettingsScreen() }
            composable("login") { LoginScreen(onBack = { navController.popBackStack() }) }
            composable("settings_hub") { SettingsHubScreen(navController) }
            composable("settings_player") { PlayerAudioScreen(navController) }
            composable("appearance") { AppearanceScreen(navController) }
            composable("storage") { StorageScreen(navController) }
            composable("updater") { UpdaterScreen(navController) }
            composable("about") { AboutScreen(navController) }
        }
    }

    if (showPlayerSheet) {
        FullPlayerSheet(
            state = playerState,
            onDismiss = { showPlayerSheet = false }
        )
    }

    if (showAccountSheet) {
        AccountDialog(
            onDismiss = { showAccountSheet = false },
            account = account,
            onLogin = {
                showAccountSheet = false
                navController.navigateSingleTop("login")
            },
            onLogout = {
                FoxyAccount.signOut()
                showAccountSheet = false
            },
            onSettings = {
                showAccountSheet = false
                navController.navigateSingleTop("settings")
            },
            onAbout = {
                showAccountSheet = false
                navController.navigateSingleTop("about")
            }
        )
    }
}

@Composable
private fun MetroTopBar(
    title: String,
    showActions: Boolean,
    onHistory: () -> Unit,
    onStats: () -> Unit,
    onTogether: () -> Unit,
    onProfile: () -> Unit,
    account: FoxyAccountState
) {
    val colors = foxyPalette()
    val settings by FoxySettings.state.collectAsState()
    val iconSize = when (settings.iconScale) {
        0 -> 24.dp
        2 -> 32.dp
        else -> 28.dp
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(horizontal = 22.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
            Text(dynamicGreeting(), color = colors.muted, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
        if (showActions) {
            MetroTopIcon(Icons.Rounded.History, "History", iconSize, onHistory)
            MetroTopIcon(Icons.Rounded.TrendingUp, "Stats", iconSize, onStats)
            MetroTopIcon(Icons.Rounded.Groups, "Listen Together", iconSize, onTogether)
        }
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(CircleShape)
                .background(Color(0xFFE8E8E8))
                .clickable { onProfile() },
            contentAlignment = Alignment.Center
        ) {
            if (account.avatarUrl.isNotBlank()) {
                AsyncImage(
                    model = account.avatarUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(38.dp)
                )
            } else {
                Text(account.displayName.initials(), color = Color(0xFFB78112), fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
            }
        }
    }
}

private fun dynamicGreeting(): String {
    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
    return when (hour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Late night mode"
    }
}

@Composable
private fun MetroTopIcon(icon: ImageVector, label: String, iconSize: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    val colors = foxyPalette()
    IconButton(onClick = onClick, modifier = Modifier.size(44.dp)) {
        Icon(icon, contentDescription = label, tint = colors.muted, modifier = Modifier.size(iconSize))
    }
}

@Composable
private fun AccountDialog(
    onDismiss: () -> Unit,
    account: FoxyAccountState,
    onLogin: () -> Unit,
    onLogout: () -> Unit,
    onSettings: () -> Unit,
    onAbout: () -> Unit
) {
    val colors = foxyPalette()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surfaceHigh,
        titleContentColor = Color.White,
        textContentColor = Color.White,
        shape = RoundedCornerShape(28.dp),
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("FoxyMusic", modifier = Modifier.weight(1f), fontWeight = FontWeight.ExtraBold)
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                }
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(22.dp))
                        .background(colors.surface)
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier.size(54.dp).clip(CircleShape).background(Color.White),
                        contentAlignment = Alignment.Center
                    ) {
                        if (account.avatarUrl.isNotBlank()) {
                            AsyncImage(
                                model = account.avatarUrl,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(54.dp)
                            )
                        } else {
                            Text(account.displayName.initials(), color = Color(0xFFB78112), fontWeight = FontWeight.ExtraBold)
                        }
                    }
                    Spacer(modifier = Modifier.width(14.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(account.displayName, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Text(
                            if (account.isSignedIn) account.email.ifBlank { "Personalized YouTube Music is active" } else "Connect for personalized recommendations",
                            color = colors.muted,
                            fontSize = 12.sp
                        )
                    }
                    MetroChip(if (account.isSignedIn) "Log out" else "Log in", onClick = if (account.isSignedIn) onLogout else onLogin)
                }
                MetroIconTile(Icons.Rounded.Sync, "Personal recommendations", if (account.isSignedIn) "Using your YouTube Music session" else "Sign in to unlock account recommendations", onClick = if (account.isSignedIn) ({}) else onLogin)
                MetroIconTile(Icons.Rounded.Sync, "Library sync foundation", "Session is stored locally for future playlist and library sync")
                MetroIconTile(Icons.Rounded.Settings, "Settings", onClick = onSettings)
                MetroIconTile(Icons.Rounded.Info, "About", onClick = onAbout)
            }
        },
        confirmButton = {}
    )
}

private fun NavController.navigateSingleTop(route: String) {
    navigate(route) {
        launchSingleTop = true
        restoreState = true
        popUpTo(graph.startDestinationId) {
            saveState = true
        }
    }
}

private fun String.initials(): String {
    val pieces = trim().split(" ").filter { it.isNotBlank() }
    return pieces.take(2).joinToString("") { it.first().uppercaseChar().toString() }.ifBlank { "FM" }
}
