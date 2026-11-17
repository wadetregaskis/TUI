//  🖥️ TUI — A Terminal UI framework for Swift
//  Synth.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Deterministic RNG

/// A stable per-index hash, so a row's content can be synthesised on demand
/// from `(seed, index)` without materialising (or storing) an array. This is
/// what lets a "1,000,000-row" list cost O(visible) memory: the data set is
/// just a count + a seed, and each visible row hashes its index into content.
@inline(__always)
func mix(_ seed: UInt64, _ index: Int) -> UInt64 {
    var z = seed &+ (UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15)
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

// MARK: - Synthetic vocabulary

/// Pseudo-text built from small fixed word lists — a few hundred bytes of
/// vocabulary recombined into names, titles, and sentences. No data files; the
/// "size on disk" of any data set is zero.
enum Synth {
    static let adjectives = [
        "swift", "lazy", "bright", "hollow", "crimson", "azure", "silent", "rapid",
        "ancient", "molten", "frozen", "hidden", "gilded", "fractal", "quantum", "stellar",
        "verbose", "terse", "nested", "flat", "sparse", "dense", "volatile", "stable",
    ]
    static let nouns = [
        "harbor", "cipher", "lattice", "ember", "vector", "glyph", "fjord", "comet",
        "raven", "willow", "summit", "delta", "phantom", "anchor", "beacon", "marble",
        "buffer", "kernel", "render", "widget", "column", "raster", "socket", "thread",
    ]
    static let surnames = [
        "Ashwood", "Vance", "Okafor", "Lindqvist", "Tanaka", "Moreau", "Ibarra", "Chen",
        "Delacroix", "Nakamura", "Petrov", "Halloran", "Esposito", "Kowalski", "Rivera", "Nguyen",
    ]
    static let firstNames = [
        "Ada", "Bram", "Cleo", "Dara", "Esme", "Finn", "Gaia", "Hugo",
        "Iris", "Juno", "Kit", "Liv", "Mira", "Noor", "Orin", "Pax",
    ]
    static let statuses = ["active", "idle", "queued", "failed", "paused", "syncing", "sealed"]

    /// The entry of `table` that `h` picks. A function of its own, its types
    /// stated: indexing inline, inside an interpolation, exceeded the
    /// type-check guard's 2,000 solver scopes.
    static func pick(_ table: [String], _ h: UInt64) -> String {
        let index: UInt64 = h % UInt64(table.count)
        return table[Int(index)]
    }

    /// A two-word lowercase identifier-ish token, e.g. `"molten-buffer"`.
    static func slug(_ h: UInt64) -> String {
        pick(adjectives, h) + "-" + pick(nouns, h >> 8)
    }

    /// A `"First Surname"` display name.
    static func name(_ h: UInt64) -> String {
        pick(firstNames, h) + " " + pick(surnames, h >> 16)
    }

    static func status(_ h: UInt64) -> String {
        pick(statuses, h >> 24)
    }

    /// A sentence of `wordCount` recombined words, deterministic in `h`.
    static func sentence(_ h: UInt64, words wordCount: Int) -> String {
        var out: [String] = []
        out.reserveCapacity(wordCount)
        var x = h
        for _ in 0..<wordCount {
            x = (x ^ (x >> 29)) &* 0xBF58_476D_1CE4_E5B9
            let pickAdjective = (x & 1) == 0
            let table = pickAdjective ? adjectives : nouns
            out.append(pick(table, x >> 7))
        }
        return out.joined(separator: " ")
    }

    /// A unicode block-element bar of `width` cells filled to `fraction`.
    static func bar(_ fraction: Double, width: Int) -> String {
        let clamped = max(0, min(1, fraction))
        let filled = Int((Double(width) * clamped).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
    }
}
