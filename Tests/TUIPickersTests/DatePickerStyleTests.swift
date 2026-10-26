//  🖥️ TUI — A Terminal UI framework for Swift
//  DatePickerStyleTests.swift
//
//  `DatePickerStyle`: the field-shaped built-ins draw the editable field, and a
//  custom style builds the picker from its configuration.
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

@MainActor
@Suite("Stepper-field and compact date pickers")
struct StepperFieldAndCompactDatePickerTests {
    /// A Gregorian calendar in UTC whose weeks start on Monday, so the field
    /// and the grid are the same wherever the test runs.
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

    private func picker(
        _ selection: Selection, style: some DatePickerStyle, components: DatePickerComponents = .date,
        stepper: Bool? = nil, disabled: Bool = false
    ) -> some View {
        Group {
            if let stepper {
                DatePicker("", selection: selection.binding, displayedComponents: components)
                    .datePickerShowsStepper(stepper)
            } else {
                DatePicker("", selection: selection.binding, displayedComponents: components)
            }
        }
        .disabled(disabled)
        .datePickerStyle(style)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
    }

    /// The column `glyph` is drawn at on the first row of `buffer`.
    private func column(of glyph: Character, in buffer: FrameBuffer) -> Int? {
        let row = buffer.lines.first?.stripped ?? ""
        return row.firstIndex(of: glyph).map { row.distance(from: row.startIndex, to: $0) }
    }

    /// Everything the popovers over `buffer` draw, stripped.
    private func popoverText(_ buffer: FrameBuffer) -> String {
        buffer.overlays.flatMap { $0.content.lines.map(\.stripped) }.joined(separator: "\n")
    }

    @Test("A stepper field draws its stepper only where it is asked for")
    func stepperIsOptIn() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 40, height: 3)
        let plain = harness.frame(picker(selection, style: .stepperField)).lines.first?.stripped ?? ""
        #expect(plain == "2026-10-03", "drawn by default: \(plain)")
        let asked = harness.frame(picker(selection, style: .stepperField, stepper: true)).lines.first?.stripped
        #expect(asked == "2026-10-03 ▲▼")
        let field = harness.frame(picker(selection, style: .field, stepper: true)).lines.first?.stripped
        #expect(field == "2026-10-03", "only a stepper field has a stepper")
    }

    /// A click on one of the stepper's arrows: the press acts on the next
    /// main-actor turn (the arrows repeat while held, as a `Stepper`'s do), so
    /// a yield before the release — not a sleep, which a timed wake can lose.
    private func click(_ harness: InputChainHarness, at x: Int, row: Int = 0) async {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        await Task.yield()
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: row))
    }

    @Test("▲ steps the selected component up and ▼ down, and focuses the field")
    func stepperArrowsStep() async {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 40, height: 4)
        let build = {
            VStack {
                Button("First") {}
                picker(selection, style: .stepperField, stepper: true)
            }
        }
        let buffer = harness.frame(build())
        let row = buffer.lines[1].stripped
        guard let up = row.firstIndex(of: "▲").map({ row.distance(from: row.startIndex, to: $0) }) else {
            Issue.record("no stepper: \(buffer.lines.map(\.stripped))")
            return
        }
        // The button has the focus; the year is the field's selected component.
        await click(harness, at: up, row: 1)
        #expect(selection.date == date(2027, 10, 3))
        #expect(harness.focusManager.currentFocusedID?.hasPrefix("datepicker") == true, "the field did not take the focus")
        // Right twice to the day, then ▼ twice.
        harness.play([KeyEvent(key: .right), KeyEvent(key: .right)], build)
        harness.frame(build())
        await click(harness, at: up + 1, row: 1)
        harness.frame(build())
        await click(harness, at: up + 1, row: 1)
        #expect(selection.date == date(2027, 10, 1))
    }

    @Test("A disabled stepper field's arrows step nothing")
    func disabledStepper() async {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 40, height: 3)
        let buffer = harness.frame(picker(selection, style: .stepperField, stepper: true, disabled: true))
        await click(harness, at: column(of: "▲", in: buffer) ?? 0)
        #expect(selection.date == date(2026, 10, 3))
    }

    @Test("Return opens a compact picker's calendar, whose keys move the day; Return closes it")
    func compactReturnOpensTheCalendar() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 40, height: 14)
        let build = { picker(selection, style: .compact) }
        #expect(popoverText(harness.frame(build())).isEmpty, "the calendar starts closed")
        harness.play([KeyEvent(key: .enter)], build)
        let opened = popoverText(harness.frame(build()))
        #expect(opened.contains("October 2026"), "Return did not open the calendar: \(opened)")
        // The calendar has the keys: Right is a day, not the field's next component.
        harness.play([KeyEvent(key: .right)], build)
        #expect(selection.date == date(2026, 10, 4))
        harness.play([KeyEvent(key: .enter)], build)
        #expect(popoverText(harness.frame(build())).isEmpty, "Return in the calendar did not close it")
        #expect(selection.date == date(2026, 10, 4))
        // Back on the field, whose Return opens the calendar again — with the keys.
        harness.play([KeyEvent(key: .enter), KeyEvent(key: .down)], build)
        #expect(selection.date == date(2026, 10, 11))
    }

    @Test("Escape closes a compact picker's calendar")
    func compactEscapeCloses() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 40, height: 14)
        let build = { picker(selection, style: .compact) }
        harness.play([KeyEvent(key: .enter), KeyEvent(key: .escape)], build)
        #expect(popoverText(harness.frame(build())).isEmpty)
    }

    @Test("A click on a compact picker's field opens its calendar")
    func compactClickOpens() {
        let selection = Selection(date(2026, 10, 3))
        let harness = InputChainHarness(width: 40, height: 14)
        let build = { picker(selection, style: .compact) }
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
        #expect(popoverText(harness.frame(build())).contains("October 2026"))
    }

    /// macOS draws a compact picker of a date and a time as two fields, and
    /// only the date's opens the calendar. Here they are one field, and a
    /// click on the hour opened the calendar — which took the keyboard from
    /// the hour the click had just chosen.
    @Test("A click on a compact picker's time chooses that component and opens no calendar")
    func compactClickOnTheTime() {
        let selection = Selection(date(2026, 10, 3, 9))
        let harness = InputChainHarness(width: 40, height: 14)
        let build = { picker(selection, style: .compact, components: [.date, .hourAndMinute]) }
        let drawn = harness.frame(build())
        let row = drawn.lines.first?.stripped ?? ""
        guard let hour = row.range(of: "09").map({ row.distance(from: row.startIndex, to: $0.lowerBound) }) else {
            Issue.record("no hour in \(row)")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: hour, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: hour, y: 0))
        #expect(popoverText(harness.frame(build())).isEmpty, "a click on the hour opened the calendar")
        harness.play([KeyEvent(key: .up)], build)
        #expect(calendar.component(.hour, from: selection.date) == 10, "Up did not step the hour the click chose")

        // The date's components still open it.
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
        #expect(popoverText(harness.frame(build())).contains("October 2026"))
    }

    @Test("A compact picker of the time alone, or a disabled one, has no calendar to open")
    func compactWithoutACalendar() {
        let selection = Selection(date(2026, 10, 3))
        let timeOnly = InputChainHarness(width: 40, height: 14)
        let time = { picker(selection, style: .compact, components: .hourAndMinute) }
        timeOnly.play([KeyEvent(key: .enter)], time)
        #expect(popoverText(timeOnly.frame(time())).isEmpty)

        let disabled = InputChainHarness(width: 40, height: 14)
        let off = { picker(selection, style: .compact, disabled: true) }
        disabled.frame(off())
        disabled.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        disabled.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
        #expect(popoverText(disabled.frame(off())).isEmpty)
    }
}
