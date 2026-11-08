//  🖥️ TUI — A Terminal UI framework for Swift
//  SessionRunner+CacheSizes.swift
//
//  `--cache-sizes N`: every cache's entry count, every N steps of a session, as
//  one line `Tools/Profiling/cache_growth.py` reads. Printed as the run goes,
//  before the report, so a run cut short still leaves its samples.
//
//  Created by Wade Tregaskis
//  License: MIT

extension SessionRunner {
    /// Prints `cache-sizes step=N name=count …` for `session`'s app, when
    /// `steps` is a multiple of `every` (and `every` is not 0: never).
    @MainActor
    static func printCacheSizes(of session: DrivenSession, after steps: Int, every: Int) {
        guard every > 0, steps.isMultiple(of: every) else { return }
        let counts = session.cacheEntryCounts().map { "\($0.name)=\($0.count)" }
        Swift.print("cache-sizes step=\(steps) " + counts.joined(separator: " "))
    }
}
