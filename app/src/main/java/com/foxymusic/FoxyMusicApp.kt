package com.foxymusic

import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
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

/** Home, Search, Library, and Me (profile hub). */
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
        0 -> 22.dp
        2 -> 28.dp
        else -> 25.dp
    }
    val navHeight = when (settings.bottomNavScale) {
        0 -> 62.dp
        2 -> 78.dp
        else -> 70.dp
    }
    var showPlayerSheet by remember { mutableStateOf(false) }
    var showAccountSheet by remember { mutableStateOf(false) }

    val navFadeTween = tween<Float>(durationMillis = 260)
    val navSlideTween = tween<IntOffset>(durationMillis = 260)

    Scaffold(
        containerColor = colors.background,
        topBar = {
            when (currentRoute) {
                "home" -> HomeActionsBar(
                    onSearch = { navController.navigatePrimary("search") },
                    onProfile = { showAccountSheet = true },
                    account = account
                )
                "search" -> SimpTopBar(
                    title = "Search",
                    subtitle = "YouTube Music catalog",
                    showSearchAction = false,
                    onSearch = { },
                    onProfile = { showAccountSheet = true },
                    account = account
                )
                "library" -> SimpTopBar(
                    title = "Library",
                    subtitle = "Liked, saved, and offline",
                    showSearchAction = true,
                    onSearch = { navController.navigatePrimary("search") },
                    onProfile = { showAccountSheet = true },
                    account = account
                )
                "profile" -> SimpTopBar(
                    title = "Me",
                    subtitle = "Profile, discovery, and account",
                    showSearchAction = true,
                    onSearch = { navController.navigatePrimary("search") },
                    onProfile = { showAccountSheet = true },
                    account = account
                )
            }
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .background(color = colors.background)
                    .padding(bottom = 4.dp)
            ) {
                PersistentMiniPlayer(
                    state = playerState,
                    onOpen = { showPlayerSheet = true }
                )
                Surface(
                    color = colors.surface.copy(alpha = 0.94f),
                    tonalElevation = 0.dp,
                    shadowElevation = 0.dp,
                    shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
                ) {
                    NavigationBar(
                        containerColor = Color.Transparent,
                        tonalElevation = 0.dp,
                        modifier = Modifier.height(navHeight)
                    ) {
                        bottomDestinations.forEach { destination ->
                            NavigationBarItem(
                                selected = currentRoute == destination.route,
                                onClick = { navController.navigatePrimary(destination.route) },
                                icon = {
                                    Icon(
                                        destination.icon,
                                        contentDescription = destination.label,
                                        modifier = Modifier.size(iconSize)
                                    )
                                },
                                label = if (settings.showBottomLabels) {
                                    {
                                        Text(
                                            destination.label,
                                            fontWeight = FontWeight.SemiBold,
                                            fontSize = if (settings.bottomNavScale == 0) 11.sp else 12.sp
                                        )
                                    }
                                } else {
                                    null
                                },
                                colors = NavigationBarItemDefaults.colors(
                                    selectedIconColor = colors.accent,
                                    selectedTextColor = colors.accent,
                                    indicatorColor = colors.accent.copy(alpha = 0.18f),
                                    unselectedIconColor = colors.muted,
                                    unselectedTextColor = colors.muted
                                )
                            )
                        }
                    }
                }
            }
        }
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier.padding(paddingValues),
            enterTransition = {
                fadeIn(animationSpec = navFadeTween) +
                    slideInHorizontally(animationSpec = navSlideTween) { w -> w / 10 }
            },
            exitTransition = {
                fadeOut(animationSpec = navFadeTween) +
                    slideOutHorizontally(animationSpec = navSlideTween) { w -> -w / 14 }
            },
            popEnterTransition = {
                fadeIn(animationSpec = navFadeTween) +
                    slideInHorizontally(animationSpec = navSlideTween) { w -> -w / 14 }
            },
            popExitTransition = {
                fadeOut(animationSpec = navFadeTween) +
                    slideOutHorizontally(animationSpec = navSlideTween) { w -> w / 10 }
            }
        ) {
            composable("home") {
                HomeScreen(
                    onPlayAll = { navController.navigatePrimary("search") },
                    onSongPlay = { showPlayerSheet = true }
                )
            }
            composable("search") { SearchScreen(onSongPlay = { showPlayerSheet = true }) }
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
            onProfile = {
                showAccountSheet = false
                navController.navigateSecondary("profile")
            },
            onLogin = {
                showAccountSheet = false
                navController.navigateSecondary("login")
            },
            onLogout = {
                FoxyAccount.signOut()
                showAccountSheet = false
            },
            onSettings = {
                showAccountSheet = false
                navController.navigateSecondary("settings")
            },
            onAbout = {
                showAccountSheet = false
                navController.navigateSecondary("about")
            }
        )
    }
}

@Composable
private fun HomeActionsBar(
    onSearch: () -> Unit,
    onProfile: () -> Unit,
    account: FoxyAccountState
) {
    val colors = foxyPalette()
    val settings by FoxySettings.state.collectAsState()
    val iconSize = when (settings.iconScale) {
        0 -> 24.dp
        2 -> 30.dp
        else -> 27.dp
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(color = colors.background)
            .statusBarsPadding()
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Spacer(modifier = Modifier.weight(1f))
        SimpTopIcon(Icons.Rounded.Search, "Search", iconSize, onSearch)
        Spacer(modifier = Modifier.width(4.dp))
        ProfileAvatar(account = account, size = 38.dp, onClick = onProfile)
    }
}

@Composable
private fun SimpTopBar(
    title: String,
    subtitle: String?,
    showSearchAction: Boolean,
    onSearch: () -> Unit,
    onProfile: () -> Unit,
    account: FoxyAccountState
) {
    val colors = foxyPalette()
    val settings by FoxySettings.state.collectAsState()
    val iconSize = when (settings.iconScale) {
        0 -> 24.dp
        2 -> 30.dp
        else -> 27.dp
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(color = colors.background)
            .statusBarsPadding()
            .padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
            if (!subtitle.isNullOrBlank()) {
                Text(subtitle, color = colors.muted, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
        if (showSearchAction) {
            SimpTopIcon(Icons.Rounded.Search, "Search", iconSize, onSearch)
            Spacer(modifier = Modifier.width(4.dp))
        }
        ProfileAvatar(account = account, size = 38.dp, onClick = onProfile)
    }
}

@Composable
private fun ProfileAvatar(
    account: FoxyAccountState,
    size: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(Color(0xFF2A2A2A))
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        if (account.avatarUrl.isNotBlank()) {
            AsyncImage(
                model = account.avatarUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size)
            )
        } else {
            Text(
                account.displayName.initials(),
                color = foxyPalette().accent,
                fontSize = (size.value / 3.2f).sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun SimpTopIcon(icon: ImageVector, label: String, iconSize: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    val colors = foxyPalette()
    IconButton(onClick = onClick, modifier = Modifier.size(44.dp)) {
        Icon(icon, contentDescription = label, tint = colors.muted, modifier = Modifier.size(iconSize))
    }
}

@Composable
private fun AccountDialog(
    onDismiss: () -> Unit,
    account: FoxyAccountState,
    onProfile: () -> Unit,
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
                        .background(color = colors.surface)
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier.size(54.dp).clip(CircleShape).background(Color(0xFF2A2A2A)),
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
                            Text(account.displayName.initials(), color = colors.accent, fontWeight = FontWeight.ExtraBold)
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
                MetroIconTile(Icons.Rounded.Person, "Profile & discovery", "Charts, moods, and your listening hub", onClick = onProfile)
                MetroIconTile(
                    Icons.Rounded.Sync,
                    "Recommendations & library",
                    if (account.isSignedIn) "Using your YouTube Music session for Home and future sync" else "Sign in for personalized Home and synced library features",
                    onClick = if (account.isSignedIn) ({}) else onLogin
                )
                MetroIconTile(Icons.Rounded.Settings, "Settings", onClick = onSettings)
                MetroIconTile(Icons.Rounded.Info, "About", onClick = onAbout)
            }
        },
        confirmButton = {}
    )
}

/** Bottom tabs: switch without stacking duplicate entries. */
private fun NavController.navigatePrimary(route: String) {
    navigate(route) {
        launchSingleTop = true
        restoreState = true
        popUpTo(graph.startDestinationId) {
            saveState = true
        }
    }
}

/** Secondary screens keep back stack so the system back button returns to the previous tab. */
private fun NavController.navigateSecondary(route: String) {
    navigate(route) {
        launchSingleTop = true
    }
}

private fun String.initials(): String {
    val pieces = trim().split(" ").filter { it.isNotBlank() }
    return pieces.take(2).joinToString("") { it.first().uppercaseChar().toString() }.ifBlank { "FM" }
}
