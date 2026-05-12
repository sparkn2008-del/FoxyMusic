import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import coil.compose.AsyncImage
import androidx.compose.ui.res.painterResource

@Composable
fun TrackArtwork(
    song: Song?,                    // Keep nullable for safety
    modifier: Modifier = Modifier,
    onClick: () -> Unit = {}
) {
    val colors = foxyColors()
    
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(enabled = onClick != {}, onClick = onClick)
            .background(colors.pill, RoundedCornerShape(12.dp)),
        contentAlignment = Alignment.Center
    ) {
        AsyncImage(
            model = song?.thumbnail ?: "",
            contentDescription = song?.title,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
            placeholder = painterResource(id = R.drawable.placeholder), // optional
            error = painterResource(id = R.drawable.placeholder)
        )
        
        // Optional overlay for better visuals
        if (song == null) {
            Icon(
                imageVector = Icons.Rounded.MusicNote,
                contentDescription = null,
                tint = colors.muted.copy(alpha = 0.6f),
                modifier = Modifier.size(28.dp)
            )
        }
    }
}