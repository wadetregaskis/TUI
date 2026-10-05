//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyle+Timer.swift
//
//  `SystemFormatStyle.Timer` and `.timer(countingDownIn:…)` /
//  `.timer(countingUpIn:…)`: a timer running through an interval.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@available(macOS 15, *)
extension SystemFormatStyle {
    /// The system timer format style — mirrors SwiftUI's
    /// `SystemFormatStyle.Timer`.
    ///
    /// Formats a date — usually now — as the time left in an interval
    /// (counting down) or gone (counting up): `1:02:05`, `2:05`, `0:00`.
    /// Counting down rounds up to the precision, so the timer reads `0:01`
    /// until the very end; counting up rounds down. Before the interval it
    /// reads its start, after it its end.
    ///
    /// A reading the face cannot hold in `maxFieldCount` fields is spelt in
    /// units, truncated (`1 hour, 2 minutes`), and so is any reading at a
    /// precision coarser than a second, without its seconds (`27 hours,
    /// 46 minutes`) — SwiftUI's behaviour, measured on macOS 15.
    public struct Timer: DiscreteFormatStyle, Codable, Hashable, Sendable {
        /// The type of data to format.
        public typealias FormatInput = Date

        /// The type of the formatted data.
        public typealias FormatOutput = AttributedString

        let interval: Range<Date>
        let countsDown: Bool
        let showsHours: Bool
        let maxFieldCount: Int
        let maxPrecision: Duration
        var locale: Locale = .autoupdatingCurrent

        /// Create a timer format style that counts down from the given
        /// interval.
        ///
        /// - Parameters:
        ///   - interval: The interval during which the timer counts down.
        ///   - showsHours: If true, the timer shows the hours as a separate
        ///     element once the duration is at least one hour. If false, the
        ///     minutes run past sixty.
        ///   - maxFieldCount: The number of fields that can be shown at once:
        ///     1 hour, 34 minutes is `1:34:00` by default and `1 hour,
        ///     34 minutes` with two.
        ///   - maxPrecision: The precision the input is formatted at. Seconds by
        ///     default; `.milliseconds(10)` shows hundredths, and `.seconds(60)`
        ///     only hours and minutes.
        public init(
            countingDownIn interval: Range<Date>, showsHours: Bool = true, maxFieldCount: Int = 3,
            maxPrecision: Duration = .seconds(1)
        ) {
            self.interval = interval
            self.countsDown = true
            self.showsHours = showsHours
            self.maxFieldCount = maxFieldCount
            self.maxPrecision = maxPrecision
        }

        /// Create a timer format style that counts up to the given interval.
        ///
        /// - Parameters:
        ///   - interval: The interval during which the timer counts up.
        ///   - showsHours: If true, the timer shows the hours as a separate
        ///     element once the duration is at least one hour. If false, the
        ///     minutes run past sixty.
        ///   - maxFieldCount: The number of fields that can be shown at once.
        ///   - maxPrecision: The precision the input is formatted at.
        public init(
            countingUpIn interval: Range<Date>, showsHours: Bool = true, maxFieldCount: Int = 3,
            maxPrecision: Duration = .seconds(1)
        ) {
            self.interval = interval
            self.countsDown = false
            self.showsHours = showsHours
            self.maxFieldCount = maxFieldCount
            self.maxPrecision = maxPrecision
        }

        private var face: ClockFace {
            ClockFace(
                showsHours: showsHours, maxFieldCount: maxFieldCount, precision: maxPrecision, padsLeading: false)
        }

        /// The interval's length, in seconds.
        private var length: Double { max(0, interval.upperBound.timeIntervalSince(interval.lowerBound)) }

        /// The seconds the timer reads at `input`, before rounding.
        private func value(at input: Date) -> Double {
            let gone = min(length, max(0, input.timeIntervalSince(interval.lowerBound)))
            return countsDown ? length - gone : gone
        }

        /// The instant the timer reads `value`.
        private func instant(reading value: Double) -> Date {
            interval.lowerBound.addingTimeInterval(countsDown ? length - value : value)
        }

        /// Creates a `FormatOutput` instance from `value`.
        public func format(_ input: Date) -> AttributedString {
            AttributedString(face.text(for: value(at: input), roundsUp: countsDown, locale: locale))
        }

        /// This style in `locale`, which spells the units a reading falls back
        /// to.
        public func locale(_ locale: Locale) -> Self {
            var copy = self
            copy.locale = locale
            return copy
        }

        /// The next discretization boundary after the given input: the first
        /// instant the timer reads differently, or `nil` once it never will.
        public func discreteInput(after input: Date) -> Date? {
            guard
                let boundary = face.next(
                    after: value(at: input), increasing: !countsDown, roundsUp: countsDown, limit: length)
            else { return nil }
            return max(input.justAfter, SystemFormatStyle.instant(of: boundary, at: instant(reading:), forward: true))
        }

        /// The next discretization boundary before the given input: the last
        /// instant before it at which the timer read differently.
        public func discreteInput(before input: Date) -> Date? {
            guard
                let boundary = face.next(
                    after: value(at: input), increasing: countsDown, roundsUp: countsDown, limit: length)
            else { return nil }
            return min(input.justBefore, SystemFormatStyle.instant(of: boundary, at: instant(reading:), forward: false))
        }
    }
}

@available(macOS 15, *)
extension FormatStyle where Self == SystemFormatStyle.Timer {
    /// Create a timer format style that counts down in the given interval —
    /// mirrors SwiftUI's `.timer(countingDownIn:…)`.
    ///
    /// ```swift
    /// Text(.currentDate, format: .timer(countingDownIn: start..<end))
    /// ```
    ///
    /// See ``SystemFormatStyle/Timer`` for the readings.
    ///
    /// - Parameters:
    ///   - interval: The interval during which the timer counts down.
    ///   - showsHours: Whether the hours are a field of their own from an hour.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - maxPrecision: The precision the input is formatted at.
    public static func timer(
        countingDownIn interval: Range<Date>, showsHours: Bool = true, maxFieldCount: Int = 3,
        maxPrecision: Duration = .seconds(1)
    ) -> SystemFormatStyle.Timer {
        SystemFormatStyle.Timer(
            countingDownIn: interval, showsHours: showsHours, maxFieldCount: maxFieldCount, maxPrecision: maxPrecision)
    }

    /// Create a timer format style that counts up in the given interval —
    /// mirrors SwiftUI's `.timer(countingUpIn:…)`.
    ///
    /// - Parameters:
    ///   - interval: The interval during which the timer counts up.
    ///   - showsHours: Whether the hours are a field of their own from an hour.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - maxPrecision: The precision the input is formatted at.
    public static func timer(
        countingUpIn interval: Range<Date>, showsHours: Bool = true, maxFieldCount: Int = 3,
        maxPrecision: Duration = .seconds(1)
    ) -> SystemFormatStyle.Timer {
        SystemFormatStyle.Timer(
            countingUpIn: interval, showsHours: showsHours, maxFieldCount: maxFieldCount, maxPrecision: maxPrecision)
    }
}

@available(macOS 15, *)
extension SystemFormatStyle.Timer: DateSizeVariantFormatStyle {
    func sizeVariants(of input: Date, locale: Locale) -> [String] {
        face.sizeVariants(for: value(at: input), roundsUp: countsDown, locale: locale)
    }
}
