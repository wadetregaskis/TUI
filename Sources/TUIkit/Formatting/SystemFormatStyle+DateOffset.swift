//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyle+DateOffset.swift
//
//  `SystemFormatStyle.DateOffset` and `.offset(to:…)`: the signed span from a
//  date — `−2 minutes, 5 seconds`, `1 year, 3 months`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@available(macOS 15, *)
extension SystemFormatStyle {
    /// A system format to display the offset to a certain date — mirrors
    /// SwiftUI's `SystemFormatStyle.DateOffset`.
    ///
    /// Formats a date — usually now — as its offset from `anchor`: positive
    /// when the date is later, negative (`−`, U+2212) when it is earlier. The
    /// rules are SwiftUI's, measured on macOS 15 and pinned in
    /// `SystemFormatStyleDateTests`:
    ///
    /// - Up to `maxFieldCount` units from the most significant that is not
    ///   zero, truncated: `1 hour, 2 minutes` until the third minute is done.
    /// - Under a day a zero after the first unit shows (`1 minute, 0 seconds`);
    ///   from a day up it does not (`1 day`). Months and years are the
    ///   calendar's.
    /// - Allowed only minutes and seconds, the offset is on a clock face:
    ///   `2:05`, `62:05`, `−2:05`.
    /// - A date in the second before the anchor reads `−0 seconds`.
    public struct DateOffset: DiscreteFormatStyle, Codable, Hashable, Sendable {
        /// The type of data to format.
        public typealias FormatInput = Date

        /// The type of the formatted data.
        public typealias FormatOutput = AttributedString

        let anchor: Date
        let allowedFields: Set<Date.ComponentsFormatStyle.Field>
        let maxFieldCount: Int
        let sign: NumberFormatStyleConfiguration.SignDisplayStrategy
        var locale: Locale = .autoupdatingCurrent
        var calendar: Calendar = .autoupdatingCurrent

        /// Create a format style to display the offset to a certain date.
        ///
        /// - Parameters:
        ///   - anchor: The date the offset is measured to from the format
        ///     input.
        ///   - allowedFields: The units of time that may be used to express the
        ///     offset.
        ///   - maxFieldCount: The number of fields that can be shown at once:
        ///     1 hour, 34 minutes and 23 seconds is `1 hour, 34 minutes` by
        ///     default and `1 hour` with one.
        ///   - sign: Whether the offset is signed: by default only a negative
        ///     one is.
        public init(
            to anchor: Date,
            allowedFields: Set<Date.ComponentsFormatStyle.Field> = [.year, .month, .week, .day, .hour, .minute, .second],
            maxFieldCount: Int = 2, sign: NumberFormatStyleConfiguration.SignDisplayStrategy = .automatic
        ) {
            self.anchor = anchor
            self.allowedFields = allowedFields
            self.maxFieldCount = maxFieldCount
            self.sign = sign
        }

        /// The allowed fields as span units, most significant first.
        private var units: [TimeSpanUnit] {
            let units = TimeSpanUnit.allCases.filter { allowedFields.contains($0.componentsField) }
            return units.isEmpty ? [.second] : units
        }

        /// Whether the offset is on a clock face: only minutes and seconds.
        private var isClockFace: Bool { units == [.minute, .second] }

        private var spelling: TimeSpanSpelling {
            TimeSpanSpelling(units: units, maxFieldCount: isClockFace ? 2 : maxFieldCount)
        }

        /// The fields the offset of `input` is counted in. On the clock face
        /// both are counted, a leading zero minute too.
        private func counted(_ input: Date) -> [TimeSpanField] {
            let earlier = min(input, anchor)
            let later = max(input, anchor)
            guard isClockFace else { return spelling.counted(from: earlier, to: later, calendar: calendar) }
            let components = calendar.dateComponents([.minute, .second], from: earlier, to: later)
            return [
                TimeSpanField(unit: .minute, value: abs(components.minute ?? 0)),
                TimeSpanField(unit: .second, value: abs(components.second ?? 0)),
            ]
        }

        /// The sign in front of the offset of `input`.
        private func signPrefix(_ input: Date) -> String {
            let offset = input.timeIntervalSince(anchor)
            if sign == .never { return "" }
            if offset < 0 { return "\u{2212}" }
            if sign == .automatic { return "" }
            return offset > 0 || sign == .always(includingZero: true) ? "+" : ""
        }

        /// Creates a `FormatOutput` instance from `value`.
        public func format(_ referenceDate: Date) -> AttributedString {
            let fields = counted(referenceDate)
            let body: String
            if isClockFace, let minutes = fields.first?.value, let seconds = fields.last?.value {
                body = "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
            } else {
                body = TimeSpan.unitList(spelling.shown(fields), width: .wide, locale: locale, calendar: calendar)
            }
            return AttributedString(signPrefix(referenceDate) + body)
        }

        /// This style in `locale`.
        public func locale(_ locale: Locale) -> Self {
            var copy = self
            copy.locale = locale
            return copy
        }

        /// This style counting months, days and years in `calendar`.
        public func calendar(_ calendar: Calendar) -> Self {
            var copy = self
            copy.calendar = calendar
            return copy
        }

        /// The next discretization boundary after the given input.
        public func discreteInput(after referenceDate: Date) -> Date? {
            TimeSpan.nextChange(
                counted: counted(referenceDate), from: anchor, now: referenceDate, calendar: calendar,
                signFlips: sign != .never)
        }

        /// The next discretization boundary before the given input.
        public func discreteInput(before referenceDate: Date) -> Date? {
            TimeSpan.previousChange(
                counted: counted(referenceDate), from: anchor, now: referenceDate, calendar: calendar,
                signFlips: sign != .never)
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
extension FormatStyle where Self == SystemFormatStyle.DateOffset {
    /// Create a format style to display the offset to a certain date —
    /// mirrors SwiftUI's `.offset(to:allowedFields:maxFieldCount:sign:)`.
    ///
    /// ```swift
    /// Text(.currentDate, format: .offset(to: deadline))
    /// ```
    ///
    /// See ``SystemFormatStyle/DateOffset`` for the readings. Unlike the
    /// initialiser's, this default does not count weeks, as SwiftUI's does not.
    ///
    /// - Parameters:
    ///   - anchor: The date the offset is measured to from the format input.
    ///   - allowedFields: The units of time that may be used.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - sign: Whether the offset is signed.
    public static func offset(
        to anchor: Date,
        allowedFields: Set<Date.ComponentsFormatStyle.Field> = [.year, .month, .day, .hour, .minute, .second],
        maxFieldCount: Int = 2, sign: NumberFormatStyleConfiguration.SignDisplayStrategy = .automatic
    ) -> SystemFormatStyle.DateOffset {
        SystemFormatStyle.DateOffset(to: anchor, allowedFields: allowedFields, maxFieldCount: maxFieldCount, sign: sign)
    }
}
