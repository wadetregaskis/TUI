//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyleClockTests.swift
//
//  `SystemFormatStyle.Timer` and `.Stopwatch`: every reading below is
//  SwiftUI's, measured on macOS 15 by formatting the same instants with the
//  same styles; the discrete boundaries are checked for what they mean — the
//  reading changes there and not before.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@Suite("SystemFormatStyle timer and stopwatch")
struct SystemFormatStyleClockTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")

    private func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }

    private func string<F: FormatStyle>(_ style: F, _ seconds: Double) -> String
    where F.FormatInput == Date, F.FormatOutput == AttributedString {
        String(style.locale(english).format(at(seconds)).characters)
    }

    /// The boundary after `seconds`, as seconds after `base`.
    @available(macOS 15, *)
    private func after<F: DiscreteFormatStyle>(_ style: F, _ seconds: Double) -> Double?
    where F.FormatInput == Date {
        style.discreteInput(after: at(seconds)).map { $0.timeIntervalSince(base) }
    }

    @available(macOS 15, *)
    private func before<F: DiscreteFormatStyle>(_ style: F, _ seconds: Double) -> Double?
    where F.FormatInput == Date {
        style.discreteInput(before: at(seconds)).map { $0.timeIntervalSince(base) }
    }

    // MARK: - Timer

    @Test(
        "A countdown reads the time left, rounded up, and holds its ends",
        arguments: [
            (-10.0, "1:02:05"), (0, "1:02:05"), (0.4, "1:02:05"), (1, "1:02:04"), (9.5, "1:01:56"),
            (3_124.9, "10:01"), (3_125.1, "10:00"), (3_724.2, "0:01"), (3_725, "0:00"), (9_000, "0:00"),
        ] as [(Double, String)])
    func countdown(_ seconds: Double, _ expected: String) {
        guard #available(macOS 15, *) else { return }
        #expect(string(SystemFormatStyle.Timer(countingDownIn: at(0)..<at(3_725)), seconds) == expected)
    }

    @Test(
        "A count-up reads the time gone, rounded down, and holds its ends",
        arguments: [
            (-10.0, "0:00"), (0.6, "0:00"), (1, "0:01"), (59.9, "0:59"), (60, "1:00"), (3_599.9, "59:59"),
            (3_600, "1:00:00"), (3_724.9, "1:02:04"), (9_000, "1:02:05"),
        ] as [(Double, String)])
    func countUp(_ seconds: Double, _ expected: String) {
        guard #available(macOS 15, *) else { return }
        #expect(string(SystemFormatStyle.Timer(countingUpIn: at(0)..<at(3_725)), seconds) == expected)
    }

    @Test("Hours, field counts and precision change the face as SwiftUI's does")
    func timerOptions() {
        guard #available(macOS 15, *) else { return }
        let long = at(0)..<at(100_000)
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, showsHours: false), 3_725) == "62:05")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, showsHours: false), 99_999) == "1666:39")
        #expect(string(SystemFormatStyle.Timer(countingDownIn: at(0)..<at(3_725), showsHours: false), 0) == "62:05")
        // One field is a unit; two hold m:ss but not h:mm:ss.
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxFieldCount: 1), 5) == "5 seconds")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxFieldCount: 1), 65) == "1 minute")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxFieldCount: 1), 3_725) == "1 hour")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxFieldCount: 2), 65) == "1:05")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxFieldCount: 2), 3_725) == "1 hour, 2 minutes")
        // Coarser than a second: units without seconds, truncated either way.
        let minutes = SystemFormatStyle.Timer(countingUpIn: long, maxPrecision: .seconds(60))
        #expect(string(minutes, 5.678) == "0 minutes")
        #expect(string(minutes, 65.678) == "1 minute")
        #expect(string(minutes, 3_725.678) == "1 hour, 2 minutes")
        #expect(string(SystemFormatStyle.Timer(countingDownIn: long, maxPrecision: .seconds(60)), 5.678) == "27 hours, 46 minutes")
        // Finer than a second: a fraction while there is a field for it.
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxPrecision: .milliseconds(100)), 5.678) == "0:05.6")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxPrecision: .milliseconds(10)), 5.678) == "0:05.67")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxPrecision: .milliseconds(1)), 65.678) == "1:05.67")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: long, maxPrecision: .milliseconds(10)), 3_725.678) == "1:02:05")
        #expect(string(SystemFormatStyle.Timer(countingDownIn: long, maxPrecision: .milliseconds(10)), 5.678) == "27:46:35")
        #expect(string(SystemFormatStyle.Timer(countingUpIn: at(0)..<at(1_000_000)), 400_000) == "111:06:40")
    }

    @Test("A timer's boundaries: where its reading next changes, and last changed")
    func timerBoundaries() {
        guard #available(macOS 15, *) else { return }
        let down = SystemFormatStyle.Timer(countingDownIn: at(0)..<at(3_725))
        #expect(after(down, -10) == 1)
        #expect(after(down, 0.4) == 1)
        #expect(after(down, 9.5) == 10)
        #expect(after(down, 3_724.9) == 3_725)
        #expect(after(down, 3_725) == nil)
        #expect(before(down, 0.4) == nil)
        let previous = before(down, 1)
        #expect(previous.map { $0 < 1 && $0 > 0.999 } == true)
        let up = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(3_725))
        #expect(after(up, -10) == 1)
        #expect(after(up, 59.9) == 60)
        #expect(after(up, 3_725) == nil)
        #expect(before(up, 0.4) == nil)
        // A countdown in minutes changes just after the minute falls.
        let minutes = SystemFormatStyle.Timer(countingDownIn: at(0)..<at(100_000), maxPrecision: .seconds(60))
        #expect(after(minutes, 5.678).map { $0 > 40 && $0 < 40.001 } == true)
        // Each boundary is where the reading changes, and not before.
        for style in [down, up] {
            for seconds in [-3.0, 0.2, 9.5, 61.7, 3_599.3, 3_724.5] {
                guard let next = style.discreteInput(after: at(seconds)) else { continue }
                #expect(style.format(next) != style.format(at(seconds)))
                #expect(style.format(next.addingTimeInterval(-0.001)) == style.format(at(seconds)))
            }
        }
    }

    // MARK: - Stopwatch

    @Test(
        "A stopwatch reads hundredths, two-digit leading field, from its start",
        arguments: [
            (-5.0, "00:00.00"), (0.004, "00:00.00"), (1.234, "00:01.23"), (59.999, "00:59.99"),
            (65.5, "01:05.50"), (3_599.99, "59:59.99"), (3_600, "01:00:00.00"), (3_725.25, "01:02:05.25"),
            (400_000, "111:06:40.00"),
        ] as [(Double, String)])
    func stopwatch(_ seconds: Double, _ expected: String) {
        guard #available(macOS 15, *) else { return }
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base), seconds) == expected)
    }

    @Test("A stopwatch's hours, field counts and precision")
    func stopwatchOptions() {
        guard #available(macOS 15, *) else { return }
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, showsHours: false), 3_725.25) == "62:05.25")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: 1), 65.25) == "1 minute")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: 2), 5.25) == "00:05")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: 2), 3_725.25) == "1 hour, 2 minutes")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: 3), 65.25) == "01:05.25")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: 3), 3_725.25) == "01:02:05")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxPrecision: .seconds(60)), 5.678) == "0 minutes")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxPrecision: .seconds(1)), 65.678) == "01:05")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxPrecision: .milliseconds(100)), 3_725.678) == "01:02:05.6")
        #expect(string(SystemFormatStyle.Stopwatch(startingAt: base, maxPrecision: .milliseconds(1)), 5.678) == "00:05.67")
    }

    @Test("A stopwatch's boundaries are a hundredth apart, none before its start")
    func stopwatchBoundaries() {
        guard #available(macOS 15, *) else { return }
        let watch = SystemFormatStyle.Stopwatch(startingAt: base)
        #expect(after(watch, -5).map { abs($0 - 0.01) < 1e-6 } == true)
        #expect(after(watch, 1.234).map { abs($0 - 1.24) < 1e-6 } == true)
        #expect(before(watch, 0.004) == nil)
        #expect(before(watch, -5) == nil)
        #expect(before(watch, 1.234).map { $0 < 1.23 && $0 > 1.229 } == true)
    }

    @Test("The statics build the styles, the locale spells the units, and the styles round-trip as JSON")
    func staticsAndCoding() throws {
        guard #available(macOS 15, *) else { return }
        let interval = at(0)..<at(100)
        #expect(SystemFormatStyle.Timer.timer(countingDownIn: interval) == SystemFormatStyle.Timer(countingDownIn: interval))
        #expect(SystemFormatStyle.Timer.timer(countingUpIn: interval) == SystemFormatStyle.Timer(countingUpIn: interval))
        #expect(SystemFormatStyle.Stopwatch.stopwatch(startingAt: base) == SystemFormatStyle.Stopwatch(startingAt: base))
        let german = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(10_000), maxFieldCount: 2)
            .locale(Locale(identifier: "de_DE"))
        #expect(String(german.format(at(3_725)).characters) == "1 Stunde und 2 Minuten")
        let watch = SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: 3)
        let decoded = try JSONDecoder().decode(SystemFormatStyle.Stopwatch.self, from: JSONEncoder().encode(watch))
        #expect(decoded == watch)
    }
}
