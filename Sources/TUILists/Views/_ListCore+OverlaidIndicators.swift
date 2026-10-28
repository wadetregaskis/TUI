//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+OverlaidIndicators.swift
//
//  A list's indicators drawn over its rows while the pointer is over it,
//  under `.scrollIndicatorPlacement(.overContent)` — see
//  `ScrollIndicatorPlacement.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

extension _ListCore {
    /// Watches the pointer come and go over the list, for indicators drawn
    /// over its rows: a list it enters draws them, one it leaves takes them
    /// away. An observer, so the rows keep their own hover.
    func attachIndicatorHoverObserver(
        to buffer: inout FrameBuffer, handler: ItemListHandler<SelectionValue>,
        dispatcher: MouseEventDispatcher, context: RenderContext
    ) {
        guard context.environment.scrollIndicatorsOverlayContent else { return }
        // Motion reports, which a terminal sends only when asked: hover is made of them.
        dispatcher.requestFeature(.motion, in: context)
        let drawing = HandlerDrawing(context)
        let handlerID = dispatcher.registerHoverObserver(in: context) { event in
            switch event.phase {
            case .entered where !handler.isPointerOver:
                handler.isPointerOver = true
                drawing.changed()
            case .exited where handler.isPointerOver:
                handler.isPointerOver = false
                drawing.changed()
            default:
                break
            }
            // Claims nothing: clicks, the wheel and the rows' hover go on.
            return false
        }
        buffer.hitTestRegions += buffer.frameHitRegions(handlerID: handlerID)
    }

    /// `lines` with the "N more" lines written over the first and the last,
    /// where rows are hidden that way, while ``ItemListHandler/overlaysTextIndicators``:
    /// the runs and claims of the lines they cover go with them, or a row's
    /// breathing would replay over the indicator.
    func overlayingTextIndicators(
        _ composed: (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]),
        hidden: (above: Int, below: Int), handler: ItemListHandler<SelectionValue>, rowWidth: Int,
        listHasFocus: Bool, context: RenderContext
    ) -> (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion]) {
        let (hiddenAbove, hiddenBelow) = hidden
        guard handler.overlaysTextIndicators, composed.lines.count >= ResolvedScrollIndicators.minimumTextHeight,
            hiddenAbove > 0 || hiddenBelow > 0
        else { return composed }
        let environment = context.environment
        let cycle = scrollIndicatorCycle(isFocused: listHasFocus, context: context)
        var (lines, runs, claims) = composed
        func cover(_ row: Int, direction: ScrollIndicatorDirection, count hidden: Int) {
            let line = renderScrollIndicator(
                direction: direction, count: hidden, unit: .rows, width: rowWidth, palette: environment.palette,
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
}
