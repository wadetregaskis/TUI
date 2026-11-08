//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+EntryCounts.swift
//
//  How many entries each of the render cache's tables holds, for a census of
//  their growth over a long run: `Stress --session … --cache-sizes N`, read by
//  `Tools/Profiling/cache_growth.py`. A cache that is bounded levels off; one
//  that keeps a little of every frame climbs, and is named by its table.
//
//  Created by Wade Tregaskis
//  License: MIT

extension RenderCache {
    /// Each table's name and how many entries it holds now.
    package var entryCounts: [(name: String, count: Int)] {
        // A typed local and `+=`, not `[…] + privateEntryCounts`: a literal of
        // tuples added to an array took the type checker past its budget.
        var counts: [(name: String, count: Int)] = [
            ("render.entries", entries.count), ("render.sizes", sizeEntries.count),
            ("render.appliedEnvironment", appliedEnvironment.count), ("render.hostedMembers", hostedMembers.count),
            ("render.hostsByAncestor", hostsByAncestor.count), ("render.erasedContent", erasedContent.count),
            ("render.readingTypes", readingTypes.count), ("render.bodyKeep", bodyKeep.count),
        ]
        counts += privateEntryCounts
        return counts
    }
}
