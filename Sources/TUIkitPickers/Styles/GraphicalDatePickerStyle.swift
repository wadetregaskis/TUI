//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GraphicalDatePickerStyle.swift
//
//  The graphical date picker: a month calendar to pick the day from, and the
//  time field under it when the picker shows the time.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A date picker style that displays an interactive calendar.
///
/// ```
///  ◀   October 2026   ▶
///  Mo Tu We Th Fr Sa Su
///            1  2  3  4
///   5  6  7  8  9 10 11
///   …
/// ```
///
/// One focus stop. Left and Right move the selection a day, Up and Down a
/// week, Page Up and Page Down a month, Home and End to the month's first and
/// last day; a click picks a day, and ◀ and ▶ turn the month shown. The
/// selection keeps its time of day and stays within the picker's range, whose
/// days outside it are dimmed. A picker that shows the time has the hour and
/// minute field under the calendar; SwiftUI draws a clock there.
public struct GraphicalDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates a graphical date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _GraphicalDatePicker(configuration: configuration)
    }
}

extension DatePickerStyle where Self == GraphicalDatePickerStyle {
    /// A date picker style that displays an interactive calendar.
    public static var graphical: GraphicalDatePickerStyle { GraphicalDatePickerStyle() }
}

/// The calendar, its label above it, and the time field under it.
struct _GraphicalDatePicker: View {
    let configuration: DatePickerStyleConfiguration
    var focusID: String?
    var isDisabled = false

    var body: some View {
        let components = configuration.displayedComponents
        VStack(alignment: .leading, spacing: 0) {
            _CollapsingLabel(label: configuration.label, controlDisabled: isDisabled)
            if components.contains(.date) {
                _DatePickerCalendarCore(
                    selection: configuration.$selection, range: configuration.range,
                    focusID: focusID, isDisabled: isDisabled)
            }
            if components.contains(.hourAndMinute) {
                _DatePickerCore(
                    selection: configuration.$selection, range: configuration.range,
                    displayedComponents: .hourAndMinute, focusID: nil, isDisabled: isDisabled)
            }
        }
    }
}

// MARK: - Handler

/// The calendar's focus stop: moves the selection by day, week and month, and
/// keeps the month shown.
final class _DatePickerCalendarHandler: PersistedFocusable {
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    var canBeFocused = true
    var selection: Binding<Date>
    var range: ClosedRange<Date>?
    var calendar: Calendar

    /// What Return does: a `.compact` picker's calendar closes. `nil` — Return
    /// goes on to the page — for a `.graphical` picker's. Re-set every render.
    var onReturn: (() -> Void)?

    /// The first day of the month shown, which ◀ and ▶ turn without moving the
    /// selection; a selection moved into another month brings it along.
    var displayedMonth: Date

    init(focusID: String, selection: Binding<Date>, range: ClosedRange<Date>?, calendar: Calendar) {
        self.focusID = focusID
        self.selection = selection
        self.range = range
        self.calendar = calendar
        self.displayedMonth = Self.startOfMonth(selection.wrappedValue, in: calendar)
    }

    static func startOfMonth(_ date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        let current = selection.wrappedValue
        switch event.key {
        case .left: select(calendar.date(byAdding: .day, value: -1, to: current))
        case .right: select(calendar.date(byAdding: .day, value: 1, to: current))
        case .up: select(calendar.date(byAdding: .day, value: -7, to: current))
        case .down: select(calendar.date(byAdding: .day, value: 7, to: current))
        case .pageUp: select(calendar.date(byAdding: .month, value: -1, to: current))
        case .pageDown: select(calendar.date(byAdding: .month, value: 1, to: current))
        case .enter:
            guard let onReturn else { return false }
            onReturn()
        case .home: select(calendar.dateInterval(of: .month, for: current)?.start.keepingTime(of: current, in: calendar))
        case .end:
            let last = calendar.dateInterval(of: .month, for: current).flatMap {
                calendar.date(byAdding: .day, value: -1, to: $0.end)
            }
            select(last?.keepingTime(of: current, in: calendar))
        default: return false
        }
        return true
    }

    /// Selects `date`, clamped to the range, and shows its month.
    func select(_ date: Date?) {
        guard let date else { return }
        let clamped = range.map { min(max(date, $0.lowerBound), $0.upperBound) } ?? date
        selection.wrappedValue = clamped
        displayedMonth = Self.startOfMonth(clamped, in: calendar)
    }

    /// Picks `day` of the month shown, keeping the selection's time of day.
    func pick(day: Date) {
        select(day.keepingTime(of: selection.wrappedValue, in: calendar))
    }

    /// Shows the month `delta` months from the one shown.
    func turn(by delta: Int) {
        if let month = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = month
        }
    }
}

extension Date {
    /// This date's day with `other`'s time of day.
    func keepingTime(of other: Date, in calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: other)
        var day = calendar.dateComponents([.era, .year, .month, .day], from: self)
        day.hour = time.hour
        day.minute = time.minute
        day.second = time.second
        day.nanosecond = time.nanosecond
        return calendar.date(from: day) ?? self
    }
}

// MARK: - Core

/// `StateStorage` property indices for ``_DatePickerCalendarCore``.
private enum DatePickerCalendarStateIndex {
    static let focusID = 0
    static let handler = 1
    /// Whether a calendar that takes the focus as it appears has taken it.
    static let hasTakenFocus = 2
}

/// Draws the month shown and registers the calendar's focus stop and click
/// targets.
struct _DatePickerCalendarCore: View, Renderable, Layoutable {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let focusID: String?
    let isDisabled: Bool

    /// What Return does on the calendar, if anything — a `.compact` picker's
    /// closes it.
    var onReturn: (() -> Void)?

    /// Whether the calendar takes the focus the first time it is drawn — a
    /// `.compact` picker's, which appears in a popover because the keys asked
    /// for it, and whose popover would otherwise wait for a first key to find
    /// it. Each opening draws it anew, so each takes the focus.
    var takesFocusOnAppear = false

    var body: Never {
        fatalError("_DatePickerCalendarCore renders via Renderable")
    }

    private typealias StateIndex = DatePickerCalendarStateIndex

    /// Seven days of three cells, and a header, the weekday row and six weeks —
    /// six whatever the month, so turning it never changes the height.
    static let width = 21
    static let height = 8

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(Self.width, Self.height)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var calendar = context.environment.calendar
        calendar.timeZone = context.environment.timeZone
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "calendar",
            propertyIndex: StateIndex.focusID)
        let handler = handler(focusID: persistedFocusID, calendar: calendar, context: context)
        handler.canBeFocused = !isDisabled
        FocusRegistration.register(context: context, handler: handler, focusID: persistedFocusID)
        if takesFocusOnAppear, !isDisabled {
            takeFocusOnce(focusID: persistedFocusID, context: context)
        }
        let isFocused = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))

        let palette = context.environment.palette
        let month = handler.displayedMonth
        var lines = [header(month: month, isFocused: isFocused, calendar: calendar, palette: palette)]
        lines.append(weekdayRow(calendar: calendar, palette: palette))
        let days = monthGrid(month: month, calendar: calendar)
        for week in 0..<6 {
            lines.append(
                (0..<7).map { column in
                    dayCell(days[week * 7 + column], isDisabled: isDisabled, calendar: calendar, palette: palette)
                }.joined())
        }
        var buffer = FrameBuffer(lines: lines)
        if !isDisabled, !context.isMeasuring {
            attachMouseHandler(to: &buffer, handler: handler, days: days, focusID: persistedFocusID, context: context)
        }
        return buffer
    }

    /// Focuses the calendar on the first frame that draws it, and never again
    /// while it stays drawn.
    private func takeFocusOnce(focusID: String, context: RenderContext) {
        guard !context.isMeasuring, let storage = context.stateStorage,
            let focusManager = context.environment.focusManager
        else { return }
        // A side effect of drawing, which a memo serving this frame must not skip.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let taken: StateBox<Bool> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.hasTakenFocus),
            default: false)
        guard !taken.value else { return }
        taken.value = true
        focusManager.focus(id: focusID)
    }

    private func handler(
        focusID: String, calendar: Calendar, context: RenderContext
    ) -> _DatePickerCalendarHandler {
        let box: StateBox<_DatePickerCalendarHandler> = context.stateStorage!.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.handler),
            default: _DatePickerCalendarHandler(
                focusID: focusID, selection: selection, range: range, calendar: calendar))
        let handler = box.value
        // Every field the view declares, every frame: a persisted handler keeps
        // the values of the frame that made it otherwise.
        handler.selection = selection
        handler.range = range
        handler.calendar = calendar
        handler.onReturn = onReturn
        return handler
    }

    // MARK: Drawing

    /// ` ◀   October 2026   ▶`: the month centred between the two arrows.
    private func header(month: Date, isFocused: Bool, calendar: Calendar, palette: any Palette) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        let title = formatter.string(from: month)
        let inner = Self.width - 4
        let fitted = title.count > inner ? String(title.prefix(inner)) : title
        let left = (inner - fitted.count) / 2
        let titleText = String(repeating: " ", count: left) + fitted
            + String(repeating: " ", count: inner - left - fitted.count)
        let arrow = (isFocused ? palette.accent : palette.foregroundSecondary).opaqueSpelling
        return ANSIRenderer.colorize(" \(TerminalSymbols.leftArrow)", foreground: arrow)
            + ANSIRenderer.colorize(titleText, foreground: palette.foreground.opaqueSpelling, bold: isFocused)
            + ANSIRenderer.colorize("\(TerminalSymbols.rightArrow) ", foreground: arrow)
    }

    /// The weekday initials, starting on the calendar's first weekday.
    private func weekdayRow(calendar: Calendar, palette: any Palette) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols.isEmpty
            ? calendar.shortWeekdaySymbols : calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = (0..<7).map { symbols[(first + $0) % symbols.count] }
        let text = ordered.map { " " + String($0.prefix(2)).padding(toLength: 2, withPad: " ", startingAt: 0) }
            .joined()
        return ANSIRenderer.colorize(text, foreground: palette.foregroundTertiary.opaqueSpelling)
    }

    /// The 42 cells of six weeks, starting on the week of the month's first
    /// day; `nil` for a cell outside the month.
    private func monthGrid(month: Date, calendar: Calendar) -> [Date?] {
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return (0..<42).map { cell in
            let day = cell - leading
            guard day >= 0, day < count else { return nil }
            return calendar.date(byAdding: .day, value: day, to: month)
        }
    }

    /// One day: its number in three cells, the selected day in the accent,
    /// today in the accent's ink, a day out of range dimmed.
    private func dayCell(_ day: Date?, isDisabled: Bool, calendar: Calendar, palette: any Palette) -> String {
        guard let day else { return "   " }
        let number = calendar.component(.day, from: day)
        let text = (number < 10 ? "  " : " ") + String(number)
        let inRange = range.map { range in
            let start = calendar.startOfDay(for: range.lowerBound)
            return day >= start && day <= range.upperBound
        } ?? true
        if calendar.isDate(day, inSameDayAs: selection.wrappedValue) {
            let fill = isDisabled ? palette.foregroundTertiary : palette.accent
            return " " + ANSIRenderer.colorize(
                String(text.dropFirst()), foreground: palette.background.opaqueSpelling,
                background: fill.opaqueSpelling)
        }
        let ink: Color =
            !inRange || isDisabled
            ? palette.foregroundTertiary
            : calendar.isDateInToday(day) ? palette.accent : palette.foreground
        return ANSIRenderer.colorize(text, foreground: ink.opaqueSpelling)
    }

    // MARK: Mouse

    /// Clicks on ◀ and ▶ turn the month; a click on a day in range picks it.
    private func attachMouseHandler(
        to buffer: inout FrameBuffer, handler: _DatePickerCalendarHandler, days: [Date?], focusID: String,
        context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        let focusManager = context.environment.focusManager
        let range = self.range
        let calendar = handler.calendar
        let handlerID = dispatcher.register(in: context) { event in
            guard event.button == .left, event.phase == .released else {
                return event.button == .left && event.phase == .pressed
            }
            focusManager?.focus(id: focusID)
            if event.y == 0 {
                if event.x <= 2 { handler.turn(by: -1) }
                if event.x >= Self.width - 3 { handler.turn(by: 1) }
                return true
            }
            guard event.y >= 2, event.x >= 0, event.x < Self.width else { return true }
            let cell = (event.y - 2) * 7 + event.x / 3
            guard days.indices.contains(cell), let day = days[cell] else { return true }
            if let range, day < calendar.startOfDay(for: range.lowerBound) || day > range.upperBound {
                return true
            }
            handler.pick(day: day)
            return true
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: Self.width, height: Self.height,
                handlerID: handlerID, focusID: focusID))
    }
}
