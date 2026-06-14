package com.foxymusic

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Simple on-device playlists (not synced to YouTube Music).
 */
object FoxyUserPlaylists {

    private var context: Context? = null
    private val playlists = mutableListOf<UserPlaylist>()

    fun init(ctx: Context) {
        context = ctx.applicationContext
        loadLocked()
    }

    fun all(): List<UserPlaylist> = playlists.toList()

    @Synchronized
    fun create(name: String): UserPlaylist {
        val trimmed = name.trim().ifBlank { "New playlist" }
        val pl = UserPlaylist(id = UUID.randomUUID().toString(), name = trimmed, songs = emptyList())
        playlists.add(pl)
        saveLocked()
        return pl
    }

    @Synchronized
    fun rename(playlistId: String, newName: String) {
        val idx = playlists.indexOfFirst { it.id == playlistId }
        if (idx < 0) return
        val n = newName.trim().ifBlank { playlists[idx].name }
        playlists[idx] = playlists[idx].copy(name = n)
        saveLocked()
    }

    @Synchronized
    fun delete(playlistId: String) {
        if (playlists.removeAll { it.id == playlistId }) saveLocked()
    }

    @Synchronized
    fun addSong(playlistId: String, song: Song) {
        val idx = playlists.indexOfFirst { it.id == playlistId }
        if (idx < 0) return
        val cur = playlists[idx]
        if (cur.songs.any { it.videoId == song.videoId }) return
        playlists[idx] = cur.copy(songs = cur.songs + song)
        saveLocked()
    }

    @Synchronized
    fun removeSong(playlistId: String, videoId: String) {
        val idx = playlists.indexOfFirst { it.id == playlistId }
        if (idx < 0) return
        val cur = playlists[idx]
        playlists[idx] = cur.copy(songs = cur.songs.filterNot { it.videoId == videoId })
        saveLocked()
    }

    @Synchronized
    fun moveSong(playlistId: String, fromIndex: Int, toIndex: Int) {
        val idx = playlists.indexOfFirst { it.id == playlistId }
        if (idx < 0) return
        val cur = playlists[idx]
        if (cur.songs.size < 2 || fromIndex !in cur.songs.indices) return
        val target = toIndex.coerceIn(0, cur.songs.lastIndex)
        if (fromIndex == target) return
        val next = cur.songs.toMutableList()
        val moved = next.removeAt(fromIndex)
        next.add(target, moved)
        playlists[idx] = cur.copy(songs = next)
        saveLocked()
    }

    @Synchronized
    fun snapshotJson(): JSONArray {
        val arr = JSONArray()
        for (p in playlists) {
            val o = JSONObject()
            o.put("id", p.id)
            o.put("name", p.name)
            val songs = JSONArray()
            for (s in p.songs) songs.put(songToJson(s))
            o.put("songs", songs)
            arr.put(o)
        }
        return arr
    }

    @Synchronized
    fun restoreFromJson(root: JSONArray) {
        playlists.clear()
        for (i in 0 until root.length()) {
            val o = root.optJSONObject(i) ?: continue
            val id = o.optString("id").ifBlank { UUID.randomUUID().toString() }
            val name = o.optString("name").ifBlank { "Playlist" }
            val songsJson = o.optJSONArray("songs") ?: JSONArray()
            val songs = mutableListOf<Song>()
            for (j in 0 until songsJson.length()) {
                val sm = songsJson.optJSONObject(j) ?: continue
                val song = songFromPlaylistJson(sm) ?: continue
                songs.add(song)
            }
            playlists.add(UserPlaylist(id = id, name = name, songs = songs.distinctBy { it.videoId }))
        }
        saveLocked()
    }

    private fun file(): File {
        val dir = context!!.filesDir
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "user_playlists_v1.json")
    }

    private fun loadLocked() {
        val ctx = context ?: return
        playlists.clear()
        runCatching {
            val f = file()
            if (!f.exists() || f.length() <= 0L) return@runCatching
            val root = JSONArray(f.readText())
            for (i in 0 until root.length()) {
                val o = root.optJSONObject(i) ?: continue
                val id = o.optString("id")
                if (id.isBlank()) continue
                val name = o.optString("name").ifBlank { "Playlist" }
                val songsJson = o.optJSONArray("songs") ?: JSONArray()
                val songs = mutableListOf<Song>()
                for (j in 0 until songsJson.length()) {
                    val sm = songsJson.optJSONObject(j) ?: continue
                    val song = songFromPlaylistJson(sm) ?: continue
                    songs.add(song)
                }
                playlists.add(UserPlaylist(id = id, name = name, songs = songs))
            }
        }
    }

    private fun saveLocked() {
        context ?: return
        runCatching { file().writeText(snapshotJson().toString()) }
    }

    private fun songToJson(s: Song): JSONObject = JSONObject().apply {
        put("videoId", s.videoId)
        put("title", s.title)
        put("artist", s.artist)
        put("thumbnail", s.thumbnail)
        put("artworkUrl", s.artworkUrl ?: "")
        put("duration", s.duration ?: "")
        put("album", s.album ?: "")
        put("isDownloaded", s.isDownloaded)
        if (!s.localPath.isNullOrBlank()) put("localPath", s.localPath)
    }

    private fun songFromPlaylistJson(o: JSONObject): Song? {
        val vid = o.optString("videoId").trim().ifBlank { return null }
        return Song(
            videoId = vid,
            title = o.optString("title").ifBlank { "Unknown title" },
            artist = o.optString("artist").ifBlank { "Unknown artist" },
            thumbnail = o.optString("thumbnail"),
            duration = o.optString("duration").takeIf { it.isNotBlank() },
            album = o.optString("album").takeIf { it.isNotBlank() },
            artworkUrl = o.optString("artworkUrl").takeIf { it.isNotBlank() },
            localPath = o.optString("localPath").takeIf { it.isNotBlank() },
            isDownloaded = o.optBoolean("isDownloaded"),
        )
    }
}

data class UserPlaylist(
    val id: String,
    val name: String,
    val songs: List<Song>,
)
