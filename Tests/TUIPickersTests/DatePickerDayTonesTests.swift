//  🖥️ TUI — A Terminal UI framework for Swift
//  DatePickerDayTonesTests.swift
//
//  A `.graphical` date picker's calendar draws the weekend in a tone of its
//  own, by the calendar's locale, and, where asked, the days gone by faint
//  (the owner's request, 2026-10-27).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIPickers
@testable import TUITestSupport

@MainActor
@Suite("A calendar's weekend and past days")
struct DatePickerDayTonesTests {
    /// A Gregorian calendar in UTC, weeks from Monday, in `locale`.
    private func calendar(_ locale: String = "en_US") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    /// The calendar's rows for a month holding `year`-`month`-10, drawn as
    /// the environment says.
    private func rows(
        _ year: Int, _ month: Int, locale: String = "en_US", _ adjust: (AnyView) -> AnyView = { $0 }
    ) -> [String] {
        let calendar = calendar(locale)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 10, hour: 9))!
        let picker = DatePicker("", selection: .constant(date), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
        return InputChainHarness(width: 30, height: 10).frame(adjust(AnyView(picker))).lines
    }

    /// The state under a day's number: the grid's `week` row (0 the first),
    /// weekday `column` (0 Monday).
    private func state(_ rows: [String], week: Int, column: Int) -> SGRState {
        rows[2 + week].ansiSGRStateAt(visibleColumn: column * 3 + 2)
    }

    @Test("The weekend is drawn in a tone of its own, the weekdays alike")
    func weekendTone() {
        // March 2099: the second week runs Monday 2 to Sunday 8, none selected
        // and none today.
        let lines = rows(2099, 3)
        let monday = state(lines, week: 1, column: 0)
        #expect(state(lines, week: 1, column: 1) == monday, "Tuesday is a weekday as Monday is")
        #expect(state(lines, week: 1, column: 5) != monday, "Saturday has a tone of its own")
        #expect(state(lines, week: 1, column: 6) == state(lines, week: 1, column: 5))
    }

    @Test("The locale says which days the weekend is")
    func weekendByLocale() {
        // In Saudi Arabia the weekend is Friday and Saturday.
        let lines = rows(2099, 3, locale: "ar_SA")
        let monday = state(lines, week: 1, column: 0)
        #expect(state(lines, week: 1, column: 4) != monday, "Friday is the weekend there")
        #expect(state(lines, week: 1, column: 6) == monday, "Sunday is a working day there")
    }

    @Test("Turned off, the weekend is drawn as the weekdays are")
    func weekendOff() {
        let lines = rows(2099, 3) { AnyView($0.datePickerDistinguishesWeekends(false)) }
        #expect(state(lines, week: 1, column: 5) == state(lines, week: 1, column: 0))
    }

    @Test("Asked, days gone by are faint, and days to come are not")
    func pastDays() {
        let past = rows(2001, 3) { AnyView($0.datePickerDistinguishesPastDays()) }
        #expect(state(past, week: 1, column: 0).isFaint)
        let future = rows(2099, 3) { AnyView($0.datePickerDistinguishesPastDays()) }
        #expect(!state(future, week: 1, column: 0).isFaint)
        let unasked = rows(2001, 3)
        #expect(!state(unasked, week: 1, column: 0).isFaint, "off unless asked")
    }
}
