//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledBand.swift
//
//  SCROLL-FIT's pull (design P3), for a view outside this module that knows
//  where every one of its lines falls without building them — `List` and
//  `Table` at a fixed pitch — and so draws only the lines of itself a scroll
//  view shows: the request a column (or the scroll view) hands it, read as a
//  band of its lines, and the reply that says what it drew. The lazy stack
//  answers the same request with its own anchored walk
//  (`StackAnchoredWindow.swift`); a view at a fixed pitch needs no walk, its
//  total being arithmetic, so the request is read here once for all of them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// What a pulled request asks of a view that knows its total height: the
/// lines of it to draw, and where the viewport's top fell in it.
///
/// Read by ``RenderContext/pulledBandRequest()``, resolved against the view's
/// total with ``band(total:seekLine:)`` and answered with ``answer(_:)``.
@MainActor
package struct PulledBandRequest {
    fileprivate let window: ScrollContentWindow
    fileprivate let context: RenderContext

    /// The scroll view's viewport, in lines: what a page key moves by in a
    /// view that does not scroll itself (B-SCROLLFIT-5).
    package var viewportHeight: Int { window.viewportHeight }

    /// The key or the focus a `scrollTo` or a focus reveal names, when this
    /// request carries one.
    package var seek: ScrollToRequest? { window.seek }

    /// The lines of a view `total` lines tall this request asks it to draw.
    ///
    /// The viewport's top is placed from the request's edge: the view's own
    /// position, its top or its end (``PullEdge``). A seek moves it: a key's
    /// line (`seekLine` answers the line and the height of what the request's
    /// key or focus names, `nil` for a key the view does not hold) is put
    /// where the request's anchor says, by the rule every seek path shares
    /// (``ScrollContentWindow/offset(realising:targetY:rowHeight:stackHeight:)``).
    /// The band is the viewport's lines within the view, or, where the
    /// viewport misses the view (a column draws a child a line past the
    /// viewport, or one off its band for its place in the focus ring), the one
    /// line nearest it.
    package func band(total: Int, seekLine: (ScrollToRequest) -> (y: Int, height: Int)?) -> PulledBand {
        let total = max(1, total)
        var position: Int
        switch window.edge {
        case .position, .top: position = window.offset
        case .end: position = total + window.offset
        }
        var resolvedSeek = false
        if let seek = window.seek, let target = seekLine(seek) {
            var placed = window
            placed.offset = position
            position = placed.offset(
                realising: seek, targetY: target.y, rowHeight: target.height, stackHeight: total)
            resolvedSeek = true
        }
        let top = min(max(position, 0), total)
        let bottom = min(max(position + window.viewportHeight, 0), total)
        let lines: Range<Int> =
            top < bottom ? top..<bottom : position + window.viewportHeight <= 0 ? 0..<1 : (total - 1)..<total
        return PulledBand(position: position, lines: lines, total: total, resolvedSeek: resolvedSeek)
    }

    /// Says what the view drew to the column or scroll view that asked: the
    /// band's place in the view, the view's height, which of its ends the
    /// band holds and where the viewport's top fell (and, when a seek moved
    /// it, that it did).
    package func answer(_ band: PulledBand) {
        guard let reply = window.reply else { return }
        reply.sliceOriginY = band.lines.lowerBound
        reply.sliceTotalHeight = band.total
        reply.sliceTotalIsEstimate = false
        reply.sliceHoldsFirstRow = band.lines.lowerBound == 0
        reply.sliceHoldsLastRow = band.lines.upperBound == band.total
        if band.resolvedSeek {
            window.reportResolvedOffset(band.position, isHold: false)
        }
        if window.isPulled { reply.pulledPosition = band.position }
        ScrollContentReply.journal(from: context)
    }

    /// Tells the scroll view the height the view's measure answered was wrong
    /// — its rows were not the pitch it took them for — so it measures again
    /// and draws the frame anew (``ScrollContentReply/measureWentStale``).
    package func measureWentStale() {
        window.reply?.measureWentStale = true
    }
}

/// The lines of a view a pulled request asks it to draw
/// (``PulledBandRequest/band(total:seekLine:)``).
package struct PulledBand: Sendable, Equatable {
    /// Where the viewport's top falls in the view's lines: negative above its
    /// top, past its end below it.
    package let position: Int
    /// The view's lines to draw, within `0..<total`, never empty.
    package let lines: Range<Int>
    /// The view's height in lines.
    package let total: Int
    /// Whether a seek moved ``position``.
    package let resolvedSeek: Bool
}

@MainActor extension RenderContext {
    /// The pulled request addressed to the view at this context's identity —
    /// handed on by a column, or the scroll view's own window when the view is
    /// its content — or `nil` when none reaches it, and while measuring.
    package func pulledBandRequest() -> PulledBandRequest? {
        guard !isMeasuring, let window = environment.scrollContentWindow, window.reply != nil,
            window.isAtOrigin(identity)
        else { return nil }
        return PulledBandRequest(window: window, context: self)
    }

    /// Whether a column pulls a view at this context's identity, wherever it
    /// stands in a scroll view's content: every container that holds it among
    /// siblings places a pulled child (`_VStackCore.isPulledWhereItStands`,
    /// which this asks for a view outside this module).
    package var isPulledWhereItStands: Bool {
        pullReachesIdentity()
    }

    /// Files the view at this context's identity as one that draws a band of
    /// its own lines against a request (``PullConsumers/Kind/bandsRows``), or
    /// withdraws it: a column above then hands it a request. Only in scroll
    /// content, where there is a request to pull by.
    package func notePulledBand(_ bands: Bool) {
        guard scrollContentOriginDepth != 0, let cache = renderCache else { return }
        cache.pullConsumers.note(identity, as: bands ? .bandsRows : nil)
    }
}

extension FrameBuffer {
    /// The focus regions of a control drawn as `band`, lines of its own
    /// `total`, as they would be were it drawn whole: its whole-control
    /// region (the tallest carrying `focusID`) reaches, for a reveal, every
    /// line of it outside the band (``HitTestRegion/revealOutsetTop``), so
    /// tabbing to it shows it as tabbing to it drawn whole does; and its
    /// cursor's line, where the band leaves it out, is marked by a one-line
    /// region at its place outside the band, so a key that moves the cursor
    /// past the band has the scroll view reveal it (SCROLL-FIT 1e: off the
    /// band a list draws only its cursor row's marker). The marker takes the
    /// whole-control region's handler, at the front of the regions, where a
    /// click never reaches it before that one — and no line of the band
    /// holds it.
    package mutating func markPulledControl(focusID: String, band: Range<Int>, total: Int, cursorLine: Int?) {
        let carrying = hitTestRegions.indices.filter {
            hitTestRegions[$0].focusID == focusID && !hitTestRegions[$0].isGeometryMarker
        }
        guard let whole = carrying.max(by: { hitTestRegions[$0].height < hitTestRegions[$1].height }) else { return }
        var region = hitTestRegions[whole]
        region.revealOutsetTop = max(region.revealOutsetTop, region.offsetY + band.lowerBound)
        region.revealOutsetBottom = max(
            region.revealOutsetBottom, total - band.lowerBound - region.offsetY - region.height)
        hitTestRegions[whole] = region
        guard let cursorLine, cursorLine >= 0, cursorLine < total, !band.contains(cursorLine) else { return }
        hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: cursorLine - band.lowerBound, width: width, height: 1,
                handlerID: region.handlerID, focusID: focusID),
            at: 0)
    }
}

// MARK: - The switch

private struct ScrollFitsContentKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// SCROLL-FIT's switch (B-SCROLLFIT-10): whether `List` and `Table` in a
    /// scroll view's content take their content's height and draw only the
    /// lines on screen, pulled as a lazy stack is. Off by default until P7
    /// turns it on and deletes it, so no compatibility spelling survives; set
    /// by the lanes' tests. Package-internal on purpose: it is not public API.
    package var scrollFitsContent: Bool {
        get { self[ScrollFitsContentKey.self] }
        set { self[ScrollFitsContentKey.self] = newValue }
    }
}
