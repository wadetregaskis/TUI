//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentStamp+Derived.swift
//
//  A stamp made from what an environment changes against the pass's first one,
//  rather than from all of it.
//
//  Almost every environment in a pass is that first one with a key or two set: a
//  stack's axis, a modifier's value. A flat stamp reads every key, classifies it,
//  hashes it, sorts the lot and looks for an equal one, and each new storage pays
//  for all of that again: more than half of `session/notes` with composites
//  memoized. So one stamp in a pass is built flat, the anchor, and every other is
//  (anchor, what differs), which reads each key once to find what differs, and
//  allocates only for what does.
//
//  Canonical: the differences are sorted and made against the anchor, not against
//  whichever environment came before, so an environment reached any way round is
//  the same stamp, and the anchor itself is interned, so a frame's is the last
//  frame's. A stamp is at most one step from a flat one, so no chain builds up.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

extension EnvironmentStamp {
    /// One key that differs from the anchor: `token` is what it holds, or `nil`
    /// when the anchor sets it and this environment does not.
    package struct Change {
        let key: ObjectIdentifier
        let token: Token?
    }

    /// Whether `changes`, in key order, are this stamp's, on `anchor`.
    func holds(_ changes: [Change], on anchor: EnvironmentStamp) -> Bool {
        guard base === anchor, self.changes.count == changes.count else { return false }
        for (mine, theirs) in zip(self.changes, changes) {
            guard mine.key == theirs.key else { return false }
            switch (mine.token, theirs.token) {
            case (nil, nil): continue
            case (let left?, let right?):
                guard Self.equal(left, right) else { return false }
            default: return false
            }
        }
        return true
    }

    /// The flat entries of a stamp on `base`: the base's, with `changes` applied.
    /// Both lists are in key order. Asked only when two stamps on different
    /// anchors are compared, or a diagnostic looks.
    static func merged(_ base: EnvironmentStamp, _ changes: [Change]) -> [Entry] {
        var merged: [Entry] = []
        merged.reserveCapacity(base.entries.count + changes.count)
        var pending = changes[...]
        func applyChanges(upTo key: ObjectIdentifier?) -> Bool {
            var replaced = false
            while let change = pending.first, key.map({ change.key <= $0 }) ?? true {
                pending.removeFirst()
                if change.key == key { replaced = true }
                if let token = change.token { merged.append(Entry(key: change.key, token: token)) }
            }
            return replaced
        }
        for entry in base.entries where !applyChanges(upTo: entry.key) {
            merged.append(entry)
        }
        _ = applyChanges(upTo: nil)
        return merged
    }
}

/// What the anchor holds under one key, read without classifying it again.
struct AnchorSlot {
    enum Compare {
        /// A key no render reads: nothing to compare.
        case neutral
        /// Bytes every value of the type defines, lying in the existential's own
        /// buffer: equal bytes, equal value. Unequal bytes settle it too when
        /// `settles`, as for an object's identity or a plain number; otherwise
        /// the value's `==` may yet say equal.
        case bytes(count: Int, settles: Bool)
        /// A value in a box of its own, whose address is the first word: the same
        /// box is the same value.
        case box
        /// Nothing shortcuts it: compared by token.
        case token
    }

    let raw: Any
    let type: ObjectIdentifier
    let compare: Compare
    /// The anchor's token, for a key it does not skip.
    let token: EnvironmentStamp.Token?
    let isProjected: Bool
}

extension EnvironmentStamps {
    /// How a derivation went.
    enum Derivation {
        case stamp(EnvironmentStamp)
        case uncomparable
        /// No anchor yet, or too far from it to be worth keeping in pieces.
        case flat
    }

    /// More differences than this, and a stamp is built flat: an environment that
    /// far from the anchor would be slower to compare in pieces, and it is what a
    /// page under its own theme looks like, which is rare.
    static let derivationLimit = 16

    /// Makes `stamp` (a flat one, of `environment`) the pass's anchor.
    func setAnchor(_ environment: EnvironmentValues, _ stamp: EnvironmentStamp) {
        anchor = stamp
        anchorSlots.removeAll(keepingCapacity: true)
        anchorComparedKeys = 0
        var tokens: [ObjectIdentifier: EnvironmentStamp.Token] = [:]
        tokens.reserveCapacity(stamp.entries.count)
        for entry in stamp.entries { tokens[entry.key] = entry.token }
        for (key, raw) in environment.storedValues {
            let rule = keyRule(key)
            let type = ObjectIdentifier(Swift.type(of: raw))
            switch rule {
            case .neutral:
                anchorSlots[key] = AnchorSlot(raw: raw, type: type, compare: .neutral, token: nil, isProjected: false)
            case .projecting:
                anchorComparedKeys += 1
                anchorSlots[key] = AnchorSlot(raw: raw, type: type, compare: .token, token: tokens[key], isProjected: true)
            case .plain:
                anchorComparedKeys += 1
                anchorSlots[key] = AnchorSlot(
                    raw: raw, type: type, compare: shortcut(for: raw), token: tokens[key], isProjected: false)
            }
        }
    }

    /// How a value of `raw`'s type can be compared without its `==`.
    private func shortcut(for raw: Any) -> AnchorSlot.Compare {
        let id = ObjectIdentifier(Swift.type(of: raw))
        if let known = shortcuts[id] { return known }
        func decide<T>(_: T) -> AnchorSlot.Compare {
            let word = MemoryLayout<UInt>.size
            // An existential's buffer holds a value of up to three words, aligned
            // to at most one, that memcpy can move; anything else goes in a box.
            let isInline =
                MemoryLayout<T>.size <= 3 * word && MemoryLayout<T>.alignment <= word && _isBitwiseTakable(T.self)
            guard isInline else { return .box }
            guard case .success(let items) = ValueHashPlanBuilder().items(for: T.self),
                ValueHashPlanBuilder.coversWhole(items, size: MemoryLayout<T>.size)
            else { return .token }
            return .bytes(count: MemoryLayout<T>.size, settles: _isPOD(T.self) || T.self is AnyClass)
        }
        let made = _openExistential(raw, do: decide)
        shortcuts[id] = made
        return made
    }

    /// Whether `raw` is what the anchor holds at `slot`, as far as the type's
    /// bytes can say; `nil` when only its token can.
    private func sameByBytes(_ raw: Any, _ slot: AnchorSlot) -> Bool? {
        guard ObjectIdentifier(Swift.type(of: raw)) == slot.type else { return false }
        switch slot.compare {
        case .neutral:
            return true
        case .bytes(let count, let settles):
            let same = withUnsafeBytes(of: raw) { left in
                withUnsafeBytes(of: slot.raw) { right in
                    memcmp(left.baseAddress.unsafelyUnwrapped, right.baseAddress.unsafelyUnwrapped, count) == 0
                }
            }
            return same ? true : settles ? false : nil
        case .box:
            let same = withUnsafeBytes(of: raw) { left in
                withUnsafeBytes(of: slot.raw) { right in left.load(as: UInt.self) == right.load(as: UInt.self) }
            }
            return same ? true : nil
        case .token:
            return nil
        }
    }

    // swiftlint:disable cyclomatic_complexity
    /// `environment`'s stamp, from what it changes against the anchor.
    func derive(_ environment: EnvironmentValues) -> Derivation {
        guard let anchor, !tracksVariety else { return .flat }
        var changes = changeScratch
        changeScratch = []
        changes.removeAll(keepingCapacity: true)
        defer { changeScratch = changes }
        var seenCompared = 0
        var hash = 0
        for (key, raw) in environment.storedValues {
            if let slot = anchorSlots[key] {
                if case .neutral = slot.compare { continue }
                seenCompared += 1
                if sameByBytes(raw, slot) == true { continue }
                // Its `==`, before a token and a hash are made to find the same.
                if !slot.isProjected, case .value(let held, let equal)? = slot.token, equal(raw, held) { continue }
                guard let token = token(ofKey: key, raw: raw, hash: &hash, comparingWith: slot.token) else {
                    if tokenWasUncomparable { return .uncomparable }
                    continue
                }
                changes.append(EnvironmentStamp.Change(key: key, token: token))
            } else {
                if case .neutral = keyRule(key) { continue }
                guard let token = token(ofKey: key, raw: raw, hash: &hash, comparingWith: nil) else {
                    if tokenWasUncomparable { return .uncomparable }
                    continue
                }
                changes.append(EnvironmentStamp.Change(key: key, token: token))
            }
            if changes.count > Self.derivationLimit { return .flat }
        }
        // A key set on the anchor and not here reads its default here.
        if seenCompared != anchorComparedKeys {
            for (key, slot) in anchorSlots {
                if case .neutral = slot.compare { continue }
                if environment.storedValues[key] == nil {
                    changes.append(EnvironmentStamp.Change(key: key, token: nil))
                    hash ^= key.hashValue
                }
            }
            if changes.count > Self.derivationLimit { return .flat }
        }
        if changes.isEmpty { return .stamp(anchor) }
        if changes.count > 1 { changes.sort { $0.key < $1.key } }
        counts.derived += 1
        let slotHash = hash ^ ObjectIdentifier(anchor).hashValue
        var bucket = derivedBuckets[slotHash] ?? []
        for (index, candidate) in bucket.enumerated() {
            guard let existing = candidate.stamp, existing.holds(changes, on: anchor) else { continue }
            counts.internHits += 1
            if index != 0 {
                bucket.swapAt(0, index)
                derivedBuckets[slotHash] = bucket
            }
            return .stamp(existing)
        }
        let made = EnvironmentStamp(base: anchor, changes: changes)
        bucket.insert(WeakStamp(made), at: 0)
        if bucket.count > Self.bucketCapacity {
            if let dead = bucket.lastIndex(where: { $0.stamp == nil }) {
                bucket.remove(at: dead)
            } else {
                bucket.removeLast()
                counts.overflows += 1
            }
        }
        derivedBuckets[slotHash] = bucket
        return .stamp(made)
    }
    // swiftlint:enable cyclomatic_complexity

    /// The token of `raw` under `key`, folded into `hash` (commutatively, so the
    /// order a dictionary lists its keys in does not matter), or `nil`: either it
    /// equals `other`, or it cannot be compared (``tokenWasUncomparable``).
    private func token(
        ofKey key: ObjectIdentifier, raw: Any, hash: inout Int, comparingWith other: EnvironmentStamp.Token?
    ) -> EnvironmentStamp.Token? {
        tokenWasUncomparable = false
        let value: Any
        switch keyRule(key) {
        case .neutral:
            return nil
        case .projecting(let project):
            guard let projection = project(raw) else {
                uncomparableKeys[key, default: 0] += 1
                tokenWasUncomparable = true
                return nil
            }
            value = projection
        case .plain:
            value = raw
        }
        var hasher = Hasher()
        hasher.combine(key)
        guard let made = token(for: value, hasher: &hasher) else {
            uncomparableKeys[key, default: 0] += 1
            tokenWasUncomparable = true
            return nil
        }
        if let other, EnvironmentStamp.equal(made, other) { return nil }
        hash ^= hasher.finalize()
        return made
    }
}
