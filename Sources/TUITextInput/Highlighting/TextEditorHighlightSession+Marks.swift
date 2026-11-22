//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightSession+Marks.swift
//
//  Marks through the highlight session (B-ATTRED-59): ranges of one version
//  of the text a highlighter states beside its tokens, such as the syntax
//  errors a parse found, kept in UTF-8 offsets of the editor's text, carried
//  through its edits and its texts written whole as an app's marks are
//  (B-ATTRED-46, 47), and drawn in their token's style over the highlighting
//  and under the app's own marks.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import TUIFoundation

/// TUI-specific. A range of the text a highlighter marks, such as a syntax
/// error: drawn in its token's style (the modifier's `style`) over the
/// highlighting, and under the app's own marks (``View/textEditorMarks(_:in:)``),
/// the selection and the find bar's matches.
@_spi(TextEditorHighlighting)
public struct TextEditorHighlightMark<Token: Hashable & Sendable>: Sendable, Equatable {
    /// The bytes marked, in UTF-8 offsets from the start of the text the
    /// marks are published for. A range of no length draws nothing.
    public var utf8: Range<Int>
    /// What it is drawn in.
    public var token: Token

    /// A mark of the bytes `utf8`, drawn in `token`'s style.
    public init(_ utf8: Range<Int>, token: Token) {
        self.utf8 = utf8
        self.token = token
    }
}

extension TextEditorHighlightSession {
    /// Publishes `marks`, ranges of the text of `version`, in place of the
    /// marks published before (B-ATTRED-59). Returns what became of them, as
    /// a publish of tokens does (B-ATTRED-64): refused for a text that is no
    /// longer the editor's, and then kept nowhere, the marks published before
    /// staying; else kept for every line of the text, `.kept(0..<lineCount)`,
    /// since marks are kept for the whole text, not the window.
    ///
    /// The editor carries them through its edits from then on, as it carries
    /// an app's marks: text typed before a mark moves it, text typed inside
    /// it grows it, text typed at either of its ends stays outside it, and a
    /// mark whose text was deleted goes. A text written whole (the app's own
    /// write, an undo, a redo) carries them through the change it is
    /// (B-ATTRED-58). So a highlighter publishes marks only when its parse
    /// finds them changed, and never needs to state them again for a text
    /// the editor has moved on from. Offsets past the text are clamped to it.
    @discardableResult
    public func publish(marks: [TextEditorHighlightMark<Token>], of version: Int) -> TextEditorPublishOutcome {
        guard let (text, _) = state.withLock({ $0.publishable(version: version) }) else {
            return observed(.refused, lines: nil, marks: marks.count, of: version)
        }
        let total = text.utf8Count
        let kept = marks.filter { max(0, $0.utf8.lowerBound) < min($0.utf8.upperBound, total) }
        let styles = interned.withLock { $0.indices(of: kept.map(\.token)) }
        let made = zip(kept, styles).map { mark, style in
            EditorMark(utf8: max(0, mark.utf8.lowerBound)..<min(mark.utf8.upperBound, total), style: style)
        }
        let outcome = state.withLock { state -> EditorHighlightKeep in
            guard !state.isClosed, version == state.version else { return .refused }
            guard state.marks != made else { return .kept(0..<0, askForFrame: false) }
            state.marks = made
            state.marksChange = .published
            guard !state.frameAsked else { return .kept(0..<0, askForFrame: false) }
            state.frameAsked = true
            return .kept(0..<0, askForFrame: true)
        }
        if case .kept(_, true) = outcome { requestFrame() }
        return observed(
            outcome == .refused ? .refused : .kept(0..<text.lineCount), lines: nil, marks: marks.count, of: version)
    }

    /// Whether the session holds marks: an edit then finds what carries them.
    var hasMarks: Bool { state.withLock { !$0.marks.isEmpty } }

    /// The marks as they are now, and whether a publish changed them, if
    /// they changed since this was last asked; else `nil`.
    func takeMarks() -> (marks: [EditorMark], published: Bool)? {
        state.withLock { state in
            guard let change = state.marksChange else { return nil }
            state.marksChange = nil
            return (state.marks, change == .published)
        }
    }

    /// The marks the session holds, each with its token, for a test.
    func keptMarks() -> [TextEditorHighlightMark<Token>] {
        state.withLock { $0.marks }.compactMap { mark in
            token(mark.style).map { TextEditorHighlightMark(mark.utf8, token: $0) }
        }
    }
}

/// How the marks a session holds changed since the editor last took them:
/// carried through an edit, which leaves the lines it did not touch as they
/// were drawn, or published anew (or dropped), which may change any line.
enum EditorHighlightMarksChange: Sendable, Equatable {
    case moved
    case published
}

extension EditorHighlightState {
    /// Carries the marks through an edit, by `edit`'s bytes, or drops them
    /// where it has none to carry them by.
    mutating func carryMarks(through edit: EditorMarkEdit?) {
        guard !marks.isEmpty else { return }
        if let edit {
            marks = edit.carry(marks)
            if marksChange == nil { marksChange = .moved }
        } else {
            marks = []
            marksChange = .published
        }
    }
}

// MARK: - Drawing them

extension EditorHighlightConnection {
    /// `drawn`, a line's runs, with the session's marks on line `line` of
    /// `layout` drawn over them in `styles`, those of the layer.
    func marked(
        _ drawn: [EditorStyledRun], ofLine line: Int, in layout: EditorLayout, styles: EditorHighlightStyles
    ) -> [EditorStyledRun] {
        guard !marks.isEmpty else { return drawn }
        if marksLayout !== layout || marksByLine == nil {
            (marksByLine, marksLayout) = (EditorMarkStore.byLine(marks, in: layout), layout)
        }
        guard let onLine = marksByLine?[line], !onLine.isEmpty else { return drawn }
        let runs = EditorMarkStore.runs(of: onLine, inLine: layout.lines[line], styles: styles)
        return runs.isEmpty ? drawn : EditorStyledRun.overlaying(runs, on: drawn)
    }

    /// Takes the session's marks if they changed: returns whether every
    /// drawn line must be drawn again, as for a publish.
    func takeMarks() -> Bool {
        guard let taken = feed.takeMarks() else { return false }
        (marks, marksByLine) = (taken.marks, nil)
        return taken.published
    }
}
