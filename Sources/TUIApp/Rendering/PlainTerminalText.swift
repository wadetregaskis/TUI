//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainTerminalText.swift
//
//  The best we can do for a terminal that truly can't show anything but ASCII, in
//  the same place as what's done for a terminal's other shortcomings. Not a mode
//  anyone is meant to choose: the owner's ruling (2026-11-01) is that an ASCII-only
//  mode makes no sense, and that this is a matter of degrading gracefully.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

/// Turns a row on its way to the terminal into ASCII, cell for cell.
///
/// Cell for cell because the frame is already laid out: every view has been measured,
/// and the diff, the mouse and the hit tests all go by those cells. So a character
/// keeps the cells it had, which makes `好`, two cells wide, `ha` rather than `hao`.
enum PlainTerminalText {
    /// Whether this terminal needs it: `TUI_PLAIN_TEXT` if set to `1` or `0`, or else
    /// whether the locale names a character set that isn't UTF-8.
    ///
    /// Only one it names. `C` and `POSIX` name none, and are what an `ssh` session to a
    /// box with no locale installed often has, in front of a terminal showing UTF-8
    /// perfectly well.
    static func isNeeded(in environment: [String: String]) -> Bool {
        switch environment["TUI_PLAIN_TEXT"] {
        case "1": return true
        case "0": return false
        default: break
        }
        let locale = ["LC_ALL", "LC_CTYPE", "LANG"].lazy.compactMap { environment[$0] }.first { !$0.isEmpty }
        guard let locale, let dot = locale.firstIndex(of: ".") else { return false }
        let charset = locale[locale.index(after: dot)...].prefix { $0 != "@" }.lowercased()
        return !charset.isEmpty && charset != "utf-8" && charset != "utf8"
    }

    /// `row` with every character that isn't ASCII replaced by ASCII of the same width.
    /// What isn't a character, the escape sequences, is passed along untouched.
    static func folding(_ row: String) -> String {
        guard row.utf8.contains(where: { $0 >= 0x80 }) else { return row }
        var result = ""
        result.reserveCapacity(row.utf8.count)
        var escape = EscapeState.none
        for character in row {
            if escape.consumes(character) {
                result.append(character)
            } else if character.isASCII {
                result.append(character)
            } else {
                result += folded(character)
            }
        }
        return result
    }

    /// The ASCII for one character, in exactly the cells it takes.
    static func folded(_ character: Character) -> String {
        let cells = character.terminalWidth
        guard cells > 0 else { return "" }
        let spelled = chrome(character) ?? letters(character) ?? ""
        return String(spelled.prefix(cells)).padding(toLength: cells, withPad: " ", startingAt: 0)
    }

    /// Box drawing, blocks and the other shapes the framework draws with, which no
    /// transform has anything to say about.
    private static func chrome(_ character: Character) -> String? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        if let spelled = shapes[scalar] { return spelled }
        switch scalar.value {
        case 0x2500...0x257F: return "+"  // the lines of `shapes`, and then the corners
        case 0x2580...0x259F, 0x25A0...0x25A9: return "#"  // blocks, shades and squares
        case 0x2800...0x28FF: return "."  // Braille
        default: return nil
        }
    }

    private static let shapes: [Unicode.Scalar: String] = {
        var table: [Unicode.Scalar: String] = [:]
        for (spelled, scalars) in [
            ("-", "─━═╌╍┄┅┈┉╴╶╸╺╼╾‐‑‒–—―"), ("|", "│┃║╎╏┆┇┊┋╵╷╹╻╽╿"), ("/", "╱"), ("\\", "╲"), ("X", "╳"),
            ("<", "←◀◂◄‹«"), (">", "→▶▸►›»"), ("^", "↑▲△▴"), ("v", "↓▼▽▾"),
            ("o", "●○◉◎◦"), ("*", "•∙★☆✱"), (".", "·"), ("x", "✓✔✗✘"),
        ] as [(String, String)] {
            for scalar in scalars.unicodeScalars { table[scalar] = spelled }
        }
        return table
    }()

    /// Letters: `é` to `e`, `ß` to `ss`, and, where Foundation has them, other scripts
    /// to Latin (`你` to `ni`). ICU's rules, which Foundation carries anyway.
    ///
    /// Decomposing first: that's the standard library's own data, so `é` comes out right
    /// whatever a platform's Foundation can do with a transform.
    private static func letters(_ character: Character) -> String? {
        let bare = String(character).decomposedStringWithCanonicalMapping.unicodeScalars.filter(\.isASCII)
        if !bare.isEmpty { return String(String.UnicodeScalarView(bare)) }
        let latin = String(character).applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false)
        guard let latin, latin.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        return latin
    }

    /// Where the walk is in an escape sequence: CSI up to its final byte; OSC, DCS and
    /// APC up to BEL or ST.
    private enum EscapeState {
        case none, introduced, control, string, stringEscape

        /// Whether `character` is part of a sequence, moving on through it if so.
        mutating func consumes(_ character: Character) -> Bool {
            switch self {
            case .none:
                guard character == "\u{1B}" else { return false }
                self = .introduced
            case .introduced:
                switch character {
                case "[": self = .control
                case "]", "P", "_": self = .string
                default: self = .none
                }
            case .control:
                if let byte = character.asciiValue, (0x40...0x7E).contains(byte) { self = .none }
            case .string:
                if character == "\u{07}" { self = .none } else if character == "\u{1B}" { self = .stringEscape }
            case .stringEscape:
                self = .none
            }
            return true
        }
    }
}
