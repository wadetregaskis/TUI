//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Highlighting.swift
//
//  The editor's side of highlighting's drawing (lane H1 of the highlighting
//  design's §8.6): the layer set and its styles resolved, and each drawn
//  line's runs, the highlighting's over the line's own, kept for the lines
//  drawn; and (lane H6′) the highlighter's session the runs come from, told
//  of each edit and of the lines on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension TextEditorHandler {
    /// Whether the lines are drawn in styles kept in ``lineStyleCache``,
    /// which an edit must then move with its lines.
    var drawsLineStyles: Bool { lineStyler != nil || highlightLayer != nil }

    /// Sets the highlighting drawn over the text, forgetting the runs drawn
    /// with the last. Its styles resolve when the editor next draws.
    func replaceHighlightLayer(_ layer: EditorHighlightLayer?) {
        highlightLayer = layer
        lineStyleCache.forgetDrawnRuns()
    }

    /// The highlighting of `lines`, or of every line, changed: their runs are
    /// read again when next drawn.
    func highlightingChanged(inLines lines: Range<Int>? = nil) {
        lineStyleCache.forgetDrawnRuns(ofLines: lines)
    }

    /// Takes the frame's text, or the attributed value's, and with a
    /// highlighter resolves its styles in `environment`, unless they are
    /// already, forgetting the runs drawn in the old ones (B-ATTRED-10: a
    /// palette change restyles, and asks the highlighter for nothing).
    @MainActor
    func adopt(text: Binding<String>, attributed: AttributedTextBinding?, environment: EnvironmentValues) {
        if let attributed { adoptAttributed(attributed, environment: environment) } else { self.text = text }
        guard highlightLayer != nil else { return }
        let styling = attributedSource != nil ? attributedStyling : nil
        guard highlightLayer?.styles.adopt(styling ?? EditorAttributedStyling(in: environment)) == true else { return }
        lineStyleCache.forgetDrawnRuns()
    }

    /// The styles `line` is drawn in under `layer`: the highlighting's runs
    /// over the line's own, where what a highlight run sets wins and what it
    /// leaves unset is the line's (B-ATTRED-8). Made when the line is first
    /// drawn and kept, so a frame costs each line's runs only once.
    func highlightedStyles(ofLine line: Int, in layer: EditorHighlightLayer) -> [EditorStyledRun] {
        if let drawn = lineStyleCache.drawnRuns(ofLine: line) { return drawn }
        // First: a text replaced whole clears the cache.
        let layout = layout()
        guard line < layout.lines.count else { return [] }
        let own = lineStyler.map { lineStyleCache.runs(ofLine: line, reading: $0) } ?? []
        let highlighted = EditorHighlightRun.styledRuns(layer.runs(line), in: layout.lines[line], styles: layer.styles)
        let drawn = EditorStyledRun.overlaying(highlighted, on: own)
        lineStyleCache.keepDrawnRuns(drawn, ofLine: line)
        return drawn
    }
}

// MARK: - The highlighter's session (H6′)

/// The highlighter an editor shows: its session, each style index's
/// attributes, and the layout whose text the session last had.
final class EditorHighlightConnection {
    /// Which highlighter it is (B-ATTRED-25).
    let key: EditorHighlighterKey
    let feed: any EditorHighlightFeed
    let style: @MainActor (UInt16) -> AttributeContainer

    /// The layout whose text the session has: an edit made from another
    /// layout (the binding kept a text of its own) is told as a text written
    /// whole, its change found from the bytes the two texts share.
    weak var syncedLayout: EditorLayout?

    init(key: EditorHighlighterKey, feed: any EditorHighlightFeed, style: @escaping @MainActor (UInt16) -> AttributeContainer) {
        self.key = key
        self.feed = feed
        self.style = style
    }
}

extension TextEditorHandler {
    /// Draws the runs `connection`'s session keeps, its text `layout`'s.
    func connectHighlighter(_ connection: EditorHighlightConnection, layout: EditorLayout) {
        highlightConnection?.feed.close()
        highlightConnection = connection
        connection.syncedLayout = layout
        let feed = connection.feed
        replaceHighlightLayer(EditorHighlightLayer(runs: { feed.runs(ofLine: $0) }, styles: EditorHighlightStyles()))
    }

    /// Stops drawing the highlighter's runs, and tells its session the
    /// editor has gone.
    func disconnectHighlighter() {
        guard let connection = highlightConnection else { return }
        connection.feed.close()
        highlightConnection = nil
        replaceHighlightLayer(nil)
    }

    /// What the session is told of `edit`, made from `before` (which must
    /// not have been laid out into its successor yet): the change by whole
    /// lines at both ends, so its byte ranges start at a line's start, and
    /// how the tokens of each line edited in place in the window move. `nil`
    /// without a session, or where the session's text is not `before`'s.
    func highlightEdit(_ edit: EditorLayout.Edit, from before: EditorLayout) -> EditorHighlightEdit? {
        guard let connection = highlightConnection, connection.syncedLayout === before, !edit.isUnchanged else {
            return nil
        }
        let oldCount = before.lines.count
        let reachesEnd = edit.replaced.upperBound == oldCount
        // Lines added or taken at the end change the line before too: its
        // break, which the edit's bytes start with.
        var first = edit.replaced.lowerBound
        if reachesEnd, edit.replaced.isEmpty || edit.replacement.isEmpty, first > 0 { first -= 1 }
        let (oldTotal, newTotal) = (before.text.utf8.count, edit.text.utf8.count)
        let suffix = reachesEnd ? 0 : oldTotal - before.lineStarts[edit.replaced.upperBound]
        let start = before.lineStarts[first]
        var change = EditorHighlightEdit(
            change: TextEditorTextChange(
                oldLines: first..<edit.replaced.upperBound, newLines: first..<edit.replacement.upperBound,
                oldUTF8: start..<(oldTotal - suffix), newUTF8: start..<(newTotal - suffix)),
            replaced: edit.replaced, replacementCount: edit.replacement.count)
        if edit.replaced.count == edit.replacement.count {
            let window = connection.feed.window
            for line in edit.replaced where window.contains(line) {
                change.carried[line] = EditorLineShift(
                    from: before.lines[line].lazy.flatMap(\.utf8),
                    to: edit.lines[line - edit.replaced.lowerBound].lazy.flatMap(\.utf8))
            }
        }
        return change
    }

    /// Tells the session of `edit`, which left `after`.
    func sendHighlightEdit(_ edit: EditorHighlightEdit, leaving after: EditorLayout) {
        guard let connection = highlightConnection else { return }
        let gone = connection.feed.textChanged(to: after.text, lineCount: after.lines.count, by: edit)
        connection.syncedLayout = after
        lineStyleCache.forgetDrawnRuns(ofEach: gone)
    }

    /// A frame's part, before its rows are drawn: the session given the text
    /// written whole if it does not have it (as the edit it is of the text
    /// before, B-ATTRED-58), the lines whose tokens changed drawn again, the
    /// tokens interned since styled, and the lines on screen told.
    @MainActor
    func syncHighlighting(visibleLines: Range<Int>) {
        guard let connection = highlightConnection, highlightLayer != nil else { return }
        let feed = connection.feed
        let layout = layout()
        if connection.syncedLayout !== layout {
            lineStyleCache.forgetDrawnRuns(ofEach: feed.textWritten(to: layout.text, lineStarts: layout.lineStarts))
            connection.syncedLayout = layout
        }
        lineStyleCache.forgetDrawnRuns(ofEach: feed.takeChangedLines())
        // In the session's order, so a session's style index is the layer's.
        let interned = feed.tokenCount
        while let next = highlightLayer?.styles.containers.count, next <= interned, next <= Int(UInt16.max) {
            _ = highlightLayer?.styles.index(of: UInt16(next)) { connection.style($0) }
        }
        lineStyleCache.forgetDrawnRuns(ofEach: feed.show(lines: visibleLines))
    }
}
