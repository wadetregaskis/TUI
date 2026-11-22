//  🖥️ TUI — A Terminal UI framework for Swift
//  StateStorage+ErasedContent.swift
//
//  An `AnyView` whose erased type changes holds a new view, whose state starts
//  afresh, as SwiftUI's does; the same type wrapped again keeps its state.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - What an AnyView's content made

/// What an `AnyView` keeps at its identity and depth: the type of the content
/// it draws, and the keys of the state that content made, so a change of type
/// drops exactly that (``StateStorage/noteErasedContentDrawn(_:at:depth:handsOverMembers:)``).
///
/// Kept among the values, at ``StateStorage/StateKey/erasedContentIndex`` in
/// the scope of the depth, as an enum's case record is, so it is pruned and
/// invalidated with its identity. Made when the content first makes state, or
/// when the `AnyView` hands its container its views, never for content that
/// keeps none: most `AnyView`s, a menu's labels among them, pay a probe.
///
/// ## Why the keys, not a pattern
///
/// The first version (2026-11-21, dropped unlanded) dropped everything below
/// the identity and the declaration-order values (scope `0`, indices `0...`)
/// at it. But a procedural core may draw caller content at its own identity,
/// where its own slots are, and the search field draws every suggestion's
/// label there, at the depth its own handler is: the labels' types took turns
/// in the record, each turn read as a swap, and the drop took the field's
/// handler with it, so its suggestions menu never stayed open. State the
/// content made is the content's, whatever its key; nothing else is dropped.
final class ErasedContentRecord {
    /// The type the content had when it was last compared.
    var type: ObjectIdentifier

    /// The walk the type was last compared in (``StateStorage/currentWalk``).
    var walk: UInt32

    /// Whether two types were drawn here within one walk: not one `AnyView`
    /// changing its content, but a core drawing several erased views in turn
    /// at its own identity — a menu's labels. Such a place is never taken for
    /// a swap again while the record lives: which label's type comes first is
    /// the menu's order, not a change of content.
    var isShared = false

    /// Whether the `AnyView` handed its container its views (it erases
    /// several), which the container draws at identities below this one,
    /// out of the `AnyView`'s sight: everything below is theirs, and a swap
    /// drops it all.
    var handsOverMembers = false

    /// The keys of the values the content made, in the order it did.
    var keys: [StateStorage.StateKey] = []

    /// The keys of the tracked values the content made (`onChange(of:)`).
    var trackedKeys: [StateStorage.StateKey] = []

    /// How many keys the last compaction kept (``compact(in:)``).
    private var keptAfterCompaction = 0

    init(type: ObjectIdentifier, walk: UInt32) {
        self.type = type
        self.walk = walk
    }

    /// Forgets the keys whose values have gone — pruned with an identity the
    /// content no longer draws — once enough have gathered: content whose
    /// rows come and go makes new keys for as long as it is drawn.
    func compact(in storage: StateStorage) {
        guard keys.count + trackedKeys.count > 2 * keptAfterCompaction + 32 else { return }
        keys.removeAll { storage.values[$0] == nil }
        trackedKeys.removeAll { storage.trackedValues[$0] == nil }
        keptAfterCompaction = keys.count + trackedKeys.count
    }
}

/// An `AnyView` whose content is being drawn or measured
/// (``StateStorage/erasedContentDraws``).
struct ErasedContentDraw {
    let identity: ViewIdentity
    let depth: Int
    let type: ObjectIdentifier
}

extension StateStorage {
    /// The key of the record an `AnyView` at `identity` and `depth` keeps.
    private func erasedContentKey(_ identity: ViewIdentity, depth: Int) -> StateKey {
        StateKey(
            identity: identity, propertyIndex: StateKey.erasedContentIndex, scope: UInt64(bitPattern: Int64(depth)))
    }

    /// Notes that the content of an `AnyView` at `identity` and `depth`, of
    /// `type`, is being drawn or measured: the state made until
    /// ``endErasedContent()`` is that content's. Measures too, since a
    /// composite's `@State` is made by whichever walk reaches it first.
    package func beginErasedContent(_ type: ObjectIdentifier, at identity: ViewIdentity, depth: Int) {
        erasedContentDraws.append(ErasedContentDraw(identity: identity, depth: depth, type: type))
    }

    /// Ends what ``beginErasedContent(_:at:depth:)`` began. Never traps: a
    /// ``reset()`` in the middle of a draw has emptied the list already.
    package func endErasedContent() {
        if !erasedContentDraws.isEmpty { erasedContentDraws.removeLast() }
    }

    /// Notes `key`, just made, as the state of the innermost `AnyView`'s
    /// content being drawn that holds it — at its identity or below: what
    /// a draw makes elsewhere (a presentation's, the chrome's) is not its.
    ///
    /// The record is made here when it is the content's first state, and
    /// noted as the state of the `AnyView` around it, if any, so a swap
    /// further out drops it and what it lists.
    func noteMadeInErasedContent(_ key: StateKey, tracked: Bool = false) {
        var level = erasedContentDraws.count - 1
        while level >= 0 {
            let draw = erasedContentDraws[level]
            if draw.identity == key.identity || draw.identity.isAncestor(of: key.identity) { break }
            level -= 1
        }
        guard level >= 0 else { return }
        let record = erasedContentRecord(at: level)
        if tracked {
            record.trackedKeys.append(key)
        } else {
            record.keys.append(key)
        }
        record.compact(in: self)
    }

    /// The record of the `AnyView` drawn at `level` of ``erasedContentDraws``,
    /// made if it has none yet — compared as of this walk, which is drawing it.
    private func erasedContentRecord(at level: Int) -> ErasedContentRecord {
        let draw = erasedContentDraws[level]
        let key = erasedContentKey(draw.identity, depth: draw.depth)
        if let record = values[key] as? ErasedContentRecord { return record }
        let record = ErasedContentRecord(type: draw.type, walk: currentWalk)
        pruneWitness.changes += 1
        values[key] = record
        if level > 0 {
            // Inside another `AnyView`'s content: the record is that content's.
            let outer = erasedContentDraws[0..<level].lastIndex {
                $0.identity == draw.identity || $0.identity.isAncestor(of: draw.identity)
            }
            if let outer { erasedContentRecord(at: outer).keys.append(key) }
        }
        return record
    }

    /// Notes that an `AnyView` at `identity` and `depth` draws content of
    /// `type`, and where that differs from the type it drew last, drops the
    /// state its content made: content of another type is a new view, as
    /// SwiftUI makes it (measured on macOS 15.8,
    /// `Tools/SwiftUIProbes/AnyView type swap (H-08)/anyview.out`: another
    /// type, the first one back, or the first inside a modifier all start
    /// afresh; the same type in a new `AnyView` keeps its state).
    ///
    /// An `AnyView` draws its content at its own identity, and a view keeps
    /// its `@State` there by declaration order, with no type in the key, so a
    /// screen erased one frame and another the next found the first one's
    /// boxes: text typed in one step of a wizard showed in the next (VIEWS-2).
    ///
    /// **What goes** is what the content made (``ErasedContentRecord``): not
    /// a core's slots at the same identity, an `onChange(of:)` around the
    /// `AnyView`, or a wrapper's negative indices, which were made outside
    /// it. When it hands its container its views (`handsOverMembers`), what
    /// those make is made out of its sight, below its identity, and
    /// everything there goes.
    ///
    /// **When.** Only a render or a render's walk of its views asks: a
    /// measure must not drop state (one measures many candidates at one
    /// place). And only the walk's first draw here compares: a core that
    /// draws several erased views in turn at one identity — the search
    /// field's suggestion labels — draws the same first each walk, and the
    /// rest, being other types, mark the place shared
    /// (``ErasedContentRecord/isShared``), which no longer swaps. Per walk,
    /// not per pass: a walk made again for what an effect wrote may draw
    /// other content, as `onAppear { loggedIn = true }` does.
    ///
    /// - Returns: Whether the type changed and state was dropped, so the
    ///   caller clears what the render cache kept from it.
    package func noteErasedContentDrawn(
        _ type: ObjectIdentifier, at identity: ViewIdentity, depth: Int, handsOverMembers: Bool
    ) -> Bool {
        let key = erasedContentKey(identity, depth: depth)
        guard let record = values[key] as? ErasedContentRecord else {
            // Content whose views its container draws makes its state out of
            // sight: the record is made now, to compare from the next walk.
            if handsOverMembers {
                beginErasedContent(type, at: identity, depth: depth)
                erasedContentRecord(at: erasedContentDraws.count - 1).handsOverMembers = true
                endErasedContent()
                markActive(identity)
            }
            return false
        }
        // Kept alive with its identity, whatever the content keeps there.
        markActive(identity)
        if handsOverMembers { record.handsOverMembers = true }
        guard record.walk != currentWalk else {
            if record.type != type { record.isShared = true }
            return false
        }
        record.walk = currentWalk
        guard record.type != type, !record.isShared else { return false }
        record.type = type
        return dropErasedContent(of: record, at: identity)
    }

    /// Drops what `record`'s content made, and — where its container drew its
    /// views — everything below `identity`, with the animations there.
    private func dropErasedContent(of record: ErasedContentRecord, at identity: ViewIdentity) -> Bool {
        let keys = record.keys
        let trackedKeys = record.trackedKeys
        record.keys = []
        record.trackedKeys = []
        var dropped = !keys.isEmpty || !trackedKeys.isEmpty
        removeValues(forKeys: keys)
        removeTrackedValues(forKeys: trackedKeys)
        // The animations of the identities below this one the content kept
        // state at; not this one's, which may be the core's around it.
        var animated = Set<ViewIdentity>()
        for key in keys where key.identity != identity && animated.insert(key.identity).inserted {
            animations.removeDescendants(of: key.identity, includingItself: true)
        }
        if record.handsOverMembers {
            let below = values.keys.filter { identity.isAncestor(of: $0.identity) }
            removeValues(forKeys: below)
            removeTrackedValues(forKeys: trackedValues.keys.filter { identity.isAncestor(of: $0.identity) })
            animations.removeDescendants(of: identity, includingItself: false)
            dropped = true
        }
        return dropped
    }
}
