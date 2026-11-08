//  🖥️ TUI — A Terminal UI framework for Swift
//  StateStorage+EntryCounts.swift
//
//  How many entries each of the state storage's tables holds, for a census of
//  their growth over a long run (`Stress --session … --cache-sizes N`; see
//  `RenderCache+EntryCounts.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

extension StateStorage {
    /// Each table's name and how many entries it holds now.
    package var entryCounts: [(name: String, count: Int)] {
        // A typed local and `+=`, not `[…] + privateEntryCounts`: a literal of
        // tuples added to an array took the type checker past its budget.
        var counts: [(name: String, count: Int)] = [
            ("state.values", values.count), ("state.optionalPresence", optionalPresence.count),
            ("state.objectHubs", objectHubs.count), ("state.environmentRestores", environmentRestores.count),
        ]
        counts += privateEntryCounts
        return counts
    }
}
