//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+TimerInterval.swift
//
//  `Text(timerInterval:pauseTime:countsDown:showsHours:)`: a timer running
//  through an interval, kept up to date a second at a time.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Text {
    /// Creates an instance that displays a timer counting within the provided
    /// interval — mirrors SwiftUI's
    /// `init(timerInterval:pauseTime:countsDown:showsHours:)`.
    ///
    /// ```swift
    /// Text(timerInterval: start...end)                     // "4:59", "4:58", …
    /// Text(timerInterval: start...end, countsDown: false)  // "0:01", "0:02", …
    /// ```
    ///
    /// Counting down, the text shows the time left, rounded up to the second
    /// (so it reads `0:01` until the very end); counting up, the time gone,
    /// rounded down. Before the interval it holds its starting value and after
    /// it its finishing one. It asks the run loop for a frame each second the
    /// reading changes, and for none once it can no longer change.
    ///
    /// `pauseTime` stops the timer where SwiftUI stops it, which counting
    /// down is not where one might guess. Counting up, the timer stops at the
    /// time gone at `pauseTime`. Counting down, it stops when what it SHOWS
    /// reaches `pauseTime − start` — SwiftUI's own documented example pauses a
    /// twelve-minute countdown whose pause time is ten minutes in "when
    /// reaching 10:00", and that is what it does (measured on macOS 15).
    ///
    /// - Parameters:
    ///   - timerInterval: The interval between where to run the timer.
    ///   - pauseTime: If present, the date at which to pause the timer. The
    ///     default is `nil`, which never pauses.
    ///   - countsDown: Whether to count up or down. The default is `true`.
    ///   - showsHours: Whether to include an hours component if there are more
    ///     than 60 minutes left on the timer (otherwise the minutes run on:
    ///     `119:30`). The default is `true`.
    public init(
        timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true,
        showsHours: Bool = true
    ) {
        self.init(
            live: TimerIntervalSource(
                start: timerInterval.lowerBound, end: timerInterval.upperBound, pauseTime: pauseTime,
                countsDown: countsDown, showsHours: showsHours))
    }
}

/// `Text(timerInterval:pauseTime:countsDown:showsHours:)`'s words at each
/// instant: the seconds left (or gone) on a clock face.
struct TimerIntervalSource: LiveTextSource, Equatable {
    let start: Date
    let end: Date
    let pauseTime: Date?
    let countsDown: Bool
    let showsHours: Bool

    /// The interval's length, in seconds.
    private var length: Double { max(0, end.timeIntervalSince(start)) }

    /// `pauseTime`'s offset into the interval, held inside it.
    private var pauseOffset: Double? {
        pauseTime.map { min(length, max(0, $0.timeIntervalSince(start))) }
    }

    /// The seconds the timer shows at `now`, before rounding: left, counting
    /// down, and gone, counting up — each held inside the interval, and at the
    /// pause.
    private func reading(at now: Date) -> Double {
        let gone = min(length, max(0, now.timeIntervalSince(start)))
        guard countsDown else { return min(gone, pauseOffset ?? length) }
        // SwiftUI's countdown stops when it SHOWS the pause's offset into the
        // interval (see `Text(timerInterval:…)`), so that offset is a floor.
        return max(length - gone, pauseOffset ?? 0)
    }

    /// Whole seconds, rounded the way the timer reads: up counting down, so it
    /// shows `0:01` until it is done; down counting up.
    private func seconds(at now: Date) -> Int {
        let value = reading(at: now)
        return Int(countsDown ? value.rounded(.up) : value.rounded(.down))
    }

    func text(at now: Date, in environment: LiveTextEnvironment) -> String {
        TimeSpan.clock(seconds: seconds(at: now), showsHours: showsHours)
    }

    func nextChange(after now: Date, in environment: LiveTextEnvironment) -> Date? {
        let current = seconds(at: now)
        if countsDown {
            // The seconds left are `ceil(end − t)`, which read one fewer once
            // `end − t` falls to it — unless the pause holds them first.
            let floor = Int((pauseOffset ?? 0).rounded(.up))
            guard current > floor else { return nil }
            return end.addingTimeInterval(-Double(current - 1))
        }
        // The seconds gone are `floor(t − start)`, up to the end or the pause.
        guard Double(current + 1) <= pauseOffset ?? length else { return nil }
        return start.addingTimeInterval(Double(current + 1))
    }
}
