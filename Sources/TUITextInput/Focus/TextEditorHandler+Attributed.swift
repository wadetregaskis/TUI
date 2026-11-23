//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Attributed.swift
//
//  An editor bound to an `AttributedString` (G3 L4): its source, the styles
//  its lines are drawn in, and the selection it exchanges with the app.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// What an attributed editor's lines' styles depend on besides the value: a
/// change has them read afresh.
struct EditorAttributedStyling: Equatable {
    let palette: any Palette
    let accent: Color
    let lineStyleSupport: LineStyleSupport
    let font: Font?
    let linkUnderline: Bool

    /// What an editor drawn in `environment` draws its lines' styles under.
    @MainActor
    init(in environment: EnvironmentValues) {
        let palette = environment.palette
        self.init(
            palette: palette, accent: palette.accent.resolve(with: palette),
            lineStyleSupport: environment.lineStyleSupport, font: environment.font,
            linkUnderline: environment.linkUnderline)
    }

    init(palette: any Palette, accent: Color, lineStyleSupport: LineStyleSupport, font: Font?, linkUnderline: Bool) {
        (self.palette, self.accent, self.lineStyleSupport) = (palette, accent, lineStyleSupport)
        (self.font, self.linkUnderline) = (font, linkUnderline)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.palette.id == b.palette.id && a.accent == b.accent && a.lineStyleSupport == b.lineStyleSupport
            && a.font == b.font && a.linkUnderline == b.linkUnderline
    }
}

extension TextEditorHandler {
    /// Takes the frame's bindings and environment for an editor bound to an
    /// `AttributedString`: the source is made the first time, and the editor's
    /// text is the binding over its characters from then on.
    @MainActor
    func adoptAttributed(_ bindings: AttributedTextBinding, environment: EnvironmentValues) {
        let source: AttributedTextSource
        if let existing = attributedSource {
            source = existing
            source.binding = bindings.text
            source.selection = bindings.selection
        } else {
            source = AttributedTextSource(bindings)
            attributedSource = source
            source.onTakenWhole = { [weak self] sameCharacters in
                guard let self else { return }
                lineStyleCache.removeAll()
                keptLineGaps = nil
                // Only recoloured: still the text the history's edits left.
                if sameCharacters, let value = attributedSource?.value { undoHistory.noteWritten(.attributed(value)) }
            }
            replaceLineStyler { [weak self] line in
                MainActor.assumeIsolated { self?.attributedStyles(ofLine: line) ?? [] }
            }
        }
        text = source.plainText
        let styling = EditorAttributedStyling(in: environment)
        if styling != attributedStyling {
            lineStyleCache.removeAll()
            keptLineGaps = nil
        }
        attributedStyling = styling
    }

    /// The styles `line` of an attributed editor's value is drawn in: each run
    /// of the line, as a `Text` of the value draws it (A-ATTRED-3: colours,
    /// a font's tier and weight as bold or faint, italic, its lines), a link
    /// in the accent and underlined, not hyperlinked (B-ATTRED-7).
    @MainActor
    func attributedStyles(ofLine line: Int) -> [EditorStyledRun] {
        guard let source = attributedSource, let styling = attributedStyling else { return [] }
        let layout = layout()
        guard line < layout.lines.count, !layout.lines[line].isEmpty else { return [] }
        let value = source.value
        let lower = value.characters.index(value.startIndex, offsetBy: layout.characterStarts[line])
        let upper = value.characters.index(lower, offsetBy: layout.lines[line].count)
        var styles: [EditorStyledRun] = []
        var column = 0
        for run in value[lower..<upper].runs {
            let length = value[run.range].characters.count
            defer { column += length }
            if let styled = EditorStyledRun(value[run.range], columns: column..<(column + length), styling: styling) {
                styles.append(styled)
            }
        }
        return styles
    }

    /// Holds the attributes of `span`'s first character for the text typed
    /// over it, which is inserted after the span is removed (B-ATTRED-16).
    func holdTypingAttributes(over span: SelectionSpan) {
        let layout = layout()
        let start = min(layout.characterOffset(of: span.start), layout.characterOffset(of: span.end))
        attributedSource?.holdTypingAttributes(ofCharacterAt: start)
    }

    /// Holds `span`'s text, with its runs, for its insertion where it is moved
    /// to (``AttributedTextSource/heldInsertion``).
    func holdMovedText(_ span: SelectionSpan) {
        let layout = layout()
        let (start, end) = (layout.characterOffset(of: span.start), layout.characterOffset(of: span.end))
        attributedSource?.holdInsertion(ofCharacters: min(start, end)..<max(start, end))
    }

    /// The channel an attributed editor exchanges its selection with the app's
    /// `AttributedTextSelection` binding by, in character offsets; `nil` with
    /// no binding.
    var attributedSelectionChannel: _TextSelectionChannel? {
        guard let source = attributedSource, source.selection != nil else { return nil }
        return _TextSelectionChannel(
            read: { [weak source] _, _ in
                guard let source, let chosen = source.selection?.wrappedValue else { return nil }
                if let published = source.published, published.selection == chosen { return published.offsets }
                let value = source.value
                let range: Range<AttributedString.Index>
                switch chosen.indices(in: value) {
                case .insertionPoint(let caret): range = caret..<caret
                case .ranges(let ranges): range = ranges.ranges[0]
                }
                let lower = value.characters.distance(from: value.startIndex, to: range.lowerBound)
                return lower..<(lower + value.characters.distance(from: range.lowerBound, to: range.upperBound))
            },
            write: { [weak self, weak source] offsets, _, affinity, _ in
                guard let self, let source else { return }
                let value = source.value
                let lower = value.characters.index(value.startIndex, offsetBy: offsets.lowerBound)
                let upper = value.characters.index(lower, offsetBy: offsets.count)
                var chosen = AttributedTextSelection(range: lower..<upper)
                // The lean the editor's keys leave, as `affinity(in:)` reports
                // it (B-ATTRED-17), unless the editor states one.
                chosen.lean = affinity == .automatic ? caretLean : affinity
                source.published = (chosen, offsets)
                if source.selection?.wrappedValue != chosen { source.selection?.wrappedValue = chosen }
            })
    }
}

extension EditorStyledRun {
    /// `run`, a stretch of an `AttributedString` drawn alike, over `columns`,
    /// as an editor drawing under `styling` draws it — its colours resolved, a
    /// font's tier and weight as bold or faint, italic, its lines fitted to
    /// the terminal, a link in the accent and underlined — or `nil` where it
    /// states nothing an editor draws.
    init?(_ run: AttributedSubstring, columns: Range<Int>, styling: EditorAttributedStyling) {
        var cell = Text.cellStyle(of: run, environmentFont: styling.font)
        if run.link != nil {
            cell.foreground = cell.foreground ?? styling.accent
            if cell.underline == nil, styling.linkUnderline { cell.underline = .single }
        }
        let decoration = CellDecoration(
            isBold: cell.isBold, isDim: cell.isDim, isItalic: cell.isItalic, underline: cell.underline,
            strikethrough: cell.strikethrough)
        guard cell.foreground != nil || cell.background != nil || decoration != CellDecoration() else { return nil }
        let palette = styling.palette
        self.init(
            columns: columns, foreground: cell.foreground?.resolve(with: palette),
            background: cell.background?.resolve(with: palette),
            decoration: decoration.fitted(to: styling.lineStyleSupport, palette: palette))
    }
}
