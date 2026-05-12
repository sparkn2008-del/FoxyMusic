package com.foxymusic

import androidx.compose.ui.graphics.Color

data class MetroFeature(
    val title: String,
    val subtitle: String,
    val color: Color
)

data class SearchSuggestion(
    val label: String,
    val query: String
)

val trendingCharts = listOf(
    MetroFeature("India Top 50", "Fresh chart picks", Color(0xFFFF7A3D)),
    MetroFeature("Global Hits", "Songs moving everywhere", Color(0xFF57D6B2)),
    MetroFeature("Viral Mix", "Fast-rising tracks", Color(0xFF8EA7FF))
)

val genreShelves = listOf(
    MetroFeature("Pop", "Bright hooks", Color(0xFFFFB86B)),
    MetroFeature("Hip-Hop", "New drops", Color(0xFFE77CA6)),
    MetroFeature("Electronic", "Late-night energy", Color(0xFF5AD7FF)),
    MetroFeature("Indie", "Soft discoveries", Color(0xFFB8E986))
)

val quickSearchSuggestions = listOf(
    SearchSuggestion("Arijit Singh", "Arijit Singh"),
    SearchSuggestion("Lo-fi Hindi", "lofi hindi"),
    SearchSuggestion("Workout mix", "workout mix"),
    SearchSuggestion("A.R. Rahman", "A R Rahman"),
    SearchSuggestion("Trending now", "trending songs")
)

val offlineFeatureStates = listOf(
    MetroFeature("Smart downloads", "Save songs for offline playback", Color(0xFFFF7A3D)),
    MetroFeature("Backup settings", "Export preferences and library data", Color(0xFF57D6B2)),
    MetroFeature("Cloud sync", "Keep playlists available across devices", Color(0xFF8EA7FF))
)
