//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+OverlaidIndicators.swift
//
//  A text editor's scroll bar drawn over its text while the pointer is over
//  it, under `.scrollIndicatorPlacement(.overContent)` — see
//  `ScrollIndicatorPlacement.swift`. The text was laid out at the whole width,
//  nothing reserved; the bar covers its last column, drawn as it is beside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// An editor's rows as drawn, before its scroll bar joins them: their lines,
/// the claims on them, and the caret's run.
struct _EditorDrawnRows {
    var lines: [String]
    var claims: [OpacityRegion]
    var caret: AnimatedCellRun?
}

extension _TextEditorCore {
    /// The column an overflowing editor draws its scroll bar at this frame —
    /// `nil` where it draws none.
    ///
    /// Beside the text, the bar's own column, which the window left it past
    /// `contentWidth`. Over the text (`.overContent`), the text's last column,
    /// and only while the pointer is over the editor: `drawn` is cut back to
    /// the columns before it, its claims and the caret's run with it.
    ///
    /// The bar is the editor's own, shown whenever the text overflows whatever
    /// `.scrollIndicators(_:)` says, beside the text or over it alike.
    ///
    /// - Parameters:
    ///   - drawn: The rows as drawn.
    ///   - contentWidth: The width the text was laid out at.
    ///   - overText: Whether the bar is drawn over the text
    ///     (`scrollIndicatorsOverlayContent`, read once by the caller).
    ///   - handler: The editor's handler, which knows where the pointer is.
    ///   - context: The editor's context.
    func scrollbarColumn(
        clearing drawn: inout _EditorDrawnRows,
        contentWidth: Int, overText: Bool, handler: TextEditorHandler, context: RenderContext
    ) -> Int? {
        guard overText else { return contentWidth }
        let barWidth = context.environment.scrollbarWidth
        guard handler.isPointerOver, contentWidth > barWidth else { return nil }
        let column = contentWidth - barWidth
        let cut = clearingTrailingColumns((drawn.lines, drawn.caret.map { [$0] } ?? [], drawn.claims), keeping: column)
        drawn = _EditorDrawnRows(lines: cut.lines, claims: cut.claims, caret: cut.runs.first)
        return column
    }
}
