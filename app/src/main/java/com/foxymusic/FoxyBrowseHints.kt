package com.foxymusic

import androidx.compose.ui.graphics.Color

data class FoxyHighlightCard(
    val title: String,
    val subtitle: String,
    val color: Color
)

data class SearchSuggestion(
    val label: String,
    val query: String
)

val trendingCharts = listOf(
    FoxyHighlightCard("India Top 50", "Fresh chart picks", Color(0xFFFF7A3D)),
    FoxyHighlightCard("Global Hits", "Songs moving everywhere", Color(0xFF57D6B2)),
    FoxyHighlightCard("Viral Mix", "Fast-rising tracks", Color(0xFF8EA7FF))
)

val genreShelves = listOf(
    FoxyHighlightCard("Pop", "Bright hooks", Color(0xFFFFB86B)),
    FoxyHighlightCard("Hip-Hop", "New drops", Color(0xFFE77CA6)),
    FoxyHighlightCard("Electronic", "Late-night energy", Color(0xFF5AD7FF)),
    FoxyHighlightCard("Indie", "Soft discoveries", Color(0xFFB8E986))
)

val quickSearchSuggestions = listOf(
    SearchSuggestion("Arijit Singh", "Arijit Singh"),
    SearchSuggestion("Lo-fi Hindi", "lofi hindi"),
    SearchSuggestion("Workout mix", "workout mix"),
    SearchSuggestion("A.R. Rahman", "A R Rahman"),
    SearchSuggestion("Trending now", "trending songs")
)

val offlineFeatureStates = listOf(
    FoxyHighlightCard("Smart downloads", "Save songs for offline playback", Color(0xFFFF7A3D)),
    FoxyHighlightCard("Backup settings", "Export preferences and library data", Color(0xFF57D6B2)),
    FoxyHighlightCard("Cloud sync", "Keep playlists available across devices", Color(0xFF8EA7FF))
)
