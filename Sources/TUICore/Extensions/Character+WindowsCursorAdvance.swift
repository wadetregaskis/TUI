//  🖥️ TUI — A Terminal UI framework for Swift
//  Character+WindowsCursorAdvance.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Windows Terminal

extension Character {
    /// The number of columns **Windows Terminal** advances the cursor by when
    /// this character is printed, as far as a CUF can repair it (DSR-measured in
    /// 1.24.12741.0 on both screens, 2026-11-16,
    /// `windows-terminal-1.24.12741.0-advance.json` and `-alternate.json`):
    ///
    /// - **Bare SMP pictographs** (🖥 🛡 🕹 without a selector): 1, against a
    ///   2-cell claim. It paints them two cells wide, over the cell after.
    /// - **A lone regional indicator**: 1, against 2.
    /// - **Plane-16 PUA (SF Symbols)**: 1, against 2.
    /// - Everything else, ZWJ sequences and skin tones included: the claim. It
    ///   clusters graphemes (DEC mode 2027, which it reports permanently set),
    ///   composes ZWJ sequences, merges skin tones and advances a Devanagari
    ///   conjunct by its cluster, as TUI's composing traits price them.
    ///
    /// One class over-advances, which no forward movement can repair, so it
    /// reads as the claim here: the invisible format characters — LRM, RLM,
    /// U+2060…2064 and the Mongolian vowel separator — advance 1 against 0.
    public var windowsTerminalCursorAdvance: Int {
        let claim = terminalWidth
        guard claim == 2 else { return claim }
        if isLoneRegionalIndicator || isBarePictographUnderAdvancer { return 1 }
        if unicodeScalars.count == 1, let only = unicodeScalars.first, Self.isPlaneSixteenGlyph(only.value) {
            return 1
        }
        return claim
    }
}

// MARK: - The classic console (conhost)

extension Character {
    /// How many columns the **classic Windows console** (conhost) moves the
    /// cursor over this character, whether or not a CUF could repair it
    /// (DSR-measured on build 26300, both screens, 2026-11-16,
    /// `conhost-10.0.26300-advance.json` and `-alternate.json`).
    ///
    /// conhost clusters nothing and has no zero width: **every code point
    /// takes a cell, and two when it is wide**. A combining accent, a virama, a
    /// variation selector, a ZWJ and a bidi mark each take one; a regional
    /// indicator and a skin-tone swatch two. Its width table is TUI's, but
    /// for two classes it gives one cell: a bare SMP pictograph (`Emoji=Yes`,
    /// `Emoji_Presentation=No`), and the emoji added in Unicode 16.
    public var windowsConsoleCells: Int {
        unicodeScalars.reduce(0) { $0 + Self.windowsConsoleCells(of: $1) }
    }

    private static func windowsConsoleCells(of scalar: Unicode.Scalar) -> Int {
        let alone = Character(scalar)
        if alone.isBarePictographUnderAdvancer || alone.isUnicode16EmojiOlderTablesMiss { return 1 }
        return alone.terminalWidth >= 2 ? 2 : 1
    }

    /// What the classic console advances this character by, as far as a CUF
    /// can repair it: ``windowsConsoleCells`` where that falls short of the
    /// claim, and the claim where it does not.
    ///
    /// The shortfalls are the bare SMP pictographs and Unicode 16's emoji,
    /// one cell against two. Everything conhost moves further than the claim —
    /// a combining mark's cell, a virama's, a ZWJ's, a variation selector's —
    /// no forward movement can take back, so it reads as the claim here;
    /// ``windowsConsoleRespelling`` sends a different spelling where one fits.
    /// The traits (``TerminalWidthTraits/textClusters`` per code point,
    /// joiners dropped, tones detached) are what bring most of the rest into
    /// line: what remains over is a mark that composes with nothing.
    public var windowsConsoleCursorAdvance: Int {
        min(windowsConsoleCells, terminalWidth)
    }

    /// A spelling of this character that the classic console advances exactly
    /// as far as TUI claims for it, where this one goes further — or `nil`
    /// where this one does not, or nothing does.
    ///
    /// Two rewrites, which change no glyph conhost draws:
    ///
    /// - A **variation selector after a base it already draws wide** goes:
    ///   `⬛︎` is sent as `⬛`, `〰️` as `〰`. conhost draws no colour emoji,
    ///   so the selector chooses nothing, and costs a cell.
    /// - The character is **composed** (NFC): an `e` and a combining acute is
    ///   sent as `é`, one cell rather than two.
    ///
    /// Accepted only when the result is still one character whose claim is
    /// this one's and which conhost advances exactly that far, so the layout
    /// and the rest of the walk see the same cells either way.
    public var windowsConsoleRespelling: Character? {
        let claim = terminalWidth
        guard windowsConsoleCells > claim else { return nil }
        var kept = String.UnicodeScalarView()
        var previousIsWide = false
        for scalar in unicodeScalars {
            let isSelector = scalar.value == 0xFE0E || scalar.value == 0xFE0F
            if isSelector, previousIsWide { continue }
            kept.append(scalar)
            previousIsWide = Self.windowsConsoleCells(of: scalar) == 2
        }
        let composed = String(kept).precomposedStringWithCanonicalMapping
        // Compared by scalar: `Character`'s `==` is canonical equivalence, by
        // which `é` and `e` + U+0301 are one character.
        guard composed.count == 1, let candidate = composed.first,
            !candidate.unicodeScalars.elementsEqual(unicodeScalars),
            candidate.terminalWidth == claim, candidate.windowsConsoleCells == claim
        else { return nil }
        return candidate
    }
}
