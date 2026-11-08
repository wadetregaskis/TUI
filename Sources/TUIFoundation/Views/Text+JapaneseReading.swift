//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+JapaneseReading.swift
//
//  Japanese read as Japanese when text is spelled in ASCII
//  (`TUI_PLAIN_TEXT=transliterate`): ICU's `Any-Latin` reads every Han
//  character as Chinese, so `日本語` came out `ri ben yu`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIView

/// Kanji read as Japanese, in romaji, where the words are Japanese.
///
/// Darwin's `CFStringTokenizer` gives a Latin transcription per word and knows
/// kanji readings in its Japanese locale (`日本語` `nippon go`, `東京へ行きます`
/// `toukyou he iki masu`). Elsewhere there is no such reader, so Japanese goes
/// to ICU like everything else: its kana are right (`こんにちは`
/// `kon'nichiha`) and its kanji are read as Chinese.
enum JapaneseReading {
    /// Whether `string` is read as Japanese: it has kana in it, which only
    /// Japanese writes, or Han in it and the app's language is Japanese. A
    /// Han-only string in any other app is read as Chinese: nothing in the
    /// characters says which it is, and `保存` is `hozon` to one reader and
    /// `bao cun` to the other.
    static func applies(to string: String, reading: TextReading) -> Bool {
        #if canImport(Darwin)
            var hasHan = false
            for scalar in string.unicodeScalars where scalar.value >= 0x3040 {
                if isKana(scalar) { return true }
                if isHan(scalar) { hasHan = true }
            }
            return hasHan && reading == .japanese
        #else
            return false
        #endif
    }

    /// Hiragana and katakana, the halfwidth forms too, and not the katakana
    /// middle dot, which Chinese text uses as well.
    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30FB: false
        case 0x3041...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D: true
        default: false
        }
    }

    /// The CJK ideographs: the unified block, extension A, the compatibility
    /// block, and the supplementary planes' extensions.
    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3134F: true
        default: false
        }
    }

    /// `string` with each Japanese word in romaji, a space between two words
    /// that had none, and everything the tokenizer has no reading for — a word
    /// it doesn't know, punctuation, other scripts — as it was, for ICU after.
    ///
    /// The space because Japanese is written without them and romaji with
    /// them: `nippongo` and `toukyouheikimasu` are hard to read. The
    /// tokenizer's words are finer than a dictionary's (`iki masu`), which
    /// reads better than none.
    static func romanized(_ string: String) -> String {
        #if canImport(Darwin)
            let text = string as NSString
            let tokenizer = CFStringTokenizerCreate(
                nil, text as CFString, CFRange(location: 0, length: text.length),
                kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
            var romanized = ""
            var position = 0
            var lastWasReading = false
            while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                if range.location > position {
                    romanized += text.substring(with: NSRange(location: position, length: range.location - position))
                    lastWasReading = false
                }
                let word = text.substring(with: NSRange(location: range.location, length: range.length))
                let reading = CFStringTokenizerCopyCurrentTokenAttribute(
                    tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
                if let reading, !reading.isEmpty, reading != word {
                    if lastWasReading { romanized += " " }
                    romanized += reading
                    lastWasReading = true
                } else {
                    romanized += word
                    lastWasReading = false
                }
                position = range.location + range.length
            }
            if position < text.length { romanized += text.substring(from: position) }
            return romanized
        #else
            return string
        #endif
    }
}
