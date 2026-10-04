//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyle+DateReference.swift
//
//  `SystemFormatStyle.DateReference` and `.reference(to:…)`: a date referred to
//  the way people refer to one — "in 2 minutes", "yesterday", "Friday, May 8",
//  "May 2026".
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@available(macOS 15, *)
extension SystemFormatStyle {
    /// A system format style to refer to a date in the most natural way —
    /// mirrors SwiftUI's `SystemFormatStyle.DateReference`.
    ///
    /// Formats a point of reference — usually now — as a reference to `date`.
    /// Near it, relatively: `now`, `in 2 minutes`, `1 hour ago`, `yesterday`,
    /// `in 5 days`. Far from it, absolutely: `Friday, May 8` in the same
    /// year, `May 2026` in another. The rules are SwiftUI's, measured on
    /// macOS 15 and pinned in `SystemFormatStyleDateTests`:
    ///
    /// - The point of reference is taken to the nearest second, and the
    ///   relative form is Foundation's `Date.AnchoredRelativeFormatStyle`
    ///   (named, wide) in the allowed fields — rounding to the nearest unit,
    ///   days counted by the calendar — with `now` for anything under half the
    ///   finest allowed unit.
    /// - The form is relative while the largest unit it would use is no
    ///   larger than `thresholdField`: by default, until the two dates fall in
    ///   different months.
    /// - Absolutely, the date is spelt in `maxFieldCount` fields from the most
    ///   significant one that differs, with the weekday beside a day when the
    ///   year is not shown.
    public struct DateReference: DiscreteFormatStyle, Codable, Hashable, Sendable {
        /// The type of data to format.
        public typealias FormatInput = Date

        /// The type of the formatted data.
        public typealias FormatOutput = AttributedString

        let date: Date
        let allowedFields: Set<Date.RelativeFormatStyle.Field>
        let maxFieldCount: Int
        let thresholdField: Date.RelativeFormatStyle.Field
        var locale: Locale = .autoupdatingCurrent
        var calendar: Calendar = .autoupdatingCurrent

        /// Create a format style to refer to a date in the most natural way.
        ///
        /// - Parameters:
        ///   - date: The date this format references.
        ///   - allowedFields: The units of time that may be used to express the
        ///     reference. `thresholdField` is always allowed.
        ///   - maxFieldCount: The number of fields shown at once in the
        ///     absolute form: January 9, 2007 is `January 2007` by default and
        ///     `January 9, 2007` with three.
        ///   - thresholdField: The least precise field the relative form may
        ///     use before the absolute one takes over.
        public init(
            to date: Date, allowedFields: Set<Date.RelativeFormatStyle.Field> = [.year, .month, .day, .hour, .minute],
            maxFieldCount: Int = 2, thresholdField: Date.RelativeFormatStyle.Field = .day
        ) {
            self.date = date
            self.allowedFields = allowedFields
            self.maxFieldCount = maxFieldCount
            self.thresholdField = thresholdField
        }

        // MARK: Fields

        /// `field` as a span unit.
        private static func unit(_ field: Date.RelativeFormatStyle.Field) -> TimeSpanUnit {
            switch field {
            case .year: .year
            case .month: .month
            case .week: .week
            case .day: .day
            case .hour: .hour
            case .minute: .minute
            default: .second
            }
        }

        /// The units the relative form may use, most significant first.
        private var units: [TimeSpanUnit] {
            Set((allowedFields.map(Self.unit)) + [Self.unit(thresholdField)]).sorted()
        }

        /// The calendar's own fields, most significant first — the ones two
        /// dates are compared in.
        private static let calendarUnits: [TimeSpanUnit] = [.year, .month, .day, .hour, .minute, .second]

        /// The point of reference, to the nearest second from `date`.
        private func rounded(_ input: Date) -> Date {
            date.addingTimeInterval(input.timeIntervalSince(date).rounded(.toNearestOrAwayFromZero))
        }

        /// The most significant calendar field in which `input` and `date`
        /// differ, or `nil` when they agree to the second.
        private func firstDifference(_ input: Date) -> TimeSpanUnit? {
            Self.calendarUnits.first { calendar.component($0.component, from: input) != calendar.component($0.component, from: date) }
        }

        /// Whether `input` refers to the date relatively: the unit the relative
        /// form would count in is no larger than the threshold.
        private func isRelative(_ input: Date) -> Bool {
            guard let difference = firstDifference(rounded(input)) else { return true }
            // The relative form counts in the difference's own unit, or the
            // largest finer one it may use, or failing both its finest.
            let counted = units.first { $0 >= difference } ?? units.last ?? .second
            return counted >= Self.unit(thresholdField)
        }

        // MARK: Formatting

        private var relativeStyle: Date.AnchoredRelativeFormatStyle {
            var style = Date.AnchoredRelativeFormatStyle(
                anchor: date, presentation: .named, unitsStyle: .wide, locale: locale, calendar: calendar,
                capitalizationContext: .unknown)
            style.allowedFields = allowedFields.union([thresholdField])
            return style
        }

        /// The relative form, `now` where Foundation would say "this minute".
        private func relative(_ input: Date) -> String {
            // Counting seconds, Foundation says "now" itself; counting days
            // at finest, "today" stays.
            let finest = units.last ?? .second
            guard finest == .minute || finest == .hour else { return relativeStyle.format(input) }
            let half = Double(finest.seconds ?? 60) / 2
            guard abs(input.timeIntervalSince(date).rounded(.toNearestOrAwayFromZero)) < half else {
                return relativeStyle.format(input)
            }
            var now = relativeStyle
            now.allowedFields = [.second]
            return now.format(date)
        }

        /// The absolute form: `maxFieldCount` fields from the first that
        /// differs.
        private func absolute(_ input: Date) -> String {
            let fields: [TimeSpanUnit] = [.year, .month, .day, .hour, .minute]
            let first = fields.firstIndex(of: firstDifference(rounded(input)) ?? .minute) ?? fields.count - 1
            let shown = fields[first..<min(fields.count, first + max(1, maxFieldCount))]
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            if shown.contains(.year) { style = style.year() }
            if shown.contains(.month) { style = style.month(.wide) }
            if shown.contains(.day) {
                style = style.day()
                if !shown.contains(.year) { style = style.weekday(.wide) }
            }
            if shown.contains(.hour) { style = style.hour() }
            if shown.contains(.minute) { style = style.minute() }
            return style.format(date)
        }

        /// Creates a `FormatOutput` instance from `value`.
        public func format(_ referenceDate: Date) -> AttributedString {
            AttributedString(isRelative(referenceDate) ? relative(referenceDate) : absolute(referenceDate))
        }

        /// This style in `locale`.
        public func locale(_ locale: Locale) -> Self {
            var copy = self
            copy.locale = locale
            return copy
        }

        /// This style comparing and counting dates in `calendar`.
        public func calendar(_ calendar: Calendar) -> Self {
            var copy = self
            copy.calendar = calendar
            return copy
        }

        // MARK: Boundaries

        /// The instants either side of `input` at which the fields the two
        /// dates differ in can change, among those above the threshold — the
        /// only instants the form can turn between relative and absolute, or
        /// the absolute form change its fields.
        ///
        /// Those are the starts and ends of the date's own periods: its year,
        /// its month, and so on down to the threshold. The point of reference
        /// is rounded to the second from the date, so each turns half a second
        /// early.
        private func turns(around input: Date) -> (next: Date?, last: Date?) {
            let point = rounded(input)
            var next: Date?
            var last: Date?
            let coarse: [TimeSpanUnit] = [.year, .month, .day, .hour, .minute]
            for unit in coarse where unit < Self.unit(thresholdField) {
                guard let period = calendar.dateInterval(of: unit.component, for: date) else { continue }
                for boundary in [period.start, period.end] {
                    let turn = date.addingTimeInterval(boundary.timeIntervalSince(date).rounded(.up) - 0.5)
                    if boundary > point {
                        next = min(next ?? turn.justAfter, turn.justAfter)
                    } else {
                        last = max(last ?? turn.justBefore, turn.justBefore)
                    }
                }
            }
            return (next, last)
        }

        /// The next discretization boundary after the given input.
        public func discreteInput(after referenceDate: Date) -> Date? {
            let turn = turns(around: referenceDate).next.flatMap { $0 > referenceDate ? $0 : nil }
            guard isRelative(referenceDate), let change = relativeStyle.discreteInput(after: referenceDate) else {
                return turn
            }
            return min(change, turn ?? change)
        }

        /// The next discretization boundary before the given input.
        public func discreteInput(before referenceDate: Date) -> Date? {
            let turn = turns(around: referenceDate).last.flatMap { $0 < referenceDate ? $0 : nil }
            guard isRelative(referenceDate), let change = relativeStyle.discreteInput(before: referenceDate) else {
                return turn
            }
            return max(change, turn ?? change)
        }

        /// The next input value after the given input: the next instant a
        /// `Date` can hold.
        public func input(after referenceDate: Date) -> Date? {
            referenceDate.justAfter
        }

        /// The next input value before the given input.
        public func input(before referenceDate: Date) -> Date? {
            referenceDate.justBefore
        }
    }
}

@available(macOS 15, *)
extension FormatStyle where Self == SystemFormatStyle.DateReference {
    /// Create a format style to refer to a date in the most natural way —
    /// mirrors SwiftUI's `.reference(to:allowedFields:maxFieldCount:thresholdField:)`.
    ///
    /// ```swift
    /// Text(.currentDate, format: .reference(to: meeting))   // "in 5 minutes"
    /// ```
    ///
    /// See ``SystemFormatStyle/DateReference`` for the readings.
    ///
    /// - Parameters:
    ///   - date: The date this format references.
    ///   - allowedFields: The units of time that may be used.
    ///   - maxFieldCount: The number of fields shown at once in the absolute
    ///     form.
    ///   - thresholdField: The least precise field the relative form may use.
    public static func reference(
        to date: Date, allowedFields: Set<Date.RelativeFormatStyle.Field> = [.year, .month, .day, .hour, .minute],
        maxFieldCount: Int = 2, thresholdField: Date.RelativeFormatStyle.Field = .day
    ) -> SystemFormatStyle.DateReference {
        SystemFormatStyle.DateReference(
            to: date, allowedFields: allowedFields, maxFieldCount: maxFieldCount, thresholdField: thresholdField)
    }
}
