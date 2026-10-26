//  🖥️ TUI — A Terminal UI framework for Swift
//  OnTapGestureModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Tests for the located `.onTapGesture { cell in … }` modifier.
///
/// A tap is a left-button press followed by a release on the view. The
/// modifier attaches a `SpatialTapGesture`: it fires the action on the
/// release, reporting the release position, and a release off the view is no
/// tap (as on macOS 15.8). These tests render a view, feed its hit-test
/// region to the dispatcher, and dispatch synthetic press/release events.
@MainActor
@Suite("onTapGesture")
struct OnTapGestureModifierTests {

    private final class Recorder {
        var taps: [(x: Int, y: Int)] = []
    }

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.applyRuntimeServices(from: tui)
        }
    }

    private func regionAndDispatcher(
        _ view: some View, _ ctx: RenderContext
    ) -> (HitTestRegion, MouseEventDispatcher) {
        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        return (buffer.hitTestRegions[0], dispatcher)
    }

    @Test("A press then release fires the tap once, at the release position")
    func pressReleaseFiresTap() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("btn").onTapGesture { cell in recorder.taps.append((cell.x, cell.y)) }
        let (region, dispatcher) = regionAndDispatcher(view, ctx)

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        // No tap on the press alone.
        #expect(recorder.taps.isEmpty)

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: region.offsetX + 2, y: region.offsetY))

        #expect(recorder.taps.count == 1)
        #expect(recorder.taps.first?.x == region.offsetX + 2)
        #expect(recorder.taps.first?.y == region.offsetY)
    }

    /// It used to: the handler claimed the press and tapped wherever the
    /// release landed. macOS 15.8's SwiftUI taps only on a release over the
    /// view.
    @Test("A release off the view is no tap")
    func releaseOutsideDoesNotTap() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("btn").onTapGesture { cell in recorder.taps.append((cell.x, cell.y)) }
        let (region, dispatcher) = regionAndDispatcher(view, ctx)

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        let farX = region.offsetX + region.width + 20
        let farY = region.offsetY + region.height + 20
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: farX, y: farY))

        #expect(recorder.taps.isEmpty)
    }

    @Test("A right-button click does not fire a tap")
    func rightClickIgnored() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("btn").onTapGesture { cell in recorder.taps.append((cell.x, cell.y)) }
        let (region, dispatcher) = regionAndDispatcher(view, ctx)

        _ = dispatcher.dispatch(
            MouseEvent(button: .right, phase: .pressed, x: region.offsetX, y: region.offsetY))
        _ = dispatcher.dispatch(
            MouseEvent(button: .right, phase: .released, x: region.offsetX, y: region.offsetY))

        #expect(recorder.taps.isEmpty)
    }
}
