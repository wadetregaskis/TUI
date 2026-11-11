//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEffectsDemo+Underline.swift
//
//  Two underline sweeps: one a letter at a time, and one gliding from word to
//  word, stretching to reach the next and drawing its tail in after it (the
//  owner's afternoon list, 2026-10-28, #5.4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// An underline drawn along the text a letter at a time, then taken back.
struct LetterSweep: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = glyphs(of: layout)
        // Out and back, fifteen letters a second, with a pause at each end.
        let count = all.count + 4
        let step = Int(time * 15) % (count * 2)
        let reached = min(all.count, step < count ? step : count * 2 - step - 1)
        for (index, glyph) in all {
            var swept = ctx
            swept.textAttributes.underline = index < reached
            swept.draw(glyph)
        }
    }
}

/// An underline under one word at a time, gliding to the next: its leading
/// end runs ahead to the next word's end, the line stretching to span both,
/// then its trailing end follows to the next word's start, the line shrinking
/// to that word. Across the words and back.
struct WordGlide: TextRenderer {
    var time: Double
    let text: [Character]
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// Seconds a glide from one word to the next takes, its pause included.
    private static let stride = 0.9

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        underlineWords(layout: layout, text: text, in: &ctx) { words in Self.span(of: words, at: time) }
    }

    /// The cells underlined `time` seconds in, of `words` (two or more).
    static func span(of words: [Range<Int>], at time: Double) -> Range<Int> {
        let leg = UnderlineLeg(words: words, time: time, stride: stride)
        // A third of the leg resting, a third for each end.
        let head = UnderlineLeg.eased((leg.progress - 1.0 / 3) * 3)
        let tail = UnderlineLeg.eased((leg.progress - 2.0 / 3) * 3)
        let forward = leg.to > leg.from
        // The end that leads moves first: the right one going right.
        let start = UnderlineLeg.lerp(words[leg.from].lowerBound, words[leg.to].lowerBound, forward ? tail : head)
        let end = UnderlineLeg.lerp(words[leg.from].upperBound, words[leg.to].upperBound, forward ? head : tail)
        return start..<max(start, end)
    }
}

/// Draws `layout`'s glyphs with those `span` picks, from the words of `text`,
/// underlined; plain where the text has fewer than two words to move between.
private func underlineWords(
    layout: Text.Layout, text: [Character], in ctx: inout GraphicsContext,
    span: ([Range<Int>]) -> Range<Int>
) {
    let all = glyphs(of: layout)
    let words = UnderlineLeg.words(all.map { character(of: $0.glyph, in: text, layout: layout) })
    guard words.count > 1 else {
        for (_, glyph) in all { ctx.draw(glyph) }
        return
    }
    let underlined = span(words)
    for (index, glyph) in all {
        var swept = ctx
        swept.textAttributes.underline = underlined.contains(index)
        swept.draw(glyph)
    }
}

/// Which two words an underline is moving between, and how far through the
/// move it is: the words visited in turn, out and back (0, 1, 2, 1, 0, 1, …),
/// one leg every `stride` seconds.
struct UnderlineLeg {
    /// The word it leaves.
    let from: Int
    /// The word it moves to.
    let to: Int
    /// How far through the leg, 0 to 1.
    let progress: Double

    init(words: [Range<Int>], time: Double, stride: Double) {
        let legs = (words.count - 1) * 2
        let leg = Int(time / stride) % legs
        from = leg < words.count - 1 ? leg : legs - leg
        to = leg < words.count - 1 ? leg + 1 : legs - leg - 1
        progress = (time / stride).truncatingRemainder(dividingBy: 1)
    }

    /// Each word's glyphs, by index, from the text's characters: a word is a
    /// run of non-blanks.
    static func words(_ characters: [Character?]) -> [Range<Int>] {
        var words: [Range<Int>] = []
        var start: Int?
        for (index, character) in characters.enumerated() {
            let blank = character?.isWhitespace ?? true
            if blank, let begun = start {
                words.append(begun..<index)
                start = nil
            } else if !blank, start == nil {
                start = index
            }
        }
        if let start { words.append(start..<characters.count) }
        return words
    }

    /// `fraction`, clamped to 0…1 and eased in and out.
    static func eased(_ fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// The cell `fraction` of the way from `from` to `to`, rounded.
    static func lerp(_ from: Int, _ to: Int, _ fraction: Double) -> Int {
        Int((Double(from) + Double(to - from) * fraction).rounded())
    }
}
