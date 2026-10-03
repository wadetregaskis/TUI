//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DatePickerStyleTests.swift
//
//  `DatePickerStyle`: the field-shaped built-ins draw the editable field, and a
//  custom style builds the picker from its configuration.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Shows what the configuration carries.
private struct ReportingStyle: DatePickerStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.label
            Text(configuration.minimumDate == nil ? "open" : "from")
            Text(configuration.maximumDate == nil ? "open" : "to")
            Text(configuration.displayedComponents == .date ? "date" : "other")
        }
    }
}

@MainActor
@Suite("DatePickerStyle")
struct DatePickerStyleTests {
    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 2)).lines.first?.stripped ?? ""
    }

    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The field-shaped built-ins draw the field the picker always drew")
    func fieldShaped() {
        let picker = DatePicker("When", selection: .constant(date), displayedComponents: .date)
        let field = line(picker)
        for styled in [
            line(picker.datePickerStyle(.automatic)), line(picker.datePickerStyle(.field)),
            line(picker.datePickerStyle(.stepperField)), line(picker.datePickerStyle(.compact)),
        ] {
            #expect(styled == field)
        }
    }

    @Test("A custom style sees the label, the bounds and the components")
    func customStyle() {
        let bounded = DatePicker(
            "When", selection: .constant(date), in: date.addingTimeInterval(-60)..., displayedComponents: .date)
        #expect(line(bounded.datePickerStyle(ReportingStyle())) == "When from open date")
        let unbounded = DatePicker("When", selection: .constant(date), displayedComponents: .hourAndMinute)
        #expect(line(unbounded.datePickerStyle(ReportingStyle())) == "When open open other")
    }
}

@MainActor
@Suite("GraphicalDatePickerStyle")
struct GraphicalDatePickerStyleTests {
    /// A Gregorian calendar in UTC whose weeks start on Monday, so the grid is
    /// the same wherever the test runs.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// The selection, outside the view.
    private final class Selection: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
        var binding: Binding<Date> { Binding(get: { self.date }, set: { self.date = $0 }) }
    }

    private func picker(_ selection: Selection, in range: ClosedRange<Date>? = nil) -> some View {
        Group {
            if let range {
                DatePicker("", selection: selection.binding, in: range, displayedComponents: .date)
            } else {
                DatePicker("", selection: selection.binding, displayedComponents: .date)
            }
        }
        .datePickerStyle(.graphical)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
    }

    @Test("The month is a header, the weekday initials, and six weeks of days")
    func layout() {
        let lines = InputChainHarness(width: 30, height: 10).frame(picker(Selection(date(2026, 10, 3))))
            .lines.map(\.stripped)
        #expect(lines[0].contains("October 2026"), "\(lines)")
        #expect(lines[1].hasPrefix(" Mo Tu We"), "\(lines)")
        // October 2026 starts on a Thursday: three blank cells first.
        #expect(lines[2] == "           1  2  3  4", "\(lines)")
        #expect(lines.count == 8)
    }

    @Test("The arrows move the selection by day and week, Page Down by month, keeping the time")
    func keys() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 30, height: 10)
        harness.play([KeyEvent(key: .right), KeyEvent(key: .down)]) { picker(selection) }
        #expect(selection.date == date(2026, 10, 11))
        harness.play([KeyEvent(key: .pageDown)]) { picker(selection) }
        #expect(selection.date == date(2026, 11, 11))
        #expect(harness.frame(picker(selection)).lines.first?.stripped.contains("November 2026") == true)
    }

    @Test("The selection stays within the range")
    func clamped() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 30, height: 10)
        harness.play([KeyEvent(key: .left), KeyEvent(key: .left)]) {
            picker(selection, in: date(2026, 10, 2, 0)...date(2026, 12, 31))
        }
        #expect(selection.date == date(2026, 10, 2, 0), "clamped to the start of the range")
    }

    @Test("A click picks a day; the arrows turn the month without moving the selection")
    func clicks() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 30, height: 10)
        harness.frame(picker(selection))
        // Row 3 is the week of the 5th; the 7th is its third column.
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 7, y: 3))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 7, y: 3))
        #expect(selection.date == date(2026, 10, 7))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 20, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 20, y: 0))
        #expect(harness.frame(picker(selection)).lines.first?.stripped.contains("November 2026") == true)
        #expect(selection.date == date(2026, 10, 7))
    }
}
