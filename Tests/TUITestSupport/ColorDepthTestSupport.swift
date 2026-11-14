//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorDepthTestSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

import Foundation
import Testing

import TUIStyling

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

/// Draws every test of a suite at 24-bit colour, whatever the process's
/// environment asks for: `.drawsInTruecolor` on the suite.
///
/// The depth the process detects follows the environment, `NO_COLOR` among
/// it, which `swift test` itself sets whenever its output is not a terminal
/// (piped, or from a script); the project's runner, `parallel_test.py`, does
/// not. A suite whose assertions depend on what colour lets the screen show —
/// a picture found by its colour, or a scrollbar thumb, drawn as a glyph
/// without colour where it is a fill with it — passed under the runner and
/// failed under `swift test`, the same way every time. The pin is task-local
/// (`ColorDepth.withCurrent`), so no other test sees it.
struct DrawsInTruecolor: SuiteTrait, TestTrait, TestScoping {
    /// Every test, not only the suite: see `RendersEnglishUI`.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? { self }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        try await ColorDepth.withCurrent(.truecolor) { try await function() }
    }
}

extension Trait where Self == DrawsInTruecolor {
    /// This suite's assertions depend on colour; draw at 24-bit whatever the
    /// environment says.
    static var drawsInTruecolor: Self { Self() }
}

#endif
