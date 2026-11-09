//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedRowFade.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// The default transition for the rows of a container that windows them — a
// lazy stack, a `List`, a `Table` — which draws only the rows its window
// shows, so the eager stacks' memory of every child (`ChildFade`,
// `PlacementStore`) does not carry over: a record of every row would see each
// scroll as a change of every placement, and a window can draw rows it has
// never drawn without the change having put any of them in.
//
// So the record is of the rows the window DREW last frame, and whether a row
// was among the container's rows then is asked of the container's data as it
// was, kept from that frame (`isRow`): a row drawn now that was not drawn then
// is an arrival only if it was not a row at all, so a row the window reaches by
// scrolling, or because the rows above it went, is placed directly. A row
// drawn then and not now has left only if it is no longer a row; with a
// transition of its own it plays its removal where it was.
//
// What it does not do is glide: the rows around one coming or going move at
// once (decisions B-FB16-2, B-FB16-5). So a removal is drawn OVER the rows,
// where the eager stacks draw it beneath its siblings while they glide into its
// room: here the row below has taken that room on the frame of the change, and
// beneath it the removal would not show.
//
// A settled frame — nothing animating, nothing fading, nothing leaving —
// appends each drawn row's identity to an array and keeps it with the data's
// membership test: no set is built and no store is asked.

/// The owner a windowed row's presence is keyed by in the ``AnimationStore``.
private enum WindowedRowPresence {}

/// A row a container that windows its rows drew, as its record keeps it.
package struct WindowedRow {
    /// The identity the row rendered at.
    package let identity: ViewIdentity
    /// Its `ForEach` key, where it has one: how a container whose rows are
    /// built on demand finds it among its data without building a row.
    package let key: String?
    /// The type of the view it drew, for a removal of its own; `nil` where
    /// the container plays none.
    package let type: Any.Type?

    package init(identity: ViewIdentity, key: String?, type: Any.Type?) {
        self.identity = identity
        self.key = key
        self.type = type
    }

    /// A stack's child, under the stack at `parent`.
    @MainActor
    package init(_ child: ChildView, under parent: ViewIdentity) {
        self.init(
            identity: child.identityStep.identity(under: parent), key: child.identityChildKey,
            type: child.identityStep.type ?? child.viewType)
    }
}

extension WindowedRow {
    /// Whether a row is among `children`, a stack's children under the stack
    /// at `parent`: by its key where it has one, else by its identity. A
    /// scan, asked only of a row an animated change may have put in or taken
    /// out.
    @MainActor
    package static func isAmong(_ children: [ChildView], under parent: ViewIdentity) -> @MainActor (Self) -> Bool {
        { row in
            if let key = row.key { return children.contains { $0.identityChildKey == key } }
            return children.contains { $0.identityStep.identity(under: parent) == row.identity }
        }
    }

    /// Whether a row is among `children`, a stack's children built on demand,
    /// under the stack at `parent`: by its key where it has one, which builds
    /// no row; else by building each to compare its identity.
    @MainActor
    package static func isAmong(
        _ children: ChildViewCollection, under parent: ViewIdentity
    ) -> @MainActor (Self) -> Bool {
        if let eager = children.eagerChildViews { return isAmong(eager, under: parent) }
        return { row in
            if let key = row.key { return children.firstOrdinal(forKey: key) != nil }
            return (0..<children.count).contains { children[$0].identityStep.identity(under: parent) == row.identity }
        }
    }
}

/// What a container that windows its rows drew of them on its last frame.
package final class WindowedRowRecord {
    /// The rows drawn, in drawing order, and where each was drawn.
    var drawn: [(row: WindowedRow, x: Int, y: Int)] = []
    /// Whether a row was among the container's rows on that frame.
    var isRow: (@MainActor (WindowedRow) -> Bool)?
    /// The rows fading in.
    var arriving: Set<ViewIdentity> = []
    /// The rows that have gone and are playing a removal of their own.
    var leaving: [(identity: ViewIdentity, type: Any.Type, x: Int, y: Int)] = []

    init() {}
}

/// One frame of a windowing container's rows coming and going: made where the
/// container starts drawing its rows, told of each row it draws
/// (``drawn(_:_:x:y:)``), and finished with the container's membership test
/// (``finish(isRow:)``). `nil` on a measure, and wherever nothing is kept.
@MainActor
package struct WindowedRowFade {
    private let context: RenderContext
    private let storage: StateStorage
    /// This container's record, kept for the next frame.
    private let record: WindowedRowRecord
    /// Whether ``record`` holds a frame before this one: not on the
    /// container's first, whose rows appear rather than arrive.
    private let hasPast: Bool
    private let animation: Animation?
    private let nowNanos: Int64
    private var drawn: [(row: WindowedRow, x: Int, y: Int)] = []
    /// The identities of the rows drawn last frame, made the first time an
    /// animated change asks.
    private var wasDrawn: Set<ViewIdentity>?

    package init?(context: RenderContext) {
        guard !context.isMeasuring, let storage = context.stateStorage, storage.animations.scrub == nil else {
            return nil
        }
        self.context = context
        self.storage = storage
        let store = storage.placements
        let walk = storage.animations.currentWalk
        if let found = store.record(at: context.identity), let window = found.window,
            !store.appearedEarlierThisPass(found, walk: walk)
        {
            record = window
            hasPast = true
        } else {
            store.remember([], at: context.identity, walk: walk)
            record = WindowedRowRecord()
            store.record(at: context.identity)?.window = record
            hasPast = false
        }
        let frame = context.environment.animationFrame
        nowNanos = frame.nowNanos
        animation = frame.canAnimate ? context.environment.transaction.effectiveAnimation : nil
        drawn.reserveCapacity(record.drawn.count)
    }

    /// The key the presence of the row at `identity` is kept at.
    private func key(_ identity: ViewIdentity) -> AnimationStore.Key {
        AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(WindowedRowPresence.self), slot: identity.hashValue)
    }

    /// `buffer`, which `row` drew at (`x`, `y`) in the container, faded while
    /// it arrives (``presence(of:x:y:drawsSomething:)``).
    package mutating func drawn(_ buffer: FrameBuffer, _ row: WindowedRow, x: Int, y: Int) -> FrameBuffer {
        guard let presence = presence(of: row, x: x, y: y, drawsSomething: buffer.width > 0 && buffer.height > 0)
        else { return buffer }
        return DefaultTransition.faded(buffer, by: presence)
    }

    /// How present `row`, drawn at (`x`, `y`) in the container, is drawn:
    /// `nil` at rest, less than `1` while it arrives — the change put it in,
    /// under an animation, and nothing else brings it in. For a container that
    /// draws its rows as lines rather than buffers (`Table`), which fades the
    /// row's lines by it itself. `key` is the row's key where `row` was made
    /// without one because reading it costs something (a `List`'s tagged row
    /// builds itself to say), asked only of a row an animated change may have
    /// put in.
    package mutating func presence(
        of row: WindowedRow, x: Int, y: Int, drawsSomething: Bool, key rowKey: @autoclosure () -> String? = nil
    ) -> Double? {
        drawn.append((row, x, y))
        guard hasPast else { return nil }
        let identity = row.identity
        if !record.arriving.isEmpty, record.arriving.contains(identity) {
            return arrival(at: identity)
        }
        guard let animation, drawsSomething, let wasRow = record.isRow else { return nil }
        if wasDrawn == nil { wasDrawn = Set(record.drawn.map(\.row.identity)) }
        guard wasDrawn?.contains(identity) == false,
            !wasRow(row.key == nil ? WindowedRow(identity: identity, key: rowKey(), type: row.type) : row),
            // A transition of its own, declared at its address as it drew.
            !storage.departures.isPresent(at: identity)
        else { return nil }
        let key = key(identity)
        storage.animations.settle(key, at: 0.0, nowNanos: nowNanos)
        _ = storage.animations.value(for: key, target: 1.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
        record.arriving.insert(identity)
        return arrival(at: identity)
    }

    /// How far the arrival of the row at `identity` has got, or `nil` once it
    /// has arrived.
    private func arrival(at identity: ViewIdentity) -> Double? {
        let key = key(identity)
        let animations = storage.animations
        let value = animations.value(
            for: key, target: 1.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
        guard animations.isAnimating(at: key, nowNanos: nowNanos) else {
            record.arriving.remove(identity)
            return nil
        }
        return min(1, max(0, value))
    }

    /// Ends the frame: keeps the rows drawn and `isRow`, the container's test
    /// of whether a row is among its rows on this frame, and answers the
    /// pictures of the rows that have gone and are playing a removal of their
    /// own, each where it was drawn, to be drawn over the rows.
    package mutating func finish(
        isRow: @escaping @MainActor (WindowedRow) -> Bool
    ) -> [(picture: FrameBuffer, x: Int, y: Int)] {
        defer {
            record.drawn = drawn
            record.isRow = isRow
            // A frame that fades or plays a removal is a function of the
            // clock, which a memo keeping its buffer would freeze.
            if !record.arriving.isEmpty || !record.leaving.isEmpty {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
            }
        }
        guard hasPast else { return [] }
        let departures = storage.departures
        if !departures.isEmpty, !Self.sameRows(drawn, record.drawn) {
            let now = Set(drawn.map(\.row.identity))
            record.leaving.removeAll { now.contains($0.identity) }
            for old in record.drawn where !now.contains(old.row.identity) {
                guard let held = old.row.type, !isRow(old.row) else { continue }
                let type = departingPictureType(heldAs: held)
                let identity = old.row.identity
                guard departures.hasEntry(at: identity, leftBy: type),
                    departures.hasDeparture(at: identity, ofType: type, nowNanos: nowNanos, frameAnimation: animation)
                else { continue }
                record.leaving.append((identity, type, old.x, old.y))
            }
        }
        guard !record.leaving.isEmpty else { return [] }
        var pictures: [(picture: FrameBuffer, x: Int, y: Int)] = []
        record.leaving.removeAll { leaver in
            guard
                let picture = departures.departing(
                    at: leaver.identity, ofType: leaver.type, nowNanos: nowNanos, frameAnimation: animation)
            else { return true }
            pictures.append((departures.carrying(picture, leftFrom: leaver.identity), leaver.x, leaver.y))
            return false
        }
        return pictures
    }

    /// Whether two frames drew the same rows in the same order.
    private static func sameRows(
        _ lhs: [(row: WindowedRow, x: Int, y: Int)], _ rhs: [(row: WindowedRow, x: Int, y: Int)]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.row.identity == $1.row.identity }
    }
}

extension FrameBuffer {
    /// This buffer with `pictures` drawn over it, each at its place: the
    /// removals a windowing container plays (``WindowedRowFade``).
    @MainActor
    package func drawingOver(_ pictures: [(picture: FrameBuffer, x: Int, y: Int)]) -> FrameBuffer {
        guard !pictures.isEmpty else { return self }
        return pictures.reduce(self) { $0.composited(with: $1.picture, at: (x: $1.x, y: $1.y)) }
    }
}

extension Optional where Wrapped == WindowedRowFade {
    /// ``WindowedRowFade/drawn(_:_:x:y:)`` where there is a fade — `buffer` as
    /// it is where there is none, the row and its place not worked out.
    @MainActor
    package mutating func drawn(
        _ buffer: FrameBuffer, _ row: @autoclosure () -> WindowedRow, x: @autoclosure () -> Int, y: Int
    ) -> FrameBuffer {
        guard self != nil else { return buffer }
        return self!.drawn(buffer, row(), x: x(), y: y)
    }

    /// `buffer`, the container's rows, with the removals ``WindowedRowFade/finish(isRow:)``
    /// answers drawn over it, each moved up by `dy` — the container's buffer
    /// starting `dy` lines into the coordinates its rows were placed in — or
    /// `buffer` as it is where there is no fade.
    @MainActor
    package mutating func finish(
        drawingOver buffer: FrameBuffer, shiftedUpBy dy: Int = 0,
        isRow: @autoclosure () -> @MainActor (WindowedRow) -> Bool
    ) -> FrameBuffer {
        guard self != nil else { return buffer }
        let leaving = self!.finish(isRow: isRow())
        return buffer.drawingOver(dy == 0 ? leaving : leaving.map { ($0.picture, $0.x, $0.y - dy) })
    }
}
