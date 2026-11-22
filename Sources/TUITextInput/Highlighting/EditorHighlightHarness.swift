//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorHighlightHarness.swift
//
//  A highlight session with no editor (B-ATTRED-60): the editor's half played
//  by the code an editor runs (its edits spliced as `EditorLayout` splices
//  them and told as `TextEditorHandler` tells them, its whole writes, its
//  scrolls), and what the session holds read back. The engine of
//  TUITesting's `TestHighlightSession`; `package`, so that TUITesting, and
//  no app, reaches it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import TUIFoundation

/// A highlight session, the editor's half played by a test.
package final class EditorHighlightHarness<Token: Hashable & Sendable> {
    /// Counts the frames the session asks for.
    private final class Frames: Sendable {
        let count = Mutex(0)
    }

    /// The session, as a highlighter is given it.
    package let session: TextEditorHighlightSession<Token>
    /// The editor's text, laid out as an editor lays it out.
    private var layout: EditorLayout
    private let frames: Frames

    /// A session over `text`, version 0, `visibleLines` on screen.
    package init(text: String, visibleLines: Range<Int>, maximumLineLength: Int) {
        let layout = EditorLayout(text: text)
        let frames = Frames()
        self.frames = frames
        session = TextEditorHighlightSession(
            text: layout.text, lineCount: layout.lines.count, maximumLineLength: maximumLineLength,
            requestFrame: { frames.count.withLock { $0 += 1 } })
        self.layout = layout
        _ = session.show(lines: visibleLines)
    }

    /// The editor's text.
    package var text: String { layout.text }

    /// How many frames the session has asked for.
    package var framesAsked: Int { frames.count.withLock { $0 } }

    /// Replaces the UTF-8 bytes `utf8` of the text, clamped to it, with
    /// `replacement`, as the editor's own edit: the lines it changed spliced
    /// into the layout and told to the session as a key's are. In a text with
    /// more than one kind of line break, which the editor writes whole, a
    /// write.
    package func replace(_ utf8: Range<Int>, with replacement: String) {
        var new = layout.text
        let bytes = new.utf8
        let lower = min(max(0, utf8.lowerBound), bytes.count)
        let upper = min(max(lower, utf8.upperBound), bytes.count)
        new.replaceSubrange(
            bytes.index(bytes.startIndex, offsetBy: lower)..<bytes.index(bytes.startIndex, offsetBy: upper),
            with: replacement)
        let before = layout
        var lines = EditedLines(before.lines)
        let last = before.lines.count - 1
        lines.apply(
            TextEditorReplacement(
                from: TextEditorPosition(line: 0, column: 0),
                to: TextEditorPosition(line: last, column: before.lines[last].count), with: EditorLayout(text: new).lines))
        guard let edit = before.replacing(lines), edit.text == new else {
            write(new)
            return
        }
        guard !edit.isUnchanged else { return }
        let told = EditorHighlightEdit(edit, from: before, window: session.window, carryingMarks: session.hasMarks)
        let after = before.laidOut(edit, reusingStorage: false)
        _ = session.textChanged(to: after.text, lineCount: after.lines.count, by: told)
        layout = after
    }

    /// Writes `text` whole, as an app's write or an undo does.
    package func write(_ text: String) {
        let written = EditorLayout(text: text)
        _ = session.textWritten(to: written.text, lineStarts: written.lineStarts)
        layout = written
    }

    /// Puts `lines` on screen.
    package func show(lines: Range<Int>) {
        _ = session.show(lines: lines)
    }

    /// Takes what a frame takes: the next publish that changes a line on
    /// screen asks for a frame again.
    package func tookFrame() {
        _ = session.takeChangedLines()
        _ = session.takeMarks()
    }

    /// `line`'s tokens as the session holds them, or `nil` for none.
    package func tokens(ofLine line: Int) -> TextEditorTokens<Token>? {
        guard let kept = session.keptLine(line) else { return nil }
        var tokens = TextEditorTokens<Token>()
        tokens.reserveCapacity(kept.runs.count)
        for run in kept.runs {
            // Style 0 is none: a token past the 65,535 a session interns.
            guard let token = session.token(run.style) else { continue }
            tokens.append(token, at: Int(run.utf8Offset))
        }
        return tokens
    }

    /// Whether `line`'s tokens are carried ones, until it is published again.
    package func isProvisional(line: Int) -> Bool {
        session.keptLine(line)?.isProvisional ?? false
    }

    /// The marks the session holds.
    package var marks: [TextEditorHighlightMark<Token>] { session.keptMarks() }

    /// Ends the session, as an editor going does.
    package func close() {
        session.close()
    }
}
