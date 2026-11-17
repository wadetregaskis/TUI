//  🖥️ TUI — A Terminal UI framework for Swift
//  StackProportion.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUICore

extension StackGuard {
    /// `levels` of an 8 MiB stack — the main thread's on macOS and Linux, which
    /// a test's depth was chosen against — and as many in proportion of the
    /// calling thread's stack where that is smaller or larger: an eighth as many
    /// on a Windows thread's 1 MiB. `levels` where the stack cannot be measured.
    ///
    /// For a test whose depth is about the stack: a chain built deeper than a
    /// walk can descend, but shallow enough that releasing it — one level inside
    /// the next, which no guard can cut short — fits; or the levels a walk is
    /// expected to read before the guard stops it.
    @MainActor
    package static func levelsInProportion(_ levels: Int) -> Int {
        guard let stack = currentThreadExtent(stackPointer: currentStackPointer()) else { return levels }
        let kibibytes = Int((stack.high - stack.low) >> 10)
        return max(1, levels * kibibytes / (8 << 10))
    }
}

#endif
