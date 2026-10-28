//  🖥️ TUI — A Terminal UI framework for Swift
//  DatePickerDayTones.swift
//
//  Which days a `.graphical` date picker's calendar draws in a tone of their
//  own: the weekend, in the secondary text colour (the calendar's locale
//  says which days it is), and, where an app asks, the days already past,
//  faint. The owner's request (2026-10-27), and TUI's own: SwiftUI's calendar
//  draws every day alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Asking for them

private struct DatePickerDistinguishesWeekendsKey: EnvironmentKey {
    static let defaultValue = true
}

private struct DatePickerDistinguishesPastDaysKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a `.graphical` ``DatePicker``'s calendar draws the weekend's
    /// days in a tone of their own (default `true`). Set with
    /// ``View/datePickerDistinguishesWeekends(_:)``.
    public var datePickerDistinguishesWeekends: Bool {
        get { self[DatePickerDistinguishesWeekendsKey.self] }
        set { self[DatePickerDistinguishesWeekendsKey.self] = newValue }
    }

    /// Whether a `.graphical` ``DatePicker``'s calendar draws the days before
    /// today faint (default `false`). Set with
    /// ``View/datePickerDistinguishesPastDays(_:)``.
    public var datePickerDistinguishesPastDays: Bool {
        get { self[DatePickerDistinguishesPastDaysKey.self] }
        set { self[DatePickerDistinguishesPastDaysKey.self] = newValue }
    }
}

extension View {
    /// Draws the weekend's days, in every `.graphical` date picker in this
    /// view, in the secondary text colour: on by default. Which days are the
    /// weekend is the calendar's locale's answer (`Calendar.isDateInWeekend`),
    /// so Friday and Saturday where that is the weekend.
    ///
    /// TUI's own: SwiftUI's calendar draws every day alike.
    ///
    /// - Parameter distinguishes: Whether the weekend has a tone of its own.
    /// - Returns: A view whose calendars draw the weekend so, or do not.
    public func datePickerDistinguishesWeekends(_ distinguishes: Bool = true) -> some View {
        environment(\.datePickerDistinguishesWeekends, distinguishes)
    }

    /// Draws the days before today, in every `.graphical` date picker in this
    /// view, faint: still choosable, but plainly gone by — for a picker of
    /// something to come, an event or a booking. Off by default.
    ///
    /// ```swift
    /// DatePicker("Date", selection: $date, displayedComponents: .date)
    ///     .datePickerStyle(.graphical)
    ///     .datePickerDistinguishesPastDays()
    /// ```
    ///
    /// TUI's own: SwiftUI's calendar draws every day alike. A day that may not
    /// be chosen at all belongs out of the picker's range instead, which dims
    /// it further.
    ///
    /// - Parameter distinguishes: Whether past days are drawn faint.
    /// - Returns: A view whose calendars draw past days so, or do not.
    public func datePickerDistinguishesPastDays(_ distinguishes: Bool = true) -> some View {
        environment(\.datePickerDistinguishesPastDays, distinguishes)
    }
}
