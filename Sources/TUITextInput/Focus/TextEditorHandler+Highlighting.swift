//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Highlighting.swift
//
//  The editor's side of highlighting's drawing (lane H1 of the highlighting
//  design's §8.6): the layer set and its styles resolved, and each drawn
//  line's runs, the highlighting's over the line's own, kept for the lines
//  drawn. Where the runs come from is the seam's (H6′).
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
