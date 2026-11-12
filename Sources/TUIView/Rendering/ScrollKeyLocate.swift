//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollKeyLocate.swift
//
//  SCROLL-FIT's locate by route (design B-SCROLLFIT-15, A-SCROLLFIT-4 (b)): a
//  `scrollTo` whose key no row of the container that resolves it carries is
//  searched for below its rows, rows never built included, by measuring them
//  for the search alone — and once found in a row drawn whole, placed in it
//  by drawing that row for the place alone. Neither draws anything on screen,
//  runs an `onAppear` or registers a focusable (`RenderContext.isMeasuring`),
//  or reads or writes a memo (`RenderContext.renderCache` is `nil`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// One search for a `scrollTo` key, carried in the environment of the
/// measures and the drawing it makes.
///
/// A search measures a container's rows with this in their environment and no
/// render cache in their context. A stack measured so answers nothing of its
/// size: it looks for the key among its own rows — by the data's keys, never
/// building a row — and, while ``depth`` allows, measures its rows in turn,
/// one level down. A place is found by drawing the row the key was found in
/// with ``marksTarget`` set: the child the key names stamps two markers on what
/// it draws (``HitTestRegion/HandlerID/seekTargetTop``,
/// ``HitTestRegion/HandlerID/seekTargetEnd``), which every container moves
/// with what it draws, so the row's own drawing says where the key's view is
/// in it, and how tall, whatever lies between.
@MainActor
package final class ScrollKeyLocate {
    /// The key sought, as `ForEach` and `.id(_:)` spell it.
    package let key: String
    /// How many levels of stacks below the one measured may still be searched:
    /// at zero a stack looks only among its own rows.
    package var depth = 0
    /// Whether the key was found.
    package var found = false
    /// Whether a stack at the last level searched had rows below which the key
    /// might be: a deeper search could find what this one did not.
    package var hasDeeperRows = false
    /// Whether the search is placing the key rather than looking for it: the
    /// child the key names marks what it draws.
    package var marksTarget = false

    package init(key: String) {
        self.key = key
    }

    /// The deepest search made: past it a key is taken to be absent.
    package static let maximumDepth = 8

    /// Whether `context` is one a search made: no render cache, which every
    /// render the app makes has, and a search in the environment. The first
    /// test is all an ordinary measure or drawing pays.
    @inline(__always)
    package static func search(in context: RenderContext) -> ScrollKeyLocate? {
        guard context.renderCache == nil else { return nil }
        return context.environment.scrollKeyLocate
    }
}

/// Equal by identity: one object is one search. A context holding one is
/// never cached (it has no render cache), so this only keeps the environment
/// comparable.
extension ScrollKeyLocate: Equatable {
    nonisolated package static func == (lhs: ScrollKeyLocate, rhs: ScrollKeyLocate) -> Bool { lhs === rhs }
}

private struct ScrollKeyLocateKey: EnvironmentKey {
    static var defaultValue: ScrollKeyLocate? { nil }
}

extension EnvironmentValues {
    /// The `scrollTo` search the measures or the drawing below are made for,
    /// or `nil` — always, but in a search's own context
    /// (``ScrollKeyLocate/search(in:)``).
    package var scrollKeyLocate: ScrollKeyLocate? {
        get { self[ScrollKeyLocateKey.self] }
        set { self[ScrollKeyLocateKey.self] = newValue }
    }
}

extension HitTestRegion.HandlerID {
    /// The marker a drawing for a search stamps at the top of the sought view
    /// (``ScrollKeyLocate/marksTarget``): a geometry marker's id, so no click
    /// lands on it and a clip keeps it, at the top of the geometry markers'
    /// range, which their mint, counting up from its bottom, never reaches.
    package static let seekTargetTop = Self(UInt64.max)
    /// The marker at the sought view's end, one line past its last.
    package static let seekTargetEnd = Self(UInt64.max - 1)
}

extension FrameBuffer {
    /// The lines the sought view's markers enclose in this buffer
    /// (``HitTestRegion/HandlerID/seekTargetTop``), or `nil` when it holds
    /// none.
    package var seekTargetLines: (y: Int, height: Int)? {
        guard let top = hitTestRegions.first(where: { $0.handlerID == .seekTargetTop }) else { return nil }
        let end = hitTestRegions.first { $0.handlerID == .seekTargetEnd }?.offsetY ?? top.offsetY
        return (top.offsetY, max(0, end - top.offsetY))
    }

    /// Stamps the markers of the sought view on this, its drawing.
    mutating func markSeekTarget() {
        hitTestRegions.append(.geometryMarker(.seekTargetTop))
        var end = HitTestRegion.geometryMarker(.seekTargetEnd)
        end.offsetY = height
        hitTestRegions.append(end)
    }
}
