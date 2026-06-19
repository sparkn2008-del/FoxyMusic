package com.foxymusic

import android.icu.text.Transliterator

/**
 * Romanizes non-Latin lyric lines into readable Latin text.
 *
 * Keep this conservative: if ICU cannot produce mostly Latin output, return the
 * original lyric instead of showing broken transliteration.
 */
object LyricsRomanizer {

    private val toLatin: Transliterator? by lazy {
        runCatching {
            Transliterator.getInstance("Any-Latin; Latin-ASCII")
        }.getOrNull()
    }

    fun romanizeLine(text: String, enabled: Boolean): String {
        if (!enabled || text.isBlank()) return text
        if (!text.any { Character.UnicodeBlock.of(it) !in latinBlocks }) return text
        val transliterator = toLatin ?: return text
        val romanized = runCatching {
            synchronized(transliterator) {
                transliterator.transliterate(text)
            }
        }.getOrDefault(text)
            .normalizePunctuation()
            .replace(Regex("\\s+"), " ")
            .trim()
        if (romanized.isBlank()) return text
        return if (romanized.looksReadableLatin()) romanized else text
    }

    private fun String.normalizePunctuation(): String = this
        .replace('’', '\'')
        .replace('‘', '\'')
        .replace('`', '\'')
        .replace('´', '\'')
        .replace('“', '"')
        .replace('”', '"')
        .replace('—', '-')
        .replace('–', '-')

    private fun String.looksReadableLatin(): Boolean {
        val letters = count { it.isLetter() }
        if (letters == 0) return true
        val latinLetters = count {
            it.isLetter() && Character.UnicodeBlock.of(it) in latinBlocks
        }
        return latinLetters.toDouble() / letters >= 0.85
    }

    private val latinBlocks = setOf(
        Character.UnicodeBlock.BASIC_LATIN,
        Character.UnicodeBlock.LATIN_1_SUPPLEMENT,
        Character.UnicodeBlock.LATIN_EXTENDED_A,
        Character.UnicodeBlock.LATIN_EXTENDED_B,
        Character.UnicodeBlock.GENERAL_PUNCTUATION,
    )
}
