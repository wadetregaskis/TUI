//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlaidScrollIndicators.swift
//
//  What every scrolling view that draws its indicators over its content
//  (`.scrollIndicatorPlacement(.overContent)`, see
//  `ScrollIndicatorPlacement.swift`) does the same way: watch the pointer come
//  and go, write the "N more" lines over the content's first and last lines,
//  and draw a bar over the last columns of content composed as lines. One
//  copy, so the views cannot drift apart in how they do it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A scrolling view's memory of whether the pointer is over it: its indicators
/// are drawn over its content while it is, under
/// ``ScrollIndicatorPlacement/overContent``.
package protocol ScrollIndicatorPointerTracking: AnyObject {
    /// Whether the pointer is over the view.
    var isPointerOver: Bool { get set }
}

extension FrameBuffer {
    /// Watches the pointer come and go over this buffer, for indicators drawn
    /// over the content: a view it enters draws them, one it leaves takes them
    /// away. An observer, so the content keeps its own hover — a list's rows, a
    /// scroll view's controls.
    ///
    /// Does nothing unless the subtree places its indicators over the content,
    /// and nothing in a measure pass.
    ///
    /// Call it after every region the view and its content have filed, so the
    /// observer stands in front of them: the dispatcher looks for observers
    /// only in front of the first control under the pointer, and one behind a
    /// row's button, say, would hear the pointer leave as it reached it.
    ///
    /// - Parameters:
    ///   - tracker: The view's handler, which remembers where the pointer is.
    ///   - context: The context the view is rendered in.
    @MainActor
    package mutating func observePointerForOverlaidIndicators(
        of tracker: some ScrollIndicatorPointerTracking, context: RenderContext
    ) {
        guard context.environment.scrollIndicatorsOverlayContent, !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else { return }
        // Motion reports, which a terminal sends only when asked: hover is made of them.
        dispatcher.requestFeature(.motion, in: context)
        let drawing = HandlerDrawing(context)
        let handlerID = dispatcher.registerHoverObserver(in: context) { event in
            switch event.phase {
            case .entered where !tracker.isPointerOver:
                tracker.isPointerOver = true
                drawing.changed()
            case .exited where tracker.isPointerOver:
                tracker.isPointerOver = false
                drawing.changed()
            default:
                break
            }
            // Claims nothing: clicks, the wheel and the content's own hover go
            // on to what is under the pointer.
            return false
        }
        hitTestRegions += frameHitRegions(handlerID: handlerID)
    }
}

/// `composed` with the "N more" lines written over its first and last lines,
/// where rows are hidden that way — the lines a view drawing its indicators
/// over its content writes for the pointer. The runs and claims of the lines
/// they cover go with them, or a row's breathing would replay over the
/// indicator.
///
/// Draws nothing on fewer than ``ResolvedScrollIndicators/minimumTextHeight``
/// lines, where the indicators would cover every row there is.
///
/// - Parameters:
///   - composed: The content's lines, and their runs and claims, in the lines'
///     coordinates.
///   - hidden: The rows hidden above and below.
///   - width: The width the indicator lines are drawn at: the content's.
///   - isFocused: Whether the view indicates the focus — a focused view's
///     indicators breathe.
///   - context: The context the view is rendered in.
@MainActor
package func overlayingScrollIndicatorLines(
    _ composed: (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]),
    hidden: (above: Int, below: Int), width: Int, isFocused: Bool, context: RenderContext
) -> (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]) {
    let (hiddenAbove, hiddenBelow) = hidden
    guard composed.lines.count >= ResolvedScrollIndicators.minimumTextHeight, hiddenAbove > 0 || hiddenBelow > 0
    else { return composed }
    let environment = context.environment
    let cycle = scrollIndicatorCycle(isFocused: isFocused, context: context)
    var (lines, runs, claims) = composed
    func cover(_ row: Int, direction: ScrollIndicatorDirection, count hidden: Int) {
        let line = renderScrollIndicator(
            direction: direction, count: hidden, unit: .rows, width: width, palette: environment.palette,
            cycle: cycle, over: environment.enclosingSurface, locale: environment.locale)
        lines[row] = line.text
        runs.removeAll { $0.offsetY == row }
        claims.removeAll { $0.offsetY == row && $0.height == 1 }
        if let animation = line.animation { runs.append(animation.shifted(byX: 0, y: row)) }
        claims += line.claims(atRow: row)
    }
    if hiddenAbove > 0 { cover(0, direction: .up, count: hiddenAbove) }
    if hiddenBelow > 0 { cover(lines.count - 1, direction: .down, count: hiddenBelow) }
    return (lines, runs, claims)
}

/// `composed` cut back to its first `column` columns, the room a vertical
/// scrollbar drawn over its last columns leaves it: each line cut there (and
/// padded to it), and the runs and claims cut with them, or a row's breathing
/// would replay over the bar. What ``overlayingVerticalScrollbar(_:bar:width:)``
/// does before it draws the bar, for content whose bar is drawn another way.
///
/// - Parameters:
///   - composed: The content's lines, and their runs and claims, in the lines'
///     coordinates.
///   - column: The columns kept: the bar's first column.
package func clearingTrailingColumns(
    _ composed: (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]), keeping column: Int
) -> (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]) {
    let columns = 0..<max(0, column)
    return (
        composed.lines.map { line in
            let (kept, keptWidth) = line.ansiAwarePrefixWithWidth(visibleCount: columns.count)
            return kept + String.spaces(max(0, columns.count - keptWidth))
        },
        composed.runs.compactMap { $0.clipped(toColumns: columns) },
        composed.claims.compactMap { $0.clipped(toColumns: columns, rows: $0.offsetY..<($0.offsetY + $0.height)) })
}

/// `composed` with a vertical scrollbar drawn over its last columns — the
/// bar a view drawing its indicators over its content draws for the pointer,
/// one cell of `bar` on each line, over content cut back by
/// ``clearingTrailingColumns(_:keeping:)``.
///
/// For content composed as lines (a table's rows), where ``ScrollView``
/// covers a buffer instead.
///
/// - Parameters:
///   - composed: The content's lines, and their runs and claims, in the lines'
///     coordinates.
///   - bar: The bar's cells, one line for each of the content's: fitted by
///     the caller, which knows what the track below a short bar is painted.
///   - width: The content's width: the bar covers its last `bar.width`
///     columns.
/// - Returns: The content with the bar drawn over it, and the column the bar
///   starts at — `nil` where the content is no wider than the bar.
package func overlayingVerticalScrollbar(
    _ composed: (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]),
    bar: ClaimingColumn, width: Int
) -> (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion], column: Int)? {
    guard width > bar.width else { return nil }
    let column = width - bar.width
    let cut = clearingTrailingColumns(composed, keeping: column)
    var lines = cut.lines
    for index in lines.indices where index < bar.count { lines[index] += bar.lines[index] }
    return (lines, cut.runs, cut.claims + bar.claims(atColumn: column), column)
}
