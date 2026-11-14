//  🖥️ TUI — A Terminal UI framework for Swift
//  Headless+CacheSizes.swift
//
//  What `--bench` prints after a frame when asked: the frame's checksum
//  (`--frame-checksums`), and every N frames the bench's own context's tables
//  (`--cache-sizes N`), in the line a session prints
//  (`SessionRunner+CacheSizes.swift`), so a page whose memory grows as it
//  runs says which table holds it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

extension Headless {
    /// Prints, after frame `iteration` (from 0), `frame N checksum=…` when
    /// `checksum` is given, and `cache-sizes step=N name=count …` for the render
    /// cache, the state storage and the lifecycle manager `context` renders
    /// against when the frames drawn are a multiple of `cacheSizesEvery` (and
    /// it is not 0: never).
    @MainActor
    static func printAfterFrame(_ iteration: Int, checksum: Int?, _ context: RenderContext, _ cacheSizesEvery: Int) {
        if let checksum { print("frame \(iteration) checksum=\(checksum)") }
        let frames = iteration + 1
        guard cacheSizesEvery > 0, frames.isMultiple(of: cacheSizesEvery) else { return }
        var counts = context.environment.renderCache?.entryCounts ?? []
        counts += context.environment.stateStorage?.entryCounts ?? []
        counts += context.environment.lifecycle?.entryCounts ?? []
        print("cache-sizes step=\(frames) " + counts.map { "\($0.name)=\($0.count)" }.joined(separator: " "))
    }
}
