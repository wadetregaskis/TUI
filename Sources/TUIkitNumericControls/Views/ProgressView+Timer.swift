//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProgressView+Timer.swift
//
//  SwiftUI's date-relative progress view: a bar that follows a timer interval
//  as the clock passes through it, and the default label that reads out the
//  time left (or gone).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// What a ``ProgressView`` holds besides its fraction, in one byte.
struct ProgressFlags: OptionSet, Sendable {
    let rawValue: UInt8

    /// The fraction holds a value; without it the bar is indeterminate.
    static let determinate = Self(rawValue: 1 << 0)
    /// The bar follows a timer interval rather than a stored fraction.
    static let timer = Self(rawValue: 1 << 1)
    /// The timer counts down: the bar shows what is left of the interval.
    static let countsDown = Self(rawValue: 1 << 2)
}

/// One entry a second through a timer interval, then the interval's end, and
/// nothing after it.
///
/// A schedule starts its sequence at the entry a view should show (see
/// `TimelineView`): before the interval, its start; inside it, the last whole
/// second passed since the start; after it, its end — so a finished timer has
/// no entry after now and stops asking for frames.
struct TimerIntervalSchedule: TimelineSchedule, Sendable {
    /// The interval's bounds, as reference-date seconds.
    let start: Double
    let end: Double

    func entries(from startDate: Date, mode: Mode) -> Entries {
        let now = startDate.timeIntervalSinceReferenceDate
        let first = min(end, start + max(0, (now - start).rounded(.down)))
        return Entries(upcoming: first, end: end)
    }

    /// The whole seconds from the first entry, then the end.
    struct Entries: Sequence, IteratorProtocol, Sendable {
        var upcoming: Double?
        let end: Double

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            upcoming = current < end ? Swift.min(end, current + 1) : nil
            return Date(timeIntervalSinceReferenceDate: current)
        }
    }
}

/// The default type of the current value label when used by a date-relative
/// progress view: the time left in the interval, or the time gone when the
/// view counts up — `0:42`, `12:05`, `1:02:03`.
public struct DefaultDateProgressLabel: View {
    /// The interval's bounds, as reference-date seconds.
    let start: Double
    let end: Double

    /// Whether to show the time left rather than the time gone.
    let countsDown: Bool

    public var body: some View {
        TimelineView(TimerIntervalSchedule(start: start, end: end)) { timeline in
            Text(verbatim: Self.timerText(seconds: seconds(at: timeline.date)))
        }
    }

    /// The whole seconds left (counting down) or gone (counting up) at `date`.
    private func seconds(at date: Date) -> Int {
        let now = min(end, max(start, date.timeIntervalSinceReferenceDate))
        return Int((countsDown ? (end - now).rounded(.up) : (now - start).rounded(.down)))
    }

    /// `m:ss`, or `h:mm:ss` from an hour.
    static func timerText(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let secs = seconds % 60
        func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0
            ? "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
            : "\(minutes):\(twoDigits(secs))"
    }
}

// MARK: - Initialisers

extension ProgressView {
    /// A progress view following `timerInterval`, its other properties given.
    private init(
        timerInterval: ClosedRange<Date>, countsDown: Bool, label: Label?, currentValueLabel: CurrentValueLabel?
    ) {
        self.init(fractionCompleted: 0, style: .block, label: label, currentValueLabel: currentValueLabel)
        timerStart = timerInterval.lowerBound.timeIntervalSinceReferenceDate
        timerEnd = timerInterval.upperBound.timeIntervalSinceReferenceDate
        flags = countsDown ? [.determinate, .timer, .countsDown] : [.determinate, .timer]
    }

    /// Creates a progress view for showing continuous progress as time passes,
    /// with descriptive and current progress labels.
    ///
    /// The bar shows what is left of the interval when `countsDown`, and what
    /// has passed otherwise, moving once a second; it stops moving at the
    /// interval's end.
    ///
    /// - Parameters:
    ///   - timerInterval: The date range over which the view progresses.
    ///   - countsDown: Whether the view counts down rather than up. Default
    ///     `true`.
    ///   - label: A view that describes the purpose of the view.
    ///   - currentValueLabel: A view that describes the current value.
    public init(
        timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.init(
            timerInterval: timerInterval, countsDown: countsDown, label: label(),
            currentValueLabel: currentValueLabel())
    }
}

extension ProgressView where CurrentValueLabel == DefaultDateProgressLabel {
    /// Creates a progress view for showing continuous progress as time passes,
    /// with a descriptive label; the current value label reads out the time
    /// left, or gone.
    ///
    /// - Parameters:
    ///   - timerInterval: The date range over which the view progresses.
    ///   - countsDown: Whether the view counts down rather than up. Default
    ///     `true`.
    ///   - label: A view that describes the purpose of the view.
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ViewBuilder label: () -> Label) {
        self.init(
            timerInterval: timerInterval, countsDown: countsDown, label: label(),
            currentValueLabel: DefaultDateProgressLabel(
                start: timerInterval.lowerBound.timeIntervalSinceReferenceDate,
                end: timerInterval.upperBound.timeIntervalSinceReferenceDate,
                countsDown: countsDown))
    }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == DefaultDateProgressLabel {
    /// Creates a progress view for showing continuous progress as time passes;
    /// the current value label reads out the time left, or gone.
    ///
    /// ```swift
    /// ProgressView(timerInterval: start...end)
    /// ```
    ///
    /// - Parameters:
    ///   - timerInterval: The date range over which the view progresses.
    ///   - countsDown: Whether the view counts down rather than up. Default
    ///     `true`.
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true) {
        self.init(
            timerInterval: timerInterval, countsDown: countsDown, label: nil,
            currentValueLabel: DefaultDateProgressLabel(
                start: timerInterval.lowerBound.timeIntervalSinceReferenceDate,
                end: timerInterval.upperBound.timeIntervalSinceReferenceDate,
                countsDown: countsDown))
    }
}
