//  🖥️ TUI — A Terminal UI framework for Swift
//  GenerationalMemo.swift
//
//  The bounded memo TUIStrings keeps its answers in: two generations of
//  a fixed size, so a memo of keys made from data does not grow for ever.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Answers kept for keys, at most two generations of ``limit`` each.
///
/// NOT one map emptied when it fills. That was the flat cap a memo of
/// TUI's has already lost to once (the text-wrap memo): a working set
/// just over the limit — 4,097 keys a frame — filled the map, emptied it
/// at the 4,097th key and refilled it, so every frame computed every answer
/// again and nothing was ever served. Here only a fresh answer is written,
/// into the current generation; a full one becomes the previous one and the
/// one before it is forgotten. A set of keys asked for again and again is
/// therefore kept whole up to twice the limit — the whole bound — and
/// computed again only past it.
///
/// An answer found in the previous generation is NOT copied back into
/// the current one. That copy is what keeps an answer asked for once a
/// generation alive for ever, but every copy fills the current generation
/// towards its turnover, and the turnover forgets the previous answers
/// not yet copied: a set of 4,098 keys asked for in turn then computed one
/// key again each round, 6,144 keys 2,047 to 4,094, and 8,191 keys 8,187 —
/// the flat cap's failure again, moved from just over the limit to just
/// under twice it. Without the copy, the price is a key asked for often
/// while a stream of others is computed: it is forgotten with its
/// generation, so it is computed again once a turnover at most — at most
/// once for every ``limit`` other keys computed.
///
/// Not thread-safe: each owner keeps it under its own lock.
struct GenerationalMemo<Key: Hashable, Value> {
    /// How many answers one generation holds.
    let limit: Int

    private var current: [Key: Value] = [:]
    private var previous: [Key: Value] = [:]

    init(limit: Int) {
        self.limit = limit
    }

    /// The answer kept for `key`, or `nil` where none is.
    func answer(for key: Key) -> Value? {
        current[key] ?? previous[key]
    }

    /// Keeps `answer` for `key`, starting a new generation first if the
    /// current one is full.
    mutating func remember(_ answer: Value, for key: Key) {
        if current.count >= limit {
            // The old previous generation's storage becomes the new current
            // one, emptied, so a turnover allocates nothing.
            swap(&current, &previous)
            current.removeAll(keepingCapacity: true)
        }
        current[key] = answer
    }

    /// How many answers are kept, in both generations.
    var count: Int { current.count + previous.count }
}
