//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimeDataSource.swift
//
//  `TimeDataSource`: a value that is a function of the clock — now, the span
//  since or until a date, the offset to one — for `Text(_:format:)` to show
//  and keep up to date.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A source of time related data — mirrors SwiftUI's `TimeDataSource`.
///
/// Hand one to `Text(_:format:)` with a `DiscreteFormatStyle` and the text
/// shows the source's value at each frame,
/// asking the run loop for a frame only when the format's output changes:
///
/// ```swift
/// Text(.currentDate, format: .offset(to: startDate))
/// Text(.durationOffset(to: startDate), format: .time(pattern: .minuteSecond))
/// ```
@available(macOS 15, *)
public struct TimeDataSource<Value>: Sendable {
    /// Which source this is: what equality compares.
    enum Kind: Hashable, Sendable {
        case currentDate
        case dateRangeEnding(at: Date)
        case dateRangeStarting(at: Date)
        case durationOffset(to: Date)
    }

    let kind: Kind

    /// The value at an instant.
    let read: @Sendable (Date) -> Value

    /// The instant at which the source reads `value` — how a format's next
    /// input becomes the next instant to draw.
    let instant: @Sendable (Value) -> Date

    /// Whether the value grows as time passes (so the format's next input is
    /// the one `after` the current one) or shrinks.
    let risesWithTime: Bool
}

@available(macOS 15, *)
extension TimeDataSource where Value == Date {
    /// A time data source that produces `Date.now`.
    public static var currentDate: TimeDataSource<Date> {
        TimeDataSource(kind: .currentDate, read: { $0 }, instant: { $0 }, risesWithTime: true)
    }
}

@available(macOS 15, *)
extension TimeDataSource where Value == Range<Date> {
    /// A time data source that produces `min(date, Date.now)..<date`.
    ///
    /// - Parameter date: The end of the range.
    public static func dateRange(endingAt date: Date) -> TimeDataSource<Range<Date>> {
        TimeDataSource(
            kind: .dateRangeEnding(at: date), read: { min(date, $0)..<date },
            instant: { date.addingTimeInterval(-$0.upperBound.timeIntervalSince($0.lowerBound)) },
            risesWithTime: false)
    }

    /// A time data source that produces `date..<max(date, Date.now)`.
    ///
    /// - Parameter date: The start of the range.
    public static func dateRange(startingAt date: Date) -> TimeDataSource<Range<Date>> {
        TimeDataSource(
            kind: .dateRangeStarting(at: date), read: { date..<max(date, $0) },
            instant: { date.addingTimeInterval($0.upperBound.timeIntervalSince($0.lowerBound)) },
            risesWithTime: true)
    }
}

@available(macOS 15, *)
extension TimeDataSource where Value == Duration {
    /// A time data source that produces the offset between `Date.now` and the
    /// given `date` as a `Duration`: positive once `date` has passed.
    ///
    /// - Parameter date: The date the offset is measured from.
    public static func durationOffset(to date: Date) -> TimeDataSource<Duration> {
        TimeDataSource(
            kind: .durationOffset(to: date), read: { .seconds($0.timeIntervalSince(date)) },
            instant: { offset in
                let parts = offset.components
                return date.addingTimeInterval(Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
            },
            risesWithTime: true)
    }
}
