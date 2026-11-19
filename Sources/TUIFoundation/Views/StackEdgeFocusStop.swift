//  🖥️ TUI — A Terminal UI framework for Swift
//  StackEdgeFocusStop.swift
//
//  The walk into a windowed stack from one of its edges: the focusable row
//  nearest the edge the focus comes in by, however far, and what keeps it
//  from being walked again for the same rows (split out of
//  `StackFocusReach.swift`, whose probe it walks with).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

@MainActor extension _VStackCore {
    /// The focusable row nearest this stack's `edge`, which the focus comes
    /// into the stack at from just past that edge — from outside the scroll
    /// view or from a neighbour in a pulled column — or `nil` when no row has
    /// anything to focus.
    ///
    /// Walked in from the edge row by row, with no cap, however far the first
    /// row that registers a focusable lies, and holding the frame while it
    /// does (owner, 2026-11-17: synchronous, no time cap, nothing carried to a
    /// later frame; revisit only with a real case that needs it). The
    /// continuations beside the focused row keep their cap: they run on every
    /// frame the focus is in the stack, this only on the frames the focus
    /// stands just outside it.
    ///
    /// Two things keep the walk from being repeated for nothing:
    /// - A stack with nothing to focus is walked once, not on every Tab past
    ///   it: the walk that finds nothing has asked every row, and the answer
    ///   is kept for the rows' data (``StackWindowState/focuslessRows``, by
    ///   ``StackWindowState/rowsVersion``) until it changes. Rows that only
    ///   grew (a log, `0..<n` with `n` rising) walk only the rows they gained.
    ///   A row that comes to hold a focusable with its data unchanged (one
    ///   enabled by state outside the rows) is not seen until then. Rows
    ///   with no data signature (data that is not `Equatable`, a flow
    ///   layout's lines) are kept by their count, since nothing else names
    ///   them: walked again on every frame, a flow of 10,000 items under a
    ///   focused scroll view built all 10,000 for every wheel step.
    /// - A row found is kept for the rows' data too
    ///   (``StackWindowState/edgeStopsByVersion``): the walk is asked on every
    ///   frame the focus stands beside the stack (owner, 2026-11-18: "(b)", the
    ///   walk made before the key), and walked each time it went from the edge
    ///   to the row again. Only that row is asked again, to see it still has
    ///   something to focus; a row before it that comes to have something with
    ///   the data unchanged is not seen until the data changes, as for a stack
    ///   with nothing to focus. Rows with no data signature are walked each
    ///   time.
    /// - The scroll view may draw its content more than once in a frame (a
    ///   reveal, a band that did not cover the offset), and each drawing asks
    ///   again: the answer is kept for the frame
    ///   (``StackWindowState/edgeStopsOfFrame``).
    func edgeFocusStop(
        _ edge: VerticalEdge, count: Int, child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        state: StackWindowState, rows: AnyEquatableBox?, context: RenderContext
    ) -> Int? {
        guard count > 0 else { return nil }
        let version = rows.map { state.rowsVersion.token(for: $0) }
        // The rows known to have nothing to focus: all of them, or the ones
        // these rows began with.
        var known = 0
        if let kept = state.focuslessRows {
            if kept.version == version, version != nil || kept.count == count { return nil }
            if let rows, let keptRows = kept.rows, kept.count <= count, rows.extends(keptRows) { known = kept.count }
        }
        let frame = context.environment.focusManager?.focusRenderGeneration
        if let frame, let kept = state.edgeStopsOfFrame, kept.frame == frame, kept.count == count,
            let stop = kept.stops[edge]
        {
            return stop
        }
        let isolated = probeContext(context)
        let direction = edge == .top ? 1 : -1
        var stop: Int?
        if let version, let kept = state.edgeStopsByVersion[edge], kept.version == version, kept.count == count {
            // The row found for these rows, if it still has something to focus.
            stop = nearestFocusableRow(
                from: kept.stop - direction, direction: direction, within: kept.stop..<(kept.stop + 1), cap: 1,
                child: child, width: width, viewportHeight: viewportHeight, isolated: isolated)
        }
        if stop == nil {
            stop = nearestFocusableRow(
                from: edge == .top ? known - 1 : count, direction: direction, within: known..<count, cap: nil,
                child: child, width: width, viewportHeight: viewportHeight, isolated: isolated)
        }
        if stop == nil { state.focuslessRows = (version, rows, count) }
        state.edgeStopsByVersion[edge] = version.flatMap { version in stop.map { (version, count, $0) } }
        if let frame {
            var kept = state.edgeStopsOfFrame.flatMap { $0.frame == frame && $0.count == count ? $0 : nil }
                ?? (frame: frame, count: count, stops: [:])
            kept.stops[edge] = .some(stop)
            state.edgeStopsOfFrame = kept
        }
        return stop
    }
}
