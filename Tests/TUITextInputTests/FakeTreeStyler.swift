//  🖥️ TUI — A Terminal UI framework for Swift
//  FakeTreeStyler.swift
//
//  Highlighters for the highlight seam's tests (lane H6′): a fake tree
//  styler, which works as the tree-sitter adapter will (the whole text
//  styled, the lines whose tokens changed found as tree-sitter's changed
//  ranges are, and only those in the window published), and a stepped
//  highlighter, which hands its session to the test and does nothing, so a
//  test plays the highlighter one step at a time.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization

@_spi(TextEditorHighlighting) @testable import TUITextInput

/// Styles a text as a tree styler does. Words, numbers and the gaps between
/// them, and `/* … */` comments, which span lines as a tree's nodes do: so
/// opening one restyles every line below it, beyond the line edited.
final class FakeTreeStyler: Sendable {
    enum Token: Hashable, Sendable { case word, number, comment, gap }

    /// A line's tokens: each and the byte it starts at.
    typealias Line = [Pair]
    struct Pair: Hashable, Sendable {
        var token: Token
        var offset: Int
    }

    /// What one step saw and did.
    struct Step: Sendable, Equatable {
        var version: Int
        var change: TextEditorTextChange?
        /// The lines whose tokens changed (tree-sitter's changed ranges, and
        /// the edit's own lines), and those published.
        var changed: Set<Int>
        var published: Set<Int>
    }

    private struct State: Sendable {
        var version: Int?
        var lines: [Line] = []
        var steps: [Step] = []
    }

    private let state = Mutex(State())

    /// Every step taken, in order.
    var steps: [Step] { state.withLock { $0.steps } }

    /// The version of the last text styled, or `nil` before the first.
    var version: Int? { state.withLock { $0.version } }

    /// `text`'s tokens, line by line, a comment carried from line to line.
    static func lines(of text: TextEditorText) -> [Line] {
        var inComment = false
        return (0..<text.lineCount).map { index in
            let bytes = Array(text.line(index))
            var line: Line = []
            var at = 0
            func open(_ token: Token, _ offset: Int) {
                if line.last?.token != token { line.append(Pair(token: token, offset: offset)) }
            }
            while at < bytes.count {
                if inComment {
                    open(.comment, at)
                    if at + 1 < bytes.count, bytes[at] == UInt8(ascii: "*"), bytes[at + 1] == UInt8(ascii: "/") {
                        inComment = false
                        at += 2
                    } else {
                        at += 1
                    }
                    continue
                }
                let byte = bytes[at]
                if byte == UInt8(ascii: "/"), at + 1 < bytes.count, bytes[at + 1] == UInt8(ascii: "*") {
                    inComment = true
                    open(.comment, at)
                    at += 2
                } else if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                    open(.number, at)
                    at += 1
                } else if byte >= 0x80 || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte | 0x20) {
                    open(.word, at)
                    at += 1
                } else {
                    open(.gap, at)
                    at += 1
                }
            }
            return line
        }
    }

    /// `line` as a seam's tokens.
    static func tokens(_ line: Line) -> TextEditorTokens<Token> {
        var tokens = TextEditorTokens<Token>()
        for pair in line { tokens.append(pair.token, at: pair.offset) }
        return tokens
    }

    /// Styles `update`'s text, and publishes to `session` the lines in the
    /// window whose tokens changed, and those the session holds no tokens of
    /// this text for (`linesToStyle`, B-ATTRED-57): in runs of lines, a lock
    /// each.
    func step(_ update: TextEditorHighlightUpdate, in session: TextEditorHighlightSession<Token>) {
        let lines = Self.lines(of: update.text)
        let toPublish = state.withLock { state -> [Int] in
            var changed: Set<Int> = []
            if update.text.version == state.version {
                // A scroll: nothing changed.
            } else if let change = update.change, state.version != nil {
                let shift = change.newLines.count - change.oldLines.count
                changed.formUnion(change.newLines)
                for line in lines.indices where !change.newLines.contains(line) {
                    let old = line < change.newLines.lowerBound ? line : line - shift
                    if old < 0 || old >= state.lines.count || state.lines[old] != lines[line] { changed.insert(line) }
                }
            } else {
                changed = Set(lines.indices)
            }
            let toPublish = update.window.filter { changed.contains($0) || update.linesToStyle.contains($0) }
            state.lines = lines
            state.version = update.text.version
            state.steps.append(
                Step(version: update.text.version, change: update.change, changed: changed, published: Set(toPublish)))
            return toPublish
        }
        // Each run of consecutive lines in one publish (B-ATTRED-29).
        var start = 0
        while start < toPublish.count {
            var end = start + 1
            while end < toPublish.count, toPublish[end] == toPublish[end - 1] + 1 { end += 1 }
            let range = toPublish[start]..<(toPublish[end - 1] + 1)
            session.publish(range.map { Self.tokens(lines[$0]) }, forLines: range, of: update.text.version)
            start = end
        }
    }
}

/// The fake tree styler as a highlighter: it styles each update as it comes,
/// until the editor goes.
struct FakeTreeHighlighter: TextEditorHighlighter {
    let styler: FakeTreeStyler

    func highlight(_ session: TextEditorHighlightSession<FakeTreeStyler.Token>) async {
        while let update = await session.nextUpdate() {
            styler.step(update, in: session)
            do { try await session.checkpoint() } catch { return }
        }
    }
}

/// Where a stepped highlighter leaves each session it is given, and how many
/// of its runs have ended.
final class SessionInbox: Sendable {
    private struct State: Sendable {
        var sessions: [TextEditorHighlightSession<FakeTreeStyler.Token>] = []
        var holds: [AsyncStream<Void>.Continuation] = []
        var ended = 0
    }

    private let state = Mutex(State())

    var sessions: [TextEditorHighlightSession<FakeTreeStyler.Token>] { state.withLock { $0.sessions } }
    var ended: Int { state.withLock { $0.ended } }

    /// Takes `session`, and waits until the task is cancelled.
    func hold(_ session: TextEditorHighlightSession<FakeTreeStyler.Token>) async {
        // A stream nothing is sent on, its continuation kept so it never
        // finishes: its iteration ends only with the task's cancellation.
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock {
            $0.sessions.append(session)
            $0.holds.append(continuation)
        }
        for await _ in stream {}
        state.withLock { $0.ended += 1 }
    }
}

/// A highlighter that does nothing but hand its session to the test, which
/// then plays it a step at a time. Two are one highlighter, being of a type
/// that is not `Equatable` (B-ATTRED-25).
struct SteppedHighlighter: TextEditorHighlighter {
    let inbox: SessionInbox

    func highlight(_ session: TextEditorHighlightSession<FakeTreeStyler.Token>) async {
        await inbox.hold(session)
    }
}

/// A stepped highlighter that is `Equatable`: two with different ids are two
/// highlighters.
struct NumberedHighlighter: TextEditorHighlighter, Equatable {
    let id: Int
    let inbox: SessionInbox

    func highlight(_ session: TextEditorHighlightSession<FakeTreeStyler.Token>) async {
        await inbox.hold(session)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
