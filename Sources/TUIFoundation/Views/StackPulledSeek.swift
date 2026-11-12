//  🖥️ TUI — A Terminal UI framework for Swift
//  StackPulledSeek.swift
//
//  A `scrollTo` resolved against a pulled column (`StackPulledColumn.swift`):
//  a row of its own becomes the anchor; a row that holds the key below it
//  (`StackNestedSeek.swift`) is aimed into when it is drawn whole, and handed
//  the seek when it is pulled, the column's lines then moved by where the
//  row's own seek put the viewport.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// What a seek hands the row it was routed to: the request, and the content
/// the column estimates above and below that row.
typealias HandedSeek = (request: ScrollToRequest, linesAbove: Int, linesBelow: Int)

/// A seek's part in a pulled column's frame.
enum PulledSeek {
    /// The column moved its viewport to this offset: to one of its own rows,
    /// or to a place in a row it draws whole.
    case moved(Int)
    /// The row the anchor was moved to is pulled and holds the key below it,
    /// and is handed the seek. Its top is at line `top` of this column, where
    /// the column estimates it, and stays there: the seek moves the viewport.
    /// `inPlace` when the row held the anchor already: it is handed its own
    /// position, so it seeks from the rows it shows.
    case handed(HandedSeek, top: Int, inPlace: Bool)

    var handed: HandedSeek? {
        guard case .handed(let seek, _, _) = self else { return nil }
        return seek
    }

    /// What the handed row's request counts from: its own position when it
    /// held the anchor, else its top.
    var handedEdge: PullEdge? {
        guard case .handed(_, _, let inPlace) = self else { return nil }
        return inPlace ? .position : .top
    }
}

@MainActor extension _VStackCore {
    /// A pending `scrollTo`, resolved against this column. A row of its own
    /// becomes the anchor, on the line the request's alignment puts it; so
    /// does a row that holds the key below it (`StackNestedSeek.swift`): drawn
    /// whole, aimed at where the key lies in it; pulled, handed the seek at
    /// the viewport's place in it, for it to resolve among its own rows.
    /// `nil` when nothing is sought or nothing here holds the key.
    func resolvePulledSeek(
        frame: PulledColumnFrame, window: inout ScrollContentWindow, width: Int
    ) -> PulledSeek? {
        guard let seek = window.seek else { return nil }
        window.seek = nil
        let target: NestedSeekTarget
        if let focusID = seek.focusID {
            // A focus reveal: the child the focused control lies in, by its
            // route; handed on when pulled, else shown whole.
            guard let ordinal = pulledChild(holding: focusID, frame: frame, context: frame.context) else { return nil }
            if frame.isPulled(ordinal) { return handPulledSeek(seek, to: ordinal, frame: frame, window: window) }
            target = NestedSeekTarget(ordinal: ordinal, y: 0, height: frame.height(of: ordinal))
        } else if let own = resolveOrdinal(forKey: seek.key, children: frame.children, state: frame.state) {
            target = NestedSeekTarget(ordinal: own, y: 0, height: frame.height(of: own))
        } else {
            guard
                let ordinal = NestedSeek.row(
                    holding: seek.key, count: frame.rowCount, child: frame.child(at:), width: width,
                    context: frame.context)
            else { return nil }
            if frame.isPulled(ordinal) { return handPulledSeek(seek, to: ordinal, frame: frame, window: window) }
            let height = frame.height(of: ordinal)
            let place = NestedSeek.place(
                of: seek.key, in: frame.child(at: ordinal), width: width, height: height, context: frame.context)
            target = NestedSeekTarget(ordinal: ordinal, y: place?.y ?? 0, height: place?.height ?? height)
        }
        let top = pulledRowTop(target.ordinal, frame: frame, window: window)
        let line = NestedSeek.line(
            for: seek, height: target.height, current: top + target.y - window.offset,
            viewportHeight: window.viewportHeight)
        let offset = max(-window.linesAbove, top + target.y - line)
        frame.anchor.ordinal = target.ordinal
        frame.anchor.key = frame.key(at: target.ordinal)
        frame.anchor.within = offset - top
        frame.anchor.derivedOffset = offset
        window.offset = offset
        return .moved(offset)
    }

    /// Moves the anchor to row `ordinal`, pulled, which holds `seek`'s key
    /// below it, at the viewport's place in it — its own position when it held
    /// the anchor already, else where the column estimates it — and hands it
    /// the seek with the content the column estimates above and below it, the
    /// lines a seek's clamp and indicator headroom read.
    private func handPulledSeek(
        _ seek: ScrollToRequest, to ordinal: Int, frame: PulledColumnFrame, window: ScrollContentWindow
    ) -> PulledSeek {
        // Where the row is: the viewport's top `from` lines below its top. A
        // row far off screen is handed a place a screen off its near edge
        // instead: an offset tens of thousands of lines off is not one a
        // stack can place a band at, and the side is all a seek reads of it.
        let holdsAnchor = ordinal == frame.anchor.ordinal && frame.state.pulledAnchorRow?.ordinal == ordinal
        let top =
            holdsAnchor ? window.offset - frame.anchor.within : pulledRowTop(ordinal, frame: frame, window: window)
        let from =
            holdsAnchor
            ? frame.anchor.within
            : min(max(window.offset - top, -window.viewportHeight), frame.height(of: ordinal))
        let total =
            frame.walksJumps
            ? (0..<frame.rowCount).reduce(0) { $0 + frame.pitch(of: $1) } : frame.rowCount * frame.estimatedPitch
        frame.anchor.ordinal = ordinal
        frame.anchor.key = frame.key(at: ordinal)
        frame.anchor.within = from
        frame.anchor.derivedOffset = window.offset
        let below = max(0, total - top - frame.height(of: ordinal))
        return .handed((seek, window.linesAbove + top, window.linesBelow + below), top: top, inPlace: holdsAnchor)
    }

    /// Row `ordinal`'s top in this column's lines, as a seek reads it: the
    /// rows above it summed where the walk measures across a jump too, or the
    /// row lies within a screen of rows of the top; else counted from the
    /// anchor (``ScrollFillColumn/viewportLine(ofRow:viewportHeight:)``).
    private func pulledRowTop(_ ordinal: Int, frame: PulledColumnFrame, window: ScrollContentWindow) -> Int {
        if frame.walksJumps || ordinal < window.viewportHeight {
            return (0..<ordinal).reduce(0) { $0 + frame.pitch(of: $1) }
        }
        return window.offset + frame.viewportLine(ofRow: ordinal, viewportHeight: window.viewportHeight)
    }
}
