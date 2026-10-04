//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureTestSupport.swift
//
//  Pointer gestures played into an `InputChainHarness` the way the run loop
//  delivers them: a frame before the first event and after every one.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit
@testable import TUIkitCore

/// What the gestures under test reported, in order.
final class GestureRecord: @unchecked Sendable {
    var entries: [String] = []

    func callAsFunction(_ entry: String) {
        entries.append(entry)
    }
}

/// One millisecond, in the nanoseconds the frame clock counts.
let gestureMillisecond: Int64 = 1_000_000

extension InputChainHarness {
    /// Plays left-button events into the view `build` makes, with a frame
    /// after each.
    func pointer(
        _ steps: [(MousePhase, Int, Int)], modifiers: (shift: Bool, ctrl: Bool, meta: Bool) = (false, false, false),
        _ build: () -> some View
    ) {
        for (phase, x, y) in steps {
            mouse(
                MouseEvent(
                    button: .left, phase: phase, x: x, y: y,
                    shift: modifiers.shift, ctrl: modifiers.ctrl, meta: modifiers.meta))
            frame(build())
        }
    }

    /// A click — press and release — at one cell, with a frame after each.
    func click(_ x: Int, _ y: Int, _ build: () -> some View) {
        pointer([(.pressed, x, y), (.released, x, y)], build)
    }

    /// Makes the dispatcher read its event times from ``now`` — for the tests
    /// that measure a velocity from them.
    func syncEventClock() {
        tui.mouseEventDispatcher.nowNanos = { [weak self] in UInt64(max(0, self?.now ?? 0)) }
    }
}
