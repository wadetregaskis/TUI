//  🖥️ TUI — A Terminal UI framework for Swift
//  Table+OverlaidIndicators.swift
//
//  A table's indicators drawn over its rows while the pointer is over it,
//  under `.scrollIndicatorPlacement(.overContent)` — see
//  `ScrollIndicatorPlacement.swift`. The rows were laid out at the whole
//  width, nothing reserved; the bar covers their last column and the "N more"
//  lines their first and last lines, drawn as they are beside the rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUILists

/// A table's rows as a content path composed them: their lines, the runs and
/// claims on those lines, and what the rows' view cells registered — all in
/// the lines' coordinates.
struct _TableDrawnRows {
    var lines: [String]
    var runs: [AnimatedCellRun]
    var claims: [OpacityRegion]
    var payload: _TableRowPayload
}

extension ItemListHandler {
    /// Draws this frame's overlaid indicators (``overlaysScrollbar``,
    /// ``overlaysTextIndicators``) over a table's composed rows, both content
    /// paths alike. The regions of the rows' view cells under them go, so a
    /// press there reaches the bar.
    ///
    /// - Parameters:
    ///   - rows: The composed rows.
    ///   - width: The rows' width: the bar covers their last column.
    ///   - hidden: The rows hidden above and below, for the "N more" lines.
    ///   - isFocused: Whether the table indicates the focus.
    ///   - context: The table's context.
    ///   - bar: The bar's cells, built only when a bar is drawn.
    /// - Returns: The column of the rows' lines the bar was drawn at, for its
    ///   mouse handler, or `nil` when no bar was drawn.
    @MainActor
    func overlayIndicators(
        on rows: inout _TableDrawnRows, width: Int, hidden: (above: Int, below: Int), isFocused: Bool,
        context: RenderContext, bar: () -> ClaimingColumn
    ) -> Int? {
        if overlaysTextIndicators, rows.lines.count >= ResolvedScrollIndicators.minimumTextHeight {
            (rows.lines, rows.runs, rows.claims) = overlayingScrollIndicatorLines(
                (rows.lines, rows.runs, rows.claims), hidden: hidden, width: width, isFocused: isFocused,
                context: context)
            let top = hidden.above > 0 ? 1 : 0
            let bottom = rows.lines.count - (hidden.below > 0 ? 1 : 0)
            rows.payload = rows.payload.clipped(toRows: top..<max(top, bottom))
        }
        guard overlaysScrollbar else { return nil }
        var cells = bar()
        cells.fit(toCount: rows.lines.count, field: ScrollbarColors.track(in: context.environment.palette))
        guard let overlaid = overlayingVerticalScrollbar((rows.lines, rows.runs, rows.claims), bar: cells, width: width)
        else { return nil }
        (rows.lines, rows.runs, rows.claims) = (overlaid.lines, overlaid.runs, overlaid.claims)
        rows.payload = rows.payload.clipped(toColumns: 0..<overlaid.column)
        return overlaid.column
    }
}

extension ScrollRowWindow {
    /// The rows this window hides above and below, out of `count` — at least
    /// one above where only part of the first row is hidden — for the "N more"
    /// lines drawn over a multi-line table's rows.
    func hiddenRows(of count: Int) -> (above: Int, below: Int) {
        (showsAbove ? max(1, range.lowerBound) : 0, showsBelow ? count - range.upperBound : 0)
    }
}
