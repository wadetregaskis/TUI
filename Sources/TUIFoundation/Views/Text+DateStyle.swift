//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+DateStyle.swift
//
//  `Text(_:style:)` and `Text(timerInterval:pauseTime:countsDown:showsHours:)`:
//  a date shown as a time, a day, a span from now or a running timer, kept up
//  to date as the clock moves.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - DateStyle

@MainActor extension Text {
    /// A predefined style used to display a `Date` — mirrors SwiftUI's
    /// `Text.DateStyle`.
    ///
    /// Every string below was measured on SwiftUI (macOS 15, `en_US`) and is
    /// pinned in `TextDateStyleTests`.
    public struct DateStyle: Sendable, Hashable, Codable {
        /// Which style this is. Encoded as SwiftUI encodes it, `{"storage":2}`
        /// for `.relative`.
        enum Storage: Int, Sendable, Hashable, Codable {
            case time
            case date
            case relative
            case offset
            case timer
        }

        let storage: Storage

        /// A style displaying only the time component for a date: `11:23 PM`.
        public static let time = Self(storage: .time)

        /// A style displaying a date: `June 3, 2019`.
        public static let date = Self(storage: .date)

        /// A style displaying a date as relative to now: `2 hr, 23 min`,
        /// `1 yr, 1 mth`.
        ///
        /// The span between the date and now, in abbreviated units, two at
        /// most and truncated, the same either side of now: `2 min, 5 sec`
        /// two minutes and five seconds ago and two minutes and five seconds
        /// ahead. Under a day the second unit shows even at zero
        /// (`1 hr, 0 min`); from a day up a zero is left out (`1 day`).
        public static let relative = Self(storage: .relative)

        /// A style displaying a date as offset from now: `+2 hours`,
        /// `−3 months`.
        ///
        /// One unit, truncated, signed `+` for a date that has passed and
        /// `−` (U+2212) for one ahead — `−0 seconds` in the last second
        /// before it.
        public static let offset = Self(storage: .offset)

        /// A style displaying a date as a timer counting from now: `2:32`,
        /// `36:59:01`.
        ///
        /// The whole seconds between the date and now on a clock face, the
        /// hours as many as it takes; it counts down to a date ahead and up
        /// from one passed.
        public static let timer = Self(storage: .timer)
    }

    /// Creates an instance that displays localized dates and times using a
    /// specific style — mirrors SwiftUI's `init(_:style:)`.
    ///
    /// ```swift
    /// Text(event.startDate, style: .relative)   // "2 hr, 23 min"
    /// ```
    ///
    /// The text is formatted when it is drawn, in the environment's
    /// `\.locale`, `\.calendar` and `\.timeZone`. The three styles that
    /// count from now — `.relative`, `.offset` and `.timer` — redraw as the
    /// clock moves: each asks the run loop for a frame at the instant its words
    /// next change (once a second for `2 min, 5 sec`, once a minute for
    /// `1 hr, 2 min`) and for nothing in between. `.time` and `.date` never
    /// change, and ask for nothing.
    ///
    /// - Parameters:
    ///   - date: The target date to display.
    ///   - style: The style used when displaying a date.
    nonisolated public init(_ date: Date, style: DateStyle) {
        self.init(live: DateStyleSource(date: date, style: style))
    }
}

// MARK: - Sources

/// `Text(date, style:)`'s words at each instant.
struct DateStyleSource: LiveTextSource, Equatable {
    let date: Date
    let style: Text.DateStyle

    /// `.relative`'s units: no weeks, two fields, abbreviated.
    private static let relative = TimeSpanSpelling(
        units: [.year, .month, .day, .hour, .minute, .second], maxFieldCount: 2)

    /// `.offset`'s: no weeks, one field, wide.
    private static let offset = TimeSpanSpelling(
        units: [.year, .month, .day, .hour, .minute, .second], maxFieldCount: 1)

    func text(at now: Date, in environment: LiveTextEnvironment) -> String {
        switch style.storage {
        case .time:
            return formatted(date: .none, time: .short, in: environment)
        case .date:
            return formatted(date: .long, time: .none, in: environment)
        case .relative:
            let counted = Self.relative.counted(
                from: min(date, now), to: max(date, now), calendar: environment.calendar)
            return TimeSpan.unitList(
                Self.relative.shown(counted), width: .abbreviated, locale: environment.locale,
                calendar: environment.calendar)
        case .offset:
            let counted = Self.offset.counted(
                from: min(date, now), to: max(date, now), calendar: environment.calendar)
            let units = TimeSpan.unitList(
                counted, width: .wide, locale: environment.locale, calendar: environment.calendar)
            return (now < date ? "\u{2212}" : "+") + units
        case .timer:
            return TimeSpan.clock(seconds: Int(abs(now.timeIntervalSince(date))), showsHours: true)
        }
    }

    /// The narrower spellings a `.sizeDependent` text steps down (measured on
    /// macOS 15): `.relative` `1 hr, 2 min` → `1h 2m`; `.offset` `+1 hour` →
    /// `+1 hr` → `+1h`; `.date` `May 8, 2026` → `May 2026` → `2026`; `.time`
    /// `11:13 PM` → `11 PM`. A timer's face has none.
    func sizeVariants(at now: Date, in environment: LiveTextEnvironment) -> [String] {
        let widest = text(at: now, in: environment)
        let style = Date.FormatStyle(
            locale: environment.locale, calendar: environment.calendar, timeZone: environment.calendar.timeZone)
        switch self.style.storage {
        case .timer:
            return [widest]
        case .time:
            return [widest, style.hour().format(date)]
        case .date:
            return [widest, style.month(.abbreviated).year().format(date), style.year().format(date)]
        case .relative:
            let counted = Self.relative.counted(
                from: min(date, now), to: max(date, now), calendar: environment.calendar)
            return [
                widest,
                TimeSpan.unitList(
                    Self.relative.shown(counted), width: .narrow, locale: environment.locale,
                    calendar: environment.calendar),
            ]
        case .offset:
            let counted = Self.offset.counted(
                from: min(date, now), to: max(date, now), calendar: environment.calendar)
            let sign = now < date ? "\u{2212}" : "+"
            return [widest] + [TimeSpanWidth.abbreviated, .narrow].map {
                sign + TimeSpan.unitList(counted, width: $0, locale: environment.locale, calendar: environment.calendar)
            }
        }
    }

    /// The date in one of the locale's own date and time styles.
    ///
    /// A `DateFormatter`, not `Date.FormatStyle`: the two disagree on the
    /// short time, and SwiftUI's `.time` is the formatter's — `06:13` in
    /// German, where `.shortened` gives `6:13` (measured on macOS 15). It costs
    /// about 30 µs a read against the style's one, and only `.time` and `.date`
    /// read it — once a frame they are drawn, never on a wake of their own.
    private func formatted(
        date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style,
        in environment: LiveTextEnvironment
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = environment.locale
        formatter.calendar = environment.calendar
        formatter.timeZone = environment.calendar.timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    func nextChange(after now: Date, in environment: LiveTextEnvironment) -> Date? {
        let spelling: TimeSpanSpelling
        switch style.storage {
        case .time, .date:
            return nil
        case .relative:
            spelling = Self.relative
        case .offset:
            spelling = Self.offset
        case .timer:
            spelling = TimeSpanSpelling(units: [.second], maxFieldCount: 1)
        }
        let counted = spelling.counted(from: min(date, now), to: max(date, now), calendar: environment.calendar)
        return TimeSpan.nextChange(
            counted: counted, from: date, now: now, calendar: environment.calendar,
            signFlips: style == .offset)
    }
}
