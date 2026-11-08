//  🖥️ TUI — A Terminal UI framework for Swift
//  DatePickerTypedComponentTests.swift
//
//  Digits typed into a `DatePicker` component are written to the date as they
//  arrive, and each write re-clamped the day to its month and the date to the
//  range — from the date the previous, partial write had already damaged.
//  Typing the year "2027" went through years 2, 20 and 202, each clamped to the
//  range's floor, so the month and day ended up the floor's; typing "2024" over
//  29 February went through year 2, whose February has 28 days, and lost the
//  leap day. Each partial value is now applied to the date as it was before
//  the first digit, so only the component being typed changes.
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
@Suite("DatePicker typed components")
struct DatePickerTypedComponentTests {

    private final class Sink {
        var value: Date
        init(_ value: Date) { self.value = value }
        var binding: Binding<Date> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func type(_ digits: String, into handler: DatePickerHandler) {
        for digit in digits { _ = handler.handleKeyEvent(KeyEvent(key: .character(digit))) }
    }

    @Test("Typing a year inside a range keeps the month and day")
    func yearInsideARange() {
        let sink = Sink(date(2025, 7, 20))
        let model = DateFieldModel(calendar: calendar, components: .date, range: date(2020, 3, 15)...date(2030, 1, 1))
        let handler = DatePickerHandler(focusID: "d", selection: sink.binding, model: model)
        handler.activeIndex = 0
        type("2027", into: handler)
        #expect(sink.value == date(2027, 7, 20), "\(sink.value)")
    }

    @Test("Typing the year over a leap day keeps the leap day")
    func yearOverALeapDay() {
        let sink = Sink(date(2024, 2, 29))
        let model = DateFieldModel(calendar: calendar, components: .date, range: nil)
        let handler = DatePickerHandler(focusID: "d", selection: sink.binding, model: model)
        handler.activeIndex = 0
        type("2024", into: handler)
        #expect(sink.value == date(2024, 2, 29), "\(sink.value)")
    }

    @Test("A digit after the component advances starts from the date as it then is")
    func nextComponentStartsFromTheTypedDate() {
        let sink = Sink(date(2024, 2, 29))
        let model = DateFieldModel(calendar: calendar, components: .date, range: nil)
        let handler = DatePickerHandler(focusID: "d", selection: sink.binding, model: model)
        handler.activeIndex = 0
        // The year fills and advances to the month, whose "0" then "3" are
        // applied to 2025-02-28 (2025 has no 29 February).
        type("202503", into: handler)
        #expect(sink.value == date(2025, 3, 28), "\(sink.value)")
    }
}
