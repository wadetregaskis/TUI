//  🖥️ TUI — A Terminal UI framework for Swift
//  RestatingAfterResetsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// `ANSIRenderer.restating(_:afterResetsIn:)` is a one-pass byte walk; this pins
/// it byte-equal to the rule spelled the slow way (``reference(_:in:)``) on every
/// shape the writer sees, including the overlapping ones (`ESC[0;0m`, a reset at
/// the very end, a reset in a later parameter, a colour whose index is 0).
///
/// Until 2026-11-22 the reference was the two-step
/// `splittingCollapsedResets(…).replacing(reset, with: reset + restore)`, which
/// sees only the literal `ESC[0m` and the collapsed `ESC[0;`: a bare `ESC[m` was
/// no reset to it. The walk now reads a reset as `SGRState` does (H-37), so the
/// reference is that rule.
@Suite("Restating a background after resets equals the reference rule")
struct RestatingAfterResetsTests {

    /// The rule the slow way: every SGR sequence holding SGR 0 — an empty or
    /// all-zero parameter, not counting a `;`-form colour's arguments — becomes
    /// `ESC[0m`, `restore`, and the parameters after its last reset as a
    /// sequence of their own; everything else is copied.
    private static func reference(_ restore: String, in string: String) -> String {
        var output = ""
        string.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, isSGR: true):
                let parameters = sequence.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false)
                var lastReset: Int?
                var index = 0
                while index < parameters.count {
                    let parameter = parameters[index]
                    if parameter.allSatisfy({ $0 == "0" }) {
                        lastReset = index
                    } else if let code = Int(parameter), [38, 48, 58].contains(code), index + 1 < parameters.count {
                        let selector = Int(parameters[index + 1])
                        index += selector == 5 ? 3 : selector == 2 ? 5 : 1
                        continue
                    }
                    index += 1
                }
                guard let lastReset else {
                    output += sequence
                    break
                }
                output += ANSIRenderer.reset + restore
                let rest = parameters[(lastReset + 1)...]
                if !rest.isEmpty { output += "\u{1B}[" + rest.joined(separator: ";") + "m" }
            case .ansi(let sequence, isSGR: false):
                output += sequence
            case .visible(let character):
                output.append(character)
            }
            return true
        }
        return output
    }

    @Test("Hand-picked shapes")
    func shapes() {
        let bg = "\u{1B}[44m"
        for line in [
            "plain", "", "\u{1B}[0m", "a\u{1B}[0mb", "\u{1B}[0;31mred\u{1B}[0m",
            "\u{1B}[0;0m", "\u{1B}[0;0;31mx", "\u{1B}[31m\u{1B}[0m\u{1B}[0m", "x\u{1B}[0;",
            "\u{1B}[0", "\u{1B}[", "\u{1B}", "\u{1B}[1;0mA", "\u{1B}[0;1;0;44mB\u{1B}[0m",
            "\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\ \u{1B}[0m", "wide \u{1F600}\u{1B}[0m ok",
            "a\u{1B}[mb", "\u{1B}[;1mx", "\u{1B}[00mx", "\u{1B}[38;5;0mx", "\u{1B}[0;5Hx", "\u{1B}[31;mx",
        ] {
            #expect(ANSIRenderer.restating(bg, afterResetsIn: line) == Self.reference(bg, in: line), "\(line.debugDescription)")
        }
        #expect(ANSIRenderer.restating("", afterResetsIn: "\u{1B}[0m") == "\u{1B}[0m")
    }

    /// Every spelling of SGR 0 is a reset, as `SGRState` reads one; what a
    /// sequence states after its last reset still overrides the restoration.
    @Test("A reset in any spelling restores; a colour's 0 and a cursor move do not")
    func everySpellingOfAReset() {
        let bg = "\u{1B}[44m"
        let restored = ANSIRenderer.reset + bg
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "a\u{1B}[mb") == "a" + restored + "b")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[00mx") == restored + "x")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[;1mx") == restored + "\u{1B}[1mx")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[1;0mx") == restored + "x")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[0;0;31mx") == restored + "\u{1B}[31mx")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[0;31mx") == restored + "\u{1B}[31mx")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[38;5;0mx") == "\u{1B}[38;5;0mx")
        #expect(ANSIRenderer.restating(bg, afterResetsIn: "\u{1B}[0;5Hx") == "\u{1B}[0;5Hx")
    }

    /// The finding's own check (FREND-4): git's reset keeps a row's fill.
    @Test("A persistent background is restated after git's bare reset")
    func persistentBackgroundAfterBareReset() {
        let code = Color.blue.backgroundEscape()
        let filled = ANSIRenderer.applyPersistentBackground("a\u{1B}[mb", color: .blue)
        #expect(filled == code + "a" + ANSIRenderer.reset + code + "b")
        #expect(
            ANSIRenderer.applyPersistentDim("\u{1B}[31mx\u{1B}[my")
                == ANSIRenderer.dim + "\u{1B}[31mx" + ANSIRenderer.reset + ANSIRenderer.dim + "y" + ANSIRenderer.reset)
    }

    @Test("Randomised runs over the writer's alphabet")
    func randomised() {
        var state: UInt64 = 0xC0FFEE
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33)
        }
        let alphabet = [
            "\u{1B}[0m", "\u{1B}[0;", "\u{1B}[31m", "\u{1B}[0;44m", "0m", ";", "text", " ", "\u{1B}[", "\u{1B}", "m", "0",
            "\u{1B}[m", "\u{1B}[;", "00", "38;5;", "48;2;", "1", "H",
        ]
        for _ in 0..<2000 {
            let length = next() % 9
            let line = (0..<length).map { _ in alphabet[next() % alphabet.count] }.joined()
            for restore in ["\u{1B}[44m", "\u{1B}[2m"] {
                #expect(ANSIRenderer.restating(restore, afterResetsIn: line) == Self.reference(restore, in: line), "\(line.debugDescription)")
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
        let alphabet = [
            "\u{1B}[0m", "\u{1B}[0;", "\u{1B}[31m", "\u{1B}[0;44m", "0m", ";", "text", " ", "\u{1B}[", "\u{1B}", "m", "0",
            "\u{1F600}", "\u{1B}[m",
        ]
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
                #expect(ANSIRenderer.applyPersistentBackground(line, color: fill) == code + Self.reference(code, in: line), "\(line.debugDescription)")
                #expect(
                    ANSIRenderer.applyPersistentBackground(line, color: fill, padding: padding)
                        == ANSIRenderer.applyPersistentBackground(padded, color: fill), "\(line.debugDescription)")
            }
            #expect(ANSIRenderer.applyPersistentDim(line) == ANSIRenderer.dim + Self.reference(ANSIRenderer.dim, in: line) + reset, "\(line.debugDescription)")
            #expect(
                ANSIRenderer.applyPersistentReverse(line, ink: ink, field: field)
                    == opening + Self.reference(opening, in: line) + reset, "\(line.debugDescription)")
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
