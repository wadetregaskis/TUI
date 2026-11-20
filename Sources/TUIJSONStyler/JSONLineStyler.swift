//  🖥️ TUI — A Terminal UI framework for Swift
//  JSONLineStyler.swift
//
//  A stateless JSON line styler over the highlight seam (lane H5′ of the
//  highlighting design's §8.6): keys, strings and their escapes, numbers,
//  `true`, `false` and `null`, punctuation, and whatever else as invalid,
//  each line on its own. A fixture for the Example, Stress's
//  `bigtext-highlighted` and the tests, not a lexer TUI ships: real
//  highlighting comes from tree-sitter, in apps (A-ATTRED-12). A string that
//  spans lines is not JSON, so a line needs nothing of the line before.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation
@_spi(TextEditorHighlighting) import TUITextInput

/// What the JSON styler calls the parts of a line.
package enum JSONToken: Hashable, Sendable {
    /// A string that names a member: followed, past any blanks, by a colon.
    case key
    /// Any other string, its quotes included; unterminated, it runs to the
    /// line's end.
    case string
    /// A backslash escape inside a string (or key): `\n`, `\"`, `é`.
    case escape
    case number
    /// `true`, `false` or `null`.
    case literal
    /// `{`, `}`, `[`, `]`, `,` and `:`.
    case punctuation
    /// Anything JSON has no place for: a stray character, a word that is not
    /// a literal, an escape JSON does not have.
    case invalid
    /// Blanks between the rest.
    case space
}

/// Styles a line of JSON: tokens from its bytes alone (B-ATTRED-42).
package enum JSONLineStyler {
    /// `line`'s tokens: each where it starts, a run of one kind one token.
    package static func tokens(of line: Substring.UTF8View) -> TextEditorTokens<JSONToken> {
        tokens(of: Array(line))
    }

    /// The tokens of a line's bytes, without its break. An array, not the
    /// string's own storage borrowed: a line's copy costs a fixture nothing
    /// worth an `unsafe` (SE-0458).
    package static func tokens(of bytes: [UInt8]) -> TextEditorTokens<JSONToken> {
        var scanner = Scanner(bytes: bytes)
        scanner.scan()
        return scanner.tokens
    }

    /// The attributes the Example, Stress and the tests draw each token in.
    package static func style(_ token: JSONToken) -> AttributeContainer {
        var container = AttributeContainer()
        switch token {
        case .key: container.foregroundColor = .cyan
        case .string: container.foregroundColor = .green
        case .escape: container.foregroundColor = .blue
        case .number: container.foregroundColor = .yellow
        case .literal: container.foregroundColor = .magenta
        case .invalid: container.foregroundColor = .red
        case .punctuation, .space: break
        }
        return container
    }

    /// Styles the lines of `update`'s window, those on screen and a screen
    /// either side, as the session keeps them, and publishes them to
    /// `session` in one batch. All of them, every update: a stateless styler
    /// has no changed ranges to find, and the session takes a line whose
    /// tokens did not change as no change at all, so the editor draws it
    /// again only if they did. A line longer than the session styles is
    /// published empty, without being scanned (B-ATTRED-15).
    package static func publish(_ update: TextEditorHighlightUpdate, in session: TextEditorHighlightSession<JSONToken>) {
        let text = update.text
        let visible = update.visibleLines
        let screen = max(1, visible.count)
        let window = max(0, visible.lowerBound - screen)..<min(text.lineCount, visible.upperBound + screen)
        guard !window.isEmpty else { return }
        let tokens = window.map { index in
            let line = text.line(index)
            return line.count > session.maximumLineLength ? TextEditorTokens() : Self.tokens(of: line)
        }
        session.publish(tokens, forLines: window, of: text.version)
    }
}

/// The JSON styler as a highlighter: it styles each update as it comes, until
/// the editor goes.
package struct JSONHighlighter: TextEditorHighlighter {
    package init() {}

    package func highlight(_ session: TextEditorHighlightSession<JSONToken>) async {
        while let update = await session.nextUpdate() {
            JSONLineStyler.publish(update, in: session)
            do { try await session.checkpoint() } catch { return }
        }
    }
}

// MARK: - The scanner

/// One pass over a line's bytes, left to right.
private struct Scanner {
    let bytes: [UInt8]
    var at = 0
    var tokens = TextEditorTokens<JSONToken>()
    private var last: JSONToken?

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// A token from `offset`, unless the one before is the same kind.
    private mutating func open(_ token: JSONToken, at offset: Int) {
        guard token != last else { return }
        tokens.append(token, at: offset)
        last = token
    }

    mutating func scan() {
        while at < bytes.count {
            switch bytes[at] {
            case UInt8(ascii: " "), UInt8(ascii: "\t"):
                open(.space, at: at)
                at += 1
            case UInt8(ascii: "\""):
                string()
            case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: ","),
                UInt8(ascii: ":"):
                open(.punctuation, at: at)
                at += 1
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                number()
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"):
                word()
            default:
                // A UTF-8 character's bytes are all 0x80 or more, so one stray
                // character is one run.
                open(.invalid, at: at)
                at += 1
            }
        }
    }

    /// A string from its opening quote: a key if a colon follows it.
    private mutating func string() {
        let start = at
        // Its end, past the closing quote, an escape's second byte never
        // closing it; the line's end if it is never closed.
        var end = start + 1
        var closed = false
        while end < bytes.count {
            if bytes[end] == UInt8(ascii: "\\") {
                end += 2
            } else if bytes[end] == UInt8(ascii: "\"") {
                end += 1
                closed = true
                break
            } else {
                end += 1
            }
        }
        end = min(end, bytes.count)
        let contentEnd = closed ? end - 1 : end
        var next = end
        while next < bytes.count, bytes[next] == UInt8(ascii: " ") || bytes[next] == UInt8(ascii: "\t") { next += 1 }
        let kind: JSONToken = closed && next < bytes.count && bytes[next] == UInt8(ascii: ":") ? .key : .string
        open(kind, at: start)
        var offset = start + 1
        while offset < contentEnd {
            if bytes[offset] == UInt8(ascii: "\\") {
                let length = escapeLength(at: offset, before: contentEnd)
                open(length > 0 ? .escape : .invalid, at: offset)
                offset += max(abs(length), 1)
            } else {
                open(kind, at: offset)
                offset += 1
            }
        }
        // The closing quote, after an escape.
        if closed { open(kind, at: contentEnd) }
        at = end
    }

    /// How long the escape at `offset` is, its backslash included, before
    /// `end`: negative for one JSON does not have, as long as is to be
    /// styled invalid.
    private func escapeLength(at offset: Int, before end: Int) -> Int {
        guard offset + 1 < end else { return -1 }
        switch bytes[offset + 1] {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"), UInt8(ascii: "f"),
            UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
            return 2
        case UInt8(ascii: "u"):
            var length = 2
            while length < 6, offset + length < end, Self.isHexDigit(bytes[offset + length]) { length += 1 }
            return length == 6 ? 6 : -length
        default:
            return -2
        }
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte | 0x20)
    }

    /// A number, leniently: a run of what numbers are made of.
    private mutating func number() {
        open(.number, at: at)
        while at < bytes.count {
            switch bytes[at] {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."),
                UInt8(ascii: "e"), UInt8(ascii: "E"):
                at += 1
            default:
                return
            }
        }
    }

    /// A run of letters: a literal, or invalid.
    private mutating func word() {
        let start = at
        while at < bytes.count, (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(bytes[at] | 0x20) { at += 1 }
        let word = bytes[start..<at]
        let isLiteral = Self.literals.contains { $0.elementsEqual(word) }
        open(isLiteral ? .literal : .invalid, at: start)
    }

    private static let literals: [[UInt8]] = [Array("true".utf8), Array("false".utf8), Array("null".utf8)]
}
