//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RestatingAfterResetsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// `ANSIRenderer.restating(_:afterResetsIn:)` replaces a two-step
/// `splittingCollapsedResets(…).replacing(reset, with: reset + restore)`;
/// this pins the one-pass form byte-equal to the two-step one on every shape
/// the writer sees, including the overlapping ones (`ESC[0;0m`, a reset at
/// the very end, a split whose remainder is itself a reset).
@Suite("Restating a background after resets equals the two-step rewrite")
struct RestatingAfterResetsTests {

    private static func twoStep(_ restore: String, in string: String) -> String {
        ANSIRenderer.splittingCollapsedResets(string).replacing(ANSIRenderer.reset, with: ANSIRenderer.reset + restore)
    }

    @Test("Hand-picked shapes")
    func shapes() {
        let bg = "\u{1B}[44m"
        for line in [
            "plain", "", "\u{1B}[0m", "a\u{1B}[0mb", "\u{1B}[0;31mred\u{1B}[0m",
            "\u{1B}[0;0m", "\u{1B}[0;0;31mx", "\u{1B}[31m\u{1B}[0m\u{1B}[0m", "x\u{1B}[0;",
            "\u{1B}[0", "\u{1B}[", "\u{1B}", "\u{1B}[1;0mA", "\u{1B}[0;1;0;44mB\u{1B}[0m",
            "\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\ \u{1B}[0m", "wide \u{1F600}\u{1B}[0m ok",
        ] {
            #expect(ANSIRenderer.restating(bg, afterResetsIn: line) == Self.twoStep(bg, in: line), "\(line.debugDescription)")
        }
        #expect(ANSIRenderer.restating("", afterResetsIn: "\u{1B}[0m") == "\u{1B}[0m")
    }

    @Test("Randomised runs over the writer's alphabet")
    func randomised() {
        var state: UInt64 = 0xC0FFEE
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33)
        }
        let alphabet = ["\u{1B}[0m", "\u{1B}[0;", "\u{1B}[31m", "\u{1B}[0;44m", "0m", ";", "text", " ", "\u{1B}[", "\u{1B}", "m", "0"]
        for _ in 0..<2000 {
            let length = next() % 9
            let line = (0..<length).map { _ in alphabet[next() % alphabet.count] }.joined()
            for restore in ["\u{1B}[44m", "\u{1B}[2m"] {
                #expect(ANSIRenderer.restating(restore, afterResetsIn: line) == Self.twoStep(restore, in: line), "\(line.debugDescription)")
            }
        }
    }

    /// The persistent wrappers write their opening, the restated line, the
    /// padding and the closing into one buffer
    /// (`ANSIRenderer.wrapping(_:restoring:opening:padding:closing:)`); this pins
    /// that to the pieces concatenated — the form they had — and the padding to
    /// wrapping a line already padded, on the same randomised lines.
    @Test("A persistent background, dim or reversal, padded or not, is its pieces concatenated")
    func wrappersArePieces() {
        var state: UInt64 = 0xBEEF
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33)
        }
        let alphabet = ["\u{1B}[0m", "\u{1B}[0;", "\u{1B}[31m", "\u{1B}[0;44m", "0m", ";", "text", " ", "\u{1B}[", "\u{1B}", "m", "0", "\u{1F600}"]
        let reset = ANSIRenderer.reset
        let ink = Color.rgb(200, 210, 220)
        let field = Color.rgb(10, 20, 30)
        let opening = String(ANSIRenderer.applyPersistentReverse("", ink: ink, field: field).dropLast(reset.count))
        for _ in 0..<2000 {
            let line = (0..<(next() % 9)).map { _ in alphabet[next() % alphabet.count] }.joined()
            let padding = next() % 4
            let padded = line + String(repeating: " ", count: padding)
            for fill in [Color.rgb(40, 50, 60), .palette256(236), .ansi(.blue)] {
                let code = fill.backgroundEscape()
                #expect(ANSIRenderer.applyPersistentBackground(line, color: fill) == code + Self.twoStep(code, in: line), "\(line.debugDescription)")
                #expect(
                    ANSIRenderer.applyPersistentBackground(line, color: fill, padding: padding)
                        == ANSIRenderer.applyPersistentBackground(padded, color: fill), "\(line.debugDescription)")
            }
            #expect(ANSIRenderer.applyPersistentDim(line) == ANSIRenderer.dim + Self.twoStep(ANSIRenderer.dim, in: line) + reset, "\(line.debugDescription)")
            #expect(
                ANSIRenderer.applyPersistentReverse(line, ink: ink, field: field)
                    == opening + Self.twoStep(opening, in: line) + reset, "\(line.debugDescription)")
            #expect(
                ANSIRenderer.applyPersistentReverse(line, ink: ink, field: field, padding: padding)
                    == ANSIRenderer.applyPersistentReverse(padded, ink: ink, field: field), "\(line.debugDescription)")
        }
    }

    /// `ANSIRenderer.backgroundCode(for:)` spells the sequence through its own
    /// writer rather than `Color.backgroundEscape()`; the two must not differ at
    /// any depth.
    @Test("A background code is the colour's own background escape, at every depth")
    func backgroundCodeIsTheEscape() {
        let colours: [Color] = [.rgb(1, 2, 3), .rgb(255, 255, 255), .palette256(17), .ansi(.red), .ansi(.brightWhite), .default]
        for depth in [ColorDepth.truecolor, .palette256, .basic16, .noColor] {
            ColorDepth.withCurrent(depth) {
                for colour in colours {
                    #expect(ANSIRenderer.backgroundCode(for: colour) == colour.backgroundEscape(), "\(colour) at \(depth)")
                }
            }
        }
    }
}
