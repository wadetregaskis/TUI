//  🖥️ TUI — A Terminal UI framework for Swift
//  SliderStepGridTests.swift
//
//  A slider's keys and wheel step along the grid a click on its track snaps
//  to (deviations sweep, likely bug 23; semantic audit 69). A value off the
//  grid — one the app wrote — used to move a whole step from where it was, so
//  the arrows reached values a click never could: 0.33 went to 0.43 where a
//  click lands on 0.3 or 0.4.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUINumericControls
@testable import TUITestSupport

@MainActor
@Suite("A slider's keys and wheel step along the click's grid")
struct SliderStepGridTests {
    private func handler(_ value: Double, in bounds: ClosedRange<Double> = 0...1) -> (SliderHandler<Double>, () -> Double) {
        final class Box {
            var value: Double
            init(_ value: Double) { self.value = value }
        }
        let box = Box(value)
        let handler = SliderHandler<Double>(
            focusID: "slider", value: Binding(get: { box.value }, set: { box.value = $0 }), bounds: bounds, step: 0.1)
        return (handler, { box.value })
    }

    @Test("Off the grid, an arrow goes to the grid's next value that way")
    func offGrid() {
        let (up, upValue) = handler(0.33)
        up.increment()
        #expect(abs(upValue() - 0.4) < 1e-9, "\(upValue())")
        let (down, downValue) = handler(0.33)
        down.decrement()
        #expect(abs(downValue() - 0.3) < 1e-9, "\(downValue())")
        let (shifted, shiftedValue) = handler(0.33)
        shifted.increment(multiplier: 5)
        #expect(abs(shiftedValue() - 0.8) < 1e-9, "\(shiftedValue())")
    }

    @Test("On the grid, an arrow moves one step, float error and all")
    func onGrid() {
        let (up, upValue) = handler(0.3)
        up.increment()
        #expect(abs(upValue() - 0.4) < 1e-9, "\(upValue())")
        // 0.1 + 0.2 is 0.30000000000000004, a hair above the grid value.
        let (down, downValue) = handler(0.1 + 0.2)
        down.decrement()
        #expect(abs(downValue() - 0.2) < 1e-9, "\(downValue())")
    }

    @Test("The grid starts at the range's lower bound, and the ends still clamp")
    func gridOrigin() {
        let (up, upValue) = handler(0.33, in: 0.05...1)
        up.increment()
        #expect(abs(upValue() - 0.35) < 1e-9, "\(upValue())")
        let (top, topValue) = handler(0.98)
        top.increment()
        #expect(topValue() == 1)
    }

    @Test("A wheel notch steps along the grid too")
    func wheel() {
        var value = 0.33
        let context = makeRenderContext(width: 40, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let slider = Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1, step: 0.1)
        let buffer = renderToBuffer(slider, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = buffer.hitTestRegions.max(by: { $0.width < $1.width }) else {
            Issue.record("expected a slider hit-test region")
            return
        }
        _ = dispatcher.dispatch(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: region.offsetX + region.width / 2, y: region.offsetY))
        #expect(abs(value - 0.3) < 1e-9 || abs(value - 0.4) < 1e-9, "the notch left the grid: \(value)")
    }
}
