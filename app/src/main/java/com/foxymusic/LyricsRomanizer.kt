package com.foxymusic

import android.icu.text.Transliterator

/**
 * SimpMusic-style "lyrics in English alphabets" — romanize non-Latin script to Latin.
 */
object LyricsRomanizer {

    private val toLatin: Transliterator? by lazy {
        runCatching {
            Transliterator.getInstance("Any-Latin; NFD; [:Nonspacing Mark:] Remove; NFC; Latin-ASCII")
        }.getOrNull()
    }

    fun romanizeLine(text: String, enabled: Boolean): String {
        if (!enabled || text.isBlank()) return text
        if (text.none { Character.UnicodeBlock.of(it) !in latinBlocks }) return text
        val transliterator = toLatin ?: return text
        return runCatching {
            synchronized(transliterator) {
                transliterator.transliterate(text)
                    .replace(Regex("\\s+"), " ")
                    .trim()
            }
        }.getOrDefault(text)
    }

    private val latinBlocks = setOf(
        Character.UnicodeBlock.BASIC_LATIN,
        Character.UnicodeBlock.LATIN_1_SUPPLEMENT,
        Character.UnicodeBlock.LATIN_EXTENDED_A,
        Character.UnicodeBlock.LATIN_EXTENDED_B,
        Character.UnicodeBlock.GENERAL_PUNCTUATION,
    )
}
