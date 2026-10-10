//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorDepthTestSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import Foundation

import TUIkit
@testable import TUIkitFoundation

/// Runs `body` with `ColorDepth.current` pinned to `depth` for the current
/// task only.
///
/// Wrap the whole colour-dependent portion of a test — the render/convert
/// call *and* its expectations — so the pinned depth is observed throughout.
///
/// The pin is task-local (`ColorDepth.withCurrent`), so parallel tests are
/// unaffected: no lock, no restore, no bleed. (An earlier version mutated the
/// process-global under a lock shared by `withColorDepth` callers — but every
/// OTHER colour-asserting test still raced it, and a `.noColor` window here
/// occasionally made an unrelated control render colourless mid-suite.)
///
/// - Parameters:
///   - depth: The colour depth to pin `ColorDepth.current` to for the
///     duration of `body`.
///   - body: The colour-dependent work to run under the pin.
/// - Returns: Whatever `body` returns.
@discardableResult
func withColorDepth<T>(_ depth: ColorDepth, _ body: () throws -> T) rethrows -> T {
    try ColorDepth.withCurrent(depth, operation: body)
}

#endif
