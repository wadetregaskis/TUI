//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicalDatePickerWideTextTests.swift
//
//  The graphical `DatePicker` cut and padded its weekday initials and centred
//  its month title in CHARACTERS. A Japanese weekday ("日") is one character
//  and two cells, so each weekday column came out four cells wide over a day
//  grid of three, and the title's "▶" was pushed past the calendar's edge. A
//  Chinese short weekday ("周日") is two characters and four cells, and cut to
//  two cells every one of them read "周".
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPickers
@testable import TUITestSupport

@MainActor
@Suite("Graphical DatePicker with wide text")
struct GraphicalDatePickerWideTextTests {

    private final class Selection {
        var date: Date
        init(_ date: Date) { self.date = date }
        var binding: Binding<Date> { Binding(get: { self.date }, set: { self.date = $0 }) }
    }

    private func lines(locale identifier: String) -> [String] {
        let locale = Locale(identifier: identifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        let selection = Selection(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!)
        let picker = DatePicker("", selection: selection.binding, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.locale, locale)
        return InputChainHarness(width: 30, height: 10).frame(picker).lines.map {
            $0.stripped.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        }
    }

    /// Where `glyph` starts on `line`, in cells.
    private func column(of glyph: String, in line: String) -> Int? {
        line.range(of: glyph).map { String(line[..<$0.lowerBound]).strippedLength }
    }

    @Test("Wide weekday initials keep the three-cell columns of the day grid", arguments: ["ja_JP", "zh_CN"])
    func weekdayColumns(locale: String) {
        let lines = lines(locale: locale)
        #expect(lines.count >= 3, "\(lines)")
        guard lines.count >= 3 else { return }
        // Seven columns of three cells: a blank and a two-cell initial.
        #expect(lines[1].strippedLength == 21, "the weekday row is \(lines[1].strippedLength) cells: \(lines[1])")
        let initials = lines[1].split(separator: " ")
        #expect(Set(initials).count == 7, "seven different initials: \(initials)")
    }

    @Test("A wide month title keeps the arrows where an English one has them", arguments: ["ja_JP", "zh_CN"])
    func titleArrows(locale: String) {
        let english = lines(locale: "en_US")
        let wide = lines(locale: locale)
        #expect(
            column(of: TerminalSymbols.rightArrow, in: wide[0]) == column(of: TerminalSymbols.rightArrow, in: english[0]),
            "\(wide[0]) against \(english[0])")
    }
}
