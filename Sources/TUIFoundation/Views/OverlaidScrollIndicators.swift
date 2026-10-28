//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlaidScrollIndicators.swift
//
//  What every scrolling view that draws its indicators over its content
//  (`.scrollIndicatorPlacement(.overContent)`, see
//  `ScrollIndicatorPlacement.swift`) does the same way: watch the pointer come
//  and go, and write the "N more" lines over the content's first and last
//  lines. One copy, so the views cannot drift apart in how they do it.
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
