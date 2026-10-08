//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyle+Stopwatch.swift
//
//  `SystemFormatStyle.Stopwatch` and `.stopwatch(startingAt:…)`: a stopwatch
//  counting up from a date, to the hundredth.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@available(macOS 15, *)
extension SystemFormatStyle {
    /// The system stopwatch format style — mirrors SwiftUI's
    /// `SystemFormatStyle.Stopwatch`.
    ///
    /// Formats a date — usually now — as the time since `startDate`, its
    /// leading field two digits wide and hundredths after it: `00:05.25`,
    /// `01:02:05.25`. It reads `00:00.00` before the start, rounds down, and
    /// spells in units what its face cannot hold (`1 hour, 2 minutes` in two
    /// fields), as ``SystemFormatStyle/Timer`` does.
    ///
    /// Shown live (`Text(.currentDate, format: .stopwatch(startingAt:))`) it
    /// changes every hundredth of a second, and a terminal draws it at the
    /// frame rate: sixty frames a second, the fractional digits stepping by
    /// about two hundredths. A coarser `maxPrecision` costs fewer frames.
    public struct Stopwatch: DiscreteFormatStyle, Codable, Hashable, Sendable {
        /// The type of data to format.
        public typealias FormatInput = Date

        /// The type of the formatted data.
        public typealias FormatOutput = AttributedString

        let startDate: Date
        let showsHours: Bool
        let maxFieldCount: Int
        let maxPrecision: Duration
        var locale: Locale = .autoupdatingCurrent

        /// Create a stopwatch format style.
        ///
        /// - Parameters:
        ///   - startDate: The date at which the stopwatch starts counting.
        ///   - showsHours: If true, the stopwatch shows the hours as a separate
        ///     element once the duration is at least one hour. If false, the
        ///     minutes run past sixty.
        ///   - maxFieldCount: The number of fields that can be shown at once,
        ///     the fraction of a second among them: `01:02:05.25` takes four.
        ///   - maxPrecision: The precision the input is formatted at.
        ///     Hundredths by default; `.seconds(60)` shows only hours and
        ///     minutes.
        public init(
            startingAt startDate: Date, showsHours: Bool = true, maxFieldCount: Int = 4,
            maxPrecision: Duration = .milliseconds(10)
        ) {
            self.startDate = startDate
            self.showsHours = showsHours
            self.maxFieldCount = maxFieldCount
            self.maxPrecision = maxPrecision
        }

        package var face: ClockFace {
            ClockFace(showsHours: showsHours, maxFieldCount: maxFieldCount, precision: maxPrecision, padsLeading: true)
        }

        /// The seconds since the start at `input`, none before it.
        package func value(at input: Date) -> Double {
            max(0, input.timeIntervalSince(startDate))
        }

        /// Creates a `FormatOutput` instance from `value`.
        public func format(_ input: Date) -> AttributedString {
            AttributedString(face.text(for: value(at: input), roundsUp: false, locale: locale))
        }

        /// This style in `locale`, which spells the units a reading falls back
        /// to.
        public func locale(_ locale: Locale) -> Self {
            var copy = self
            copy.locale = locale
            return copy
        }

        /// The next discretization boundary after the given input.
        public func discreteInput(after input: Date) -> Date? {
            guard
                let boundary = face.next(
                    after: value(at: input), increasing: true, roundsUp: false, limit: .infinity)
            else { return nil }
            return max(
                input.justAfter,
                SystemFormatStyle.instant(of: boundary, at: { startDate.addingTimeInterval($0) }, forward: true))
        }

        /// The next discretization boundary before the given input.
        public func discreteInput(before input: Date) -> Date? {
            guard
                let boundary = face.next(
                    after: value(at: input), increasing: false, roundsUp: false, limit: .infinity)
            else { return nil }
            return min(
                input.justBefore,
                SystemFormatStyle.instant(of: boundary, at: { startDate.addingTimeInterval($0) }, forward: false))
        }
    }
}

@available(macOS 15, *)
extension FormatStyle where Self == SystemFormatStyle.Stopwatch {
    /// Create a stopwatch format style — mirrors SwiftUI's
    /// `.stopwatch(startingAt:…)`.
    ///
    /// ```swift
    /// Text(.currentDate, format: .stopwatch(startingAt: start))
    /// ```
    ///
    /// See ``SystemFormatStyle/Stopwatch`` for the readings.
    ///
    /// - Parameters:
    ///   - startDate: The date at which the stopwatch starts counting.
    ///   - showsHours: Whether the hours are a field of their own from an hour.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - maxPrecision: The precision the input is formatted at.
    public static func stopwatch(
        startingAt startDate: Date, showsHours: Bool = true, maxFieldCount: Int = 4,
        maxPrecision: Duration = .milliseconds(10)
    ) -> SystemFormatStyle.Stopwatch {
        SystemFormatStyle.Stopwatch(
            startingAt: startDate, showsHours: showsHours, maxFieldCount: maxFieldCount, maxPrecision: maxPrecision)
    }
}
