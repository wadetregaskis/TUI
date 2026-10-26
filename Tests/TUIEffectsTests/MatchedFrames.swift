//  🖥️ TUI — A Terminal UI framework for Swift
//  MatchedFrames.swift
//
//  The frames the matched geometry tests draw: the run loop's, on a clock
//  a test moves.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// Frames rendered the way the run loop renders them — the scene root's
/// geometry answered, and the frame drawn again when a reader or a matched
/// view drew from a wrong answer (`InputChainHarness`) — on a clock a test
/// moves, each frame under the animation it is given, read as the screen
/// shows it: layers composited, styling stripped.
@MainActor
final class MatchedFrames {
    let harness: InputChainHarness

    init(width: Int = 40, height: Int = 12, reducesMotion: Bool = false) {
        harness = InputChainHarness(width: width, height: height) { environment in
            environment.canAnimate = true
            environment.accessibilityReduceMotion = reducesMotion
        }
    }

    /// The root's corrections so far.
    var corrections: GeometryCorrections { harness.geometryCorrections }

    /// One frame of `view` at `millis` on the frame clock, under `animation`,
    /// as drawn: its layers not yet composited.
    func buffer<V: View>(_ view: @autoclosure () -> V, atMillis millis: Int = 0, animation: Animation? = nil)
        -> FrameBuffer
    {
        harness.now = Int64(millis) * 1_000_000
        harness.transaction = Transaction(animation: animation)
        return harness.frame(view())
    }

    /// One frame of `view` at `millis` on the frame clock, under `animation`.
    @discardableResult
    func draw<V: View>(_ view: @autoclosure () -> V, atMillis millis: Int = 0, animation: Animation? = nil)
        -> [String]
    {
        let buffer = buffer(view(), atMillis: millis, animation: animation)
        return buffer.compositingOverlays(
            maxWidth: harness.context.availableWidth, maxHeight: harness.context.availableHeight,
            palette: harness.context.environment.palette
        ).lines.map(\.stripped)
    }
}
