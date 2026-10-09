//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimeSpan.swift
//
//  Spelling a span of time the way SwiftUI's live text spells it — as calendar
//  fields ("1 yr, 3 mths", "2 minutes, 5 seconds") or on a clock face
//  ("1:02:05", "00:05.25") — and finding the instant a spelling next changes.
//  Shared by `Text(_:style:)`, `Text(timerInterval:…)` and `SystemFormatStyle`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Units and fields

/// A unit a span of time is spelt in, most significant first.
package enum TimeSpanUnit: Int, Comparable, CaseIterable, Sendable {
    case year
    case month
    case week
    case day
    case hour
    case minute
    case second

    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The calendar component that counts this unit between two dates.
    var component: Calendar.Component {
        switch self {
        case .year: .year
        case .month: .month
        case .week: .weekOfYear
        case .day: .day
        case .hour: .hour
        case .minute: .minute
        case .second: .second
        }
    }

    /// Its length in seconds, for the units a `Duration` can hold; `nil` for
    /// the two whose length depends on where they fall.
    var seconds: Int64? {
        switch self {
        case .year, .month: nil
        case .week: 604_800
        case .day: 86_400
        case .hour: 3_600
        case .minute: 60
        case .second: 1
        }
    }

    /// The same unit in `Duration.UnitsFormatStyle`'s vocabulary.
    var durationUnit: Duration.UnitsFormatStyle.Unit? {
        switch self {
        case .year, .month: nil
        case .week: .weeks
        case .day: .days
        case .hour: .hours
        case .minute: .minutes
        case .second: .seconds
        }
    }
}

/// How wide a unit's name is spelt: "1 hour, 2 minutes", "1 hr, 2 min",
/// "1 hr 2 min" or "1h 2m" — `Duration.UnitsFormatStyle`'s widths, and the
/// rungs a `.sizeDependent` text steps down (decisions A32).
package enum TimeSpanWidth: Sendable {
    case wide
    case abbreviated
    case condensedAbbreviated
    case narrow

    /// The same width, as `Duration.UnitsFormatStyle` names it.
    var durationWidth: Duration.UnitsFormatStyle.UnitWidth {
        switch self {
        case .wide: .wide
        case .abbreviated: .abbreviated
        case .condensedAbbreviated: .condensedAbbreviated
        case .narrow: .narrow
        }
    }
}

/// One field of a spelt span: a unit and how many whole ones.
package struct TimeSpanField: Equatable, Sendable {
    let unit: TimeSpanUnit
    let value: Int
}

// MARK: - Calendar spellings

/// The rules SwiftUI's unit spellings follow, measured on macOS 15 (see
/// `SwiftUI-API-completion-decisions-W11a.md`):
///
/// - The span is counted in whole units of `units`, **truncated**, by the
///   calendar: "1 hr, 2 min" until the third minute is complete.
/// - It starts at the most significant unit that is not zero, and shows up to
///   `maxFieldCount` consecutive units from there.
/// - Under a day (nothing above hours counted), a zero after the first field is
///   shown — "1 minute, 0 seconds", "1 hr, 0 min". From a day up it is left out
///   — "1 day", not "1 day, 0 hours". A span of nothing is "0" of the finest
///   unit: "0 seconds".
package struct TimeSpanSpelling: Equatable, Sendable {
    /// The units the span may be counted in, most significant first.
    let units: [TimeSpanUnit]

    /// How many consecutive units are shown at most.
    let maxFieldCount: Int

    /// `units` is an array, not `some Collection`: TUIkitFoundation calls this
    /// from another module, where a generic initializer runs unspecialised
    /// (CONTRIBUTING.md, "Crossing a module boundary"), and every caller has an
    /// array already.
    package init(units: [TimeSpanUnit], maxFieldCount: Int) {
        self.units = units.sorted()
        self.maxFieldCount = max(1, maxFieldCount)
    }

    /// The fields the span between `earlier` and `later` is counted in, before
    /// any zero is dropped: the first non-zero unit and the units after it, up
    /// to ``maxFieldCount``. The finest of them is what the spelling changes
    /// with, which is why a zero that will not be shown still counts here.
    package func counted(from earlier: Date, to later: Date, calendar: Calendar) -> [TimeSpanField] {
        guard let finest = units.last else { return [] }
        let components = calendar.dateComponents(Set(units.map(\.component)), from: earlier, to: later)
        let values = units.map { abs(components.value(for: $0.component) ?? 0) }
        guard let first = values.firstIndex(where: { $0 != 0 }) else {
            return [TimeSpanField(unit: finest, value: 0)]
        }
        let end = min(units.count, first + maxFieldCount)
        return (first..<end).map { TimeSpanField(unit: units[$0], value: values[$0]) }
    }

    /// The fields that are shown, from those ``counted(from:to:calendar:)``
    /// returned: every one under a day, the non-zero ones from a day up.
    package func shown(_ counted: [TimeSpanField]) -> [TimeSpanField] {
        guard let first = counted.first, first.unit < .hour else { return counted }
        let nonZero = counted.filter { $0.value != 0 }
        return nonZero.isEmpty ? [first] : nonZero
    }
}

// MARK: - Spelling fields

package enum TimeSpan {
    /// `fields` spelt as a list of units in `locale`: "1 hour, 2 minutes",
    /// "1 Std., 2 Min.".
    ///
    /// Spans under a month go through `Duration.UnitsFormatStyle`, which is
    /// localised, pluralised and list-joined on every platform. Years and
    /// months have no `Duration` unit; Apple's Foundation spells them with
    /// `Date.ComponentsFormatStyle`, and the open-source Foundation, which
    /// declares that type without a way to build one, with the framework's
    /// own tables (``tableUnitList(_:width:locale:)``).
    package static func unitList(
        _ fields: [TimeSpanField], width: TimeSpanWidth, locale: Locale, calendar: Calendar
    ) -> String {
        guard !fields.isEmpty else { return "" }
        let durationUnits = fields.compactMap(\.unit.durationUnit)
        if durationUnits.count == fields.count {
            let seconds = fields.reduce(Int64(0)) { $0 + Int64($1.value) * ($1.unit.seconds ?? 0) }
            let style = Duration.UnitsFormatStyle(
                allowedUnits: Set(durationUnits),
                width: width.durationWidth,
                maximumUnitCount: fields.count,
                zeroValueUnits: .show(length: 1),
                valueLength: nil,
                fractionalPart: .hide)
            return Duration.seconds(seconds).formatted(style.locale(locale))
        }
        return calendarUnitList(fields, width: width, locale: locale, calendar: calendar)
    }

    #if canImport(FoundationEssentials)
        /// A span with years or months, from the framework's own tables —
        /// because the open-source Foundation cannot spell one.
        ///
        /// **A gap in swift-corelibs-foundation, worth knowing before touching
        /// this:** the open-source Foundation (swift-foundation, which
        /// swift-corelibs-foundation re-exports on Linux, Windows and WASI)
        /// DECLARES `Date.ComponentsFormatStyle` — its `Field` type exists, so
        /// `Set<Date.ComponentsFormatStyle.Field>` compiles everywhere, and
        /// `SystemFormatStyle.DateOffset` takes one — but declares it without
        /// any initialiser and without `Date.formatted(_:)` support for it, so
        /// there is no way to build one and spell a span with it. Nothing else
        /// there spells years and months either: `Duration` has no such units,
        /// their length depending on where they fall. So on every platform
        /// whose Foundation is the open-source one, the year and month names
        /// come from TUIkit's translation tables, in its seven languages, and
        /// everything finer, and the joining, from `Duration.UnitsFormatStyle`,
        /// which is localised there. Measured equal to Apple's
        /// `Date.ComponentsFormatStyle` in all seven (`TimeSpanTableTests`).
        /// Revisit if swift-foundation gains the initialiser: the `#else`
        /// below is the whole implementation it would need.
        private static func calendarUnitList(
            _ fields: [TimeSpanField], width: TimeSpanWidth, locale: Locale, calendar: Calendar
        ) -> String {
            tableUnitList(fields, width: width, locale: locale)
        }
    #else
        /// A span with years or months, through `Date.ComponentsFormatStyle`.
        ///
        /// The style counts a range itself, so it is handed one that holds
        /// exactly `fields`: it ends on the first day of a 31-day month (the
        /// one the calendar's reference date falls in) with the years and
        /// months before it, and the finer fields after it — which, being under
        /// a month's worth, cannot carry into another month.
        private static func calendarUnitList(
            _ fields: [TimeSpanField], width: TimeSpanWidth, locale: Locale, calendar: Calendar
        ) -> String {
            let pivot =
                calendar.dateInterval(of: .month, for: Date(timeIntervalSinceReferenceDate: 0))?.start
                ?? Date(timeIntervalSinceReferenceDate: 0)
            let coarse = fields.filter { $0.unit <= .month }
            let fine = fields.filter { $0.unit > .month }
            guard let start = calendar.date(byAdding: components(coarse, sign: -1), to: pivot),
                let end = calendar.date(byAdding: components(fine, sign: 1), to: pivot)
            else { return "" }
            let componentsWidth: Date.ComponentsFormatStyle.Style =
                switch width {
                case .wide: .wide
                case .abbreviated: .abbreviated
                case .condensedAbbreviated: .condensedAbbreviated
                case .narrow: .narrow
                }
            let style = Date.ComponentsFormatStyle(
                style: componentsWidth, locale: locale, calendar: calendar,
                fields: Set(fields.map(\.unit.componentsField)))
            return style.format(start..<end)
        }
    #endif

    /// `fields` as date components, each multiplied by `sign`.
    static func components(_ fields: [TimeSpanField], sign: Int) -> DateComponents {
        var components = DateComponents()
        for field in fields {
            components.setValue(sign * field.value, for: field.unit.component)
        }
        return components
    }

    // MARK: Clock faces

    /// Whole seconds on a clock face: `m:ss`, or `h:mm:ss` from an hour when
    /// `showsHours` (otherwise the minutes run past 59: `62:05`).
    ///
    /// - Parameter padsLeading: Whether the leading field takes two digits, as
    ///   a stopwatch's does (`00:05`, `01:02:05`) and a timer's does not.
    package static func clock(seconds: Int, showsHours: Bool, padsLeading: Bool = false) -> String {
        let total = max(0, seconds)
        let hours = showsHours ? total / 3_600 : 0
        let minutes = showsHours ? total / 60 % 60 : total / 60
        let secs = total % 60
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        guard hours > 0 else { return "\(padsLeading ? two(minutes) : "\(minutes)"):\(two(secs))" }
        return "\(padsLeading ? two(hours) : "\(hours)"):\(two(minutes)):\(two(secs))"
    }

    // MARK: When a spelling changes

    /// The first instant after `now` at which a truncated spelling of the span
    /// between `date` and `now` changes, given the fields it was `counted` in.
    ///
    /// - A growing span (`date` is past) changes when its finest counted field
    ///   gains one: at `date` plus the counted fields with the finest one more.
    /// - A shrinking span (`date` is ahead) changes the moment it falls short
    ///   of what was counted: just after `date` minus the counted fields. A
    ///   span already down to nothing changes at `date` itself when the
    ///   spelling has a sign (`signFlips`), and one finest unit after it when
    ///   it does not, since it reads the same either side.
    ///
    /// Calendar arithmetic does not always invert (31 January plus a month is
    /// 28 February), so a boundary that lands at or before `now` is replaced by
    /// a second from now: a spare frame rather than a text that never moves.
    package static func nextChange(
        counted: [TimeSpanField], from date: Date, now: Date, calendar: Calendar, signFlips: Bool
    ) -> Date {
        guard let finest = counted.last else { return now.addingTimeInterval(1) }
        var candidate: Date?
        if now >= date {
            var grown = counted
            grown[grown.count - 1] = TimeSpanField(unit: finest.unit, value: finest.value + 1)
            candidate = calendar.date(byAdding: components(grown, sign: 1), to: date)
        } else if counted.allSatisfy({ $0.value == 0 }) {
            candidate =
                signFlips
                ? date : calendar.date(byAdding: components([TimeSpanField(unit: finest.unit, value: 1)], sign: 1), to: date)
        } else {
            candidate = calendar.date(byAdding: components(counted, sign: -1), to: date).map(\.justAfter)
        }
        guard let candidate, candidate > now else { return now.addingTimeInterval(1) }
        return candidate
    }

    /// The last instant before `now` at which the spelling read differently —
    /// ``nextChange(counted:from:now:calendar:signFlips:)`` run backwards.
    ///
    /// - Going back, a growing span shrinks: it read less just before `date`
    ///   plus what was counted. One down to nothing reads differently just
    ///   before `date` when it is signed, and at one finest unit before it
    ///   when it is not.
    /// - A shrinking span grows going back: it read more from `date` minus the
    ///   counted fields with the finest one more.
    static func previousChange(
        counted: [TimeSpanField], from date: Date, now: Date, calendar: Calendar, signFlips: Bool
    ) -> Date {
        guard let finest = counted.last else { return now.justBefore }
        var candidate: Date?
        if now >= date {
            if counted.allSatisfy({ $0.value == 0 }) {
                let unit = [TimeSpanField(unit: finest.unit, value: 1)]
                candidate = signFlips ? date.justBefore : calendar.date(byAdding: components(unit, sign: -1), to: date)
            } else {
                candidate = calendar.date(byAdding: components(counted, sign: 1), to: date).map(\.justBefore)
            }
        } else {
            var grown = counted
            grown[grown.count - 1] = TimeSpanField(unit: finest.unit, value: finest.value + 1)
            candidate = calendar.date(byAdding: components(grown, sign: -1), to: date)
        }
        guard let candidate, candidate < now else { return now.justBefore }
        return candidate
    }
}

extension TimeSpanUnit {
    /// The same unit in `Date.ComponentsFormatStyle`'s vocabulary.
    var componentsField: Date.ComponentsFormatStyle.Field {
        switch self {
        case .year: .year
        case .month: .month
        case .week: .week
        case .day: .day
        case .hour: .hour
        case .minute: .minute
        case .second: .second
        }
    }
}

extension Date {
    /// The next instant a `Date` can hold after this one: where a spelling
    /// that holds AT a boundary and changes just past it changes.
    var justAfter: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.nextUp) }

    /// The last instant a `Date` can hold before this one.
    var justBefore: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.nextDown) }
}
