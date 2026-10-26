//  🖥️ TUI — A Terminal UI framework for Swift
//  PrehashedVerdicts.swift
//
//  A yes-or-no per structural hash, placed by the hash's own bits.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A verdict per key, for keys that are already hashes — a node's
/// structural hash — so each is placed by its own bits rather than hashed
/// again.
///
/// `Set<Int>` and `[Int: Bool]` run every key through SipHash, which for the
/// prune's climbs (``RetainedSubtreeIndex/retains(_:)``, one ask per ancestor
/// passed) was 3.5% of a `dashboard` frame in `Int._rawHashValue(seed:)`
/// alone. Here a key's slot is its Fibonacci hash — the multiply-and-shift
/// `ValueHashPlans` places types by — with linear probing in a power-of-two
/// table kept at most half full. Inserts and overwrites only: the index lives
/// for one prune.
///
/// Keyed by the hash alone, as the dictionary it replaces was: two nodes
/// whose hashes collide share a verdict, where the caller confirms what it
/// must structurally.
struct PrehashedVerdicts {
    /// The keys, 0 marking an empty slot (a key of 0 is stored as 1 — see
    /// ``stored(_:)``).
    private var keys: [Int]
    private var verdicts: [Bool]
    /// 64 − log2(capacity): what a Fibonacci hash is shifted right by.
    private var shift: UInt64
    private var count = 0

    /// A table with room for `minimumCount` keys before it first grows —
    /// none allocated for 0, so an index that is never asked costs nothing.
    init(minimumCount: Int = 0) {
        guard minimumCount > 0 else {
            keys = []
            verdicts = []
            shift = 64
            return
        }
        var capacity = 8
        while capacity < 2 * minimumCount { capacity <<= 1 }
        keys = Array(repeating: 0, count: capacity)
        verdicts = Array(repeating: false, count: capacity)
        shift = UInt64(64 - capacity.trailingZeroBitCount)
    }

    /// The verdict stored for `hash`, or `nil` for none.
    subscript(hash: Int) -> Bool? {
        guard !keys.isEmpty else { return nil }
        let key = Self.stored(hash)
        let mask = keys.count - 1
        var slot = home(of: key)
        while true {
            let found = keys[slot]
            if found == key { return verdicts[slot] }
            if found == 0 { return nil }
            slot = (slot + 1) & mask
        }
    }

    /// Stores `verdict` for `hash`, over any stored before.
    mutating func set(_ verdict: Bool, for hash: Int) {
        if 2 * (count + 1) > keys.count { grow() }
        place(Self.stored(hash), verdict)
    }

    /// A key as stored: 0 is the empty slot's mark, so a hash of 0 shares
    /// 1's slot — one more collision among the ones keying by hash accepts.
    private static func stored(_ hash: Int) -> Int { hash == 0 ? 1 : hash }

    private func home(of key: Int) -> Int {
        Int(truncatingIfNeeded: (UInt64(bitPattern: Int64(key)) &* 0x9E37_79B9_7F4A_7C15) >> shift)
    }

    private mutating func place(_ key: Int, _ verdict: Bool) {
        let mask = keys.count - 1
        var slot = home(of: key)
        while keys[slot] != 0, keys[slot] != key { slot = (slot + 1) & mask }
        if keys[slot] == 0 { count += 1 }
        keys[slot] = key
        verdicts[slot] = verdict
    }

    private mutating func grow() {
        let old = zip(keys, verdicts).filter { $0.0 != 0 }
        self = Self(minimumCount: max(4, keys.count))
        for (key, verdict) in old { place(key, verdict) }
    }
}
