//  🖥️ TUI — A Terminal UI framework for Swift
//  OnScrollGestureModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Tests for the `.onScrollGesture(_:)` modifier, built on
/// `.onMouseEvent`: it fires its action with a `ScrollDirection` for
/// each scroll-wheel tick inside the view and consumes the event, while
/// ignoring non-scroll events; and `.onScrollWheel(_:)`, which consumes only
/// what its action takes.
@MainActor
@Suite("onScrollGesture")
struct OnScrollGestureModifierTests {

    private final class Recorder {
        var directions: [ScrollDirection] = []
    }

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.applyRuntimeServices(from: tui)
        }
    }

    @Test(
        "Each scroll-wheel button maps to its direction and is consumed",
        arguments: [
            (MouseButton.scrollUp, ScrollDirection.up),
            (.scrollDown, .down),
            (.scrollLeft, .left),
            (.scrollRight, .right),
        ])
    func mapsScrollButtonToDirection(_ button: MouseButton, _ direction: ScrollDirection) {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("x").onScrollGesture { recorder.directions.append($0) }

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        let region = buffer.hitTestRegions[0]

        let consumed = dispatcher.dispatch(
            MouseEvent(button: button, phase: .scrolled, x: region.offsetX, y: region.offsetY))

        #expect(consumed)
        #expect(recorder.directions == [direction])
    }

    @Test("A non-scroll event does not fire the scroll action")
    func ignoresNonScroll() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("x").onScrollGesture { recorder.directions.append($0) }

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        let region = buffer.hitTestRegions[0]

        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))

        #expect(!consumed)
        #expect(recorder.directions.isEmpty)
    }

    // MARK: - Declining a tick

    private final class Gate {
        var accepts: Bool
        var directions: [ScrollDirection] = []
        init(accepts: Bool) { self.accepts = accepts }

        func offer(_ direction: ScrollDirection) -> Bool {
            directions.append(direction)
            return accepts
        }
    }

    /// The text a ScrollView of 100 rows shows after one wheel tick down over
    /// its content, which carries a handler that `gate` answers for.
    private func rowsAfterOneTick(_ gate: Gate) -> String {
        let ctx = context(width: 30, height: 8)
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<100, id: \.self) { Text("Row \($0)") }
            }
            .onScrollWheel { gate.offer($0) }
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(renderToBuffer(view, context: ctx).hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
        return renderToBuffer(view, context: ctx).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("A handler that declines the tick lets the ScrollView around it scroll")
    func decliningHandlerPassesTheTickOn() {
        let gate = Gate(accepts: false)
        let text = rowsAfterOneTick(gate)
        #expect(gate.directions == [.down], "the handler was not offered the tick")
        #expect(!text.contains("Row 0"), "the ScrollView did not scroll:\n\(text)")
    }

    @Test("A handler that takes the tick keeps it from the ScrollView, as the Void form always does")
    func acceptingHandlerConsumesTheTick() {
        let gate = Gate(accepts: true)
        let text = rowsAfterOneTick(gate)
        #expect(gate.directions == [.down])
        #expect(text.contains("Row 0"), "the ScrollView scrolled a tick the handler took:\n\(text)")
    }

    @Test("A declined tick is reported as not consumed where nothing is behind the view")
    func declinedTickIsNotConsumed() {
        let ctx = context()
        let view = Text("x").onScrollWheel { _ in false }
        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        let region = buffer.hitTestRegions[0]
        #expect(!dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: region.offsetX, y: region.offsetY)))
    }
}
