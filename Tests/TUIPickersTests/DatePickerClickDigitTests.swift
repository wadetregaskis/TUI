//  🖥️ TUI — A Terminal UI framework for Swift
//  DatePickerClickDigitTests.swift
//
//  A click on a `DatePicker` component chose it but left the digits half-typed
//  into the previous one in the buffer, so the next digit was appended to them:
//  "2" into the year, a click on the month, then "5" set the month to 25,
//  clamped to 12. Every key that changes the component cleared the buffer; the
//  click wrote the active index directly and could not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIPickers
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("DatePicker click and typed digits")
struct DatePickerClickDigitTests {

    private final class Sink {
        var value: Date
        init(_ value: Date) { self.value = value }
        var binding: Binding<Date> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    @Test("Typing after a click on another component starts a fresh number there")
    func clickClearsHalfTypedDigits() {
        // The render takes the environment's calendar, the current one.
        let calendar = Calendar.current
        let sink = Sink(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 12))!)
        let context = makeRenderContext(width: 40, height: 1)
        guard let dispatcher = context.environment.mouseEventDispatcher,
            let focusManager = context.environment.focusManager
        else {
            Issue.record("the context carries no dispatcher")
            return
        }
        dispatcher.setActiveSupport(.standard)
        let buffer = renderToBuffer(
            DatePicker(selection: sink.binding, displayedComponents: .date) { EmptyView() }, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = buffer.hitTestRegions.max(by: { $0.width < $1.width }) else {
            Issue.record("expected a date-picker hit-test region")
            return
        }
        func click(_ column: Int) {
            for phase in [MousePhase.pressed, .released] {
                _ = dispatcher.dispatch(
                    MouseEvent(button: .left, phase: phase, x: region.offsetX + column, y: region.offsetY))
            }
        }
        // "YYYY-MM-DD": the year at +0…3, the month at +5…6.
        click(0)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character("2")))
        click(5)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character("5")))
        #expect(calendar.component(.month, from: sink.value) == 5, "the 5 did not extend the year's 2 into 25")
    }
}
