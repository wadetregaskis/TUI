//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyleDateTests.swift
//
//  `SystemFormatStyle.DateOffset` and `.DateReference`: every reading below is
//  SwiftUI's, measured on macOS 15 by formatting the same instants with the
//  same styles (en_US, Gregorian; the offsets and the relative references in
//  UTC, the absolute references in Los Angeles, where the probe ran).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkitStrings
@testable import TUIkitTestSupport

@Suite("SystemFormatStyle offset and reference")
struct SystemFormatStyleDateTests {
    /// 2026-05-09 06:13:20 UTC, 2026-05-08 23:13:20 in Los Angeles.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")

    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }

    @available(macOS 15, *)
    private func offset(_ style: SystemFormatStyle.DateOffset, _ seconds: Double) -> String {
        String(style.locale(english).calendar(calendar()).format(at(seconds)).characters)
    }

    @available(macOS 15, *)
    private func reference(_ style: SystemFormatStyle.DateReference, _ seconds: Double, zone: String = "UTC") -> String {
        String(style.locale(english).calendar(calendar(zone)).format(at(seconds)).characters)
    }

    // MARK: - DateOffset

    @Test(
        "An offset: two truncated units, signed when negative, zeros shown under a day",
        arguments: [
            (-90_000.0, "−1 day, 1 hour"), (-3_725, "−1 hour, 2 minutes"), (-125, "−2 minutes, 5 seconds"),
            (-59.6, "−59 seconds"), (-0.6, "−0 seconds"), (-0.4, "−0 seconds"), (0, "0 seconds"),
            (0.6, "0 seconds"), (1, "1 second"), (59.6, "59 seconds"), (60, "1 minute, 0 seconds"),
            (119.6, "1 minute, 59 seconds"), (3_599.6, "59 minutes, 59 seconds"), (3_600, "1 hour, 0 minutes"),
            (3_779.6, "1 hour, 2 minutes"), (86_399, "23 hours, 59 minutes"), (86_400, "1 day"),
            (90_000, "1 day, 1 hour"), (2_678_400, "1 month"), (40_000_000, "1 year, 3 months"),
        ] as [(Double, String)])
    func offsets(_ seconds: Double, _ expected: String) {
        guard #available(macOS 15, *) else { return }
        #expect(offset(SystemFormatStyle.DateOffset(to: base), seconds) == expected)
    }

    @Test("Sign strategies, field counts and allowed fields")
    func offsetOptions() {
        guard #available(macOS 15, *) else { return }
        let never = SystemFormatStyle.DateOffset(to: base, sign: .never)
        #expect(offset(never, -30) == "30 seconds")
        let always = SystemFormatStyle.DateOffset(to: base, sign: .always())
        #expect([-30.0, 0, 30].map { offset(always, $0) } == ["−30 seconds", "+0 seconds", "+30 seconds"])
        let notZero = SystemFormatStyle.DateOffset(to: base, sign: .always(includingZero: false))
        #expect([-30.0, 0, 30].map { offset(notZero, $0) } == ["−30 seconds", "0 seconds", "+30 seconds"])
        #expect(offset(SystemFormatStyle.DateOffset(to: base, maxFieldCount: 1), 3_725) == "1 hour")
        #expect(offset(SystemFormatStyle.DateOffset(to: base, maxFieldCount: 1), 90_061) == "1 day")
        #expect(offset(SystemFormatStyle.DateOffset(to: base, maxFieldCount: 3), 3_725) == "1 hour, 2 minutes, 5 seconds")
        #expect(offset(SystemFormatStyle.DateOffset(to: base, maxFieldCount: 3), 90_061) == "1 day, 1 hour, 1 minute")
        // Minutes and seconds only: a clock face.
        let face = SystemFormatStyle.DateOffset(to: base, allowedFields: [.minute, .second])
        #expect([5.0, 125, 3_725, -125].map { offset(face, $0) } == ["0:05", "2:05", "62:05", "−2:05"])
        let hms = SystemFormatStyle.DateOffset(to: base, allowedFields: [.hour, .minute, .second])
        #expect([5.0, 125, 3_725, 90_061].map { offset(hms, $0) }
            == ["5 seconds", "2 minutes, 5 seconds", "1 hour, 2 minutes", "25 hours, 1 minute"])
        let hm = SystemFormatStyle.DateOffset(to: base, allowedFields: [.hour, .minute])
        #expect([5.0, 125, 90_061].map { offset(hm, $0) } == ["0 minutes", "2 minutes", "25 hours, 1 minute"])
        let weeks = SystemFormatStyle.DateOffset(to: base, allowedFields: [.week, .day])
        #expect([5.0, 90_061, 700_000, 2_678_400].map { offset(weeks, $0) }
            == ["0 days", "1 day", "1 week, 1 day", "4 weeks, 3 days"])
        #expect(String(SystemFormatStyle.DateOffset(to: base).locale(Locale(identifier: "de_DE")).format(at(3_725)).characters)
            == "1 Stunde und 2 Minuten")
    }

    @Test("An offset's boundaries are SwiftUI's")
    func offsetBoundaries() {
        guard #available(macOS 15, *) else { return }
        let style = SystemFormatStyle.DateOffset(to: base).calendar(calendar())
        func after(_ seconds: Double) -> Double? { style.discreteInput(after: at(seconds))?.timeIntervalSince(base) }
        #expect(after(-0.6) == 0, "the sign goes at the anchor")
        #expect(after(0) == 1)
        #expect(after(59.4) == 60)
        #expect(after(60) == 61)
        #expect(after(3_600) == 3_660, "a minute's resolution from an hour")
        #expect(after(86_399) == 86_400)
        #expect(after(86_400) == 90_000, "the hidden hour still counts")
        #expect(after(2_678_400) == 3_283_200, "a month, and the week after it")
        #expect(after(40_000_000) == 42_163_200)
        // Ahead of the anchor, just after the span falls short.
        #expect(after(-125).map { $0 > -125 && $0 < -124.999 } == true)
        #expect(after(-90_000).map { $0 > -90_000 && $0 < -89_999.999 } == true)
        let face = SystemFormatStyle.DateOffset(to: base, allowedFields: [.minute, .second]).calendar(calendar())
        #expect(face.discreteInput(after: at(3_725))?.timeIntervalSince(base) == 3_726)
        // The static counts no weeks; the initialiser does.
        let noWeeks = SystemFormatStyle.DateOffset(to: base, allowedFields: [.year, .month, .day, .hour, .minute, .second])
        #expect(SystemFormatStyle.DateOffset.offset(to: base) == noWeeks)
        // Before: the reading differs there, and not just after.
        for seconds in [-3_725.0, -0.4, 0.4, 61, 3_725, 90_000] {
            guard let previous = style.discreteInput(before: at(seconds)) else { continue }
            #expect(style.format(previous) != style.format(at(seconds)))
            #expect(previous < at(seconds))
        }
        #expect(style.input(after: at(10))! > at(10))
        #expect(style.input(before: at(10))! < at(10))
    }

    // MARK: - DateReference

    @Test(
        "A reference near the date is relative: now within half a minute, days by the calendar",
        arguments: [
            (-400_000.0, "in 5 days"), (-200_000, "in 3 days"), (-90_000, "tomorrow"), (-86_400, "tomorrow"),
            (-3_725, "in 1 hour"), (-3_599, "in 1 hour"), (-125, "in 2 minutes"), (-89.4, "in 1 minute"),
            (-30.6, "in 1 minute"), (-29.4, "now"), (-0.6, "now"), (0, "now"), (0.6, "now"), (29.4, "now"),
            (29.6, "1 minute ago"), (30, "1 minute ago"), (89.4, "1 minute ago"), (89.6, "2 minutes ago"),
            (125, "2 minutes ago"), (3_599, "1 hour ago"), (3_600, "1 hour ago"), (5_399.6, "2 hours ago"),
            (86_399, "yesterday"), (90_000, "yesterday"), (172_800, "2 days ago"), (400_000, "4 days ago"),
        ] as [(Double, String)])
    func relativeReferences(_ seconds: Double, _ expected: String) {
        guard #available(macOS 15, *) else { return }
        #expect(reference(SystemFormatStyle.DateReference(to: base), seconds) == expected)
    }

    @Test("A reference far from the date is absolute, in the fields that differ")
    func absoluteReferences() {
        guard #available(macOS 15, *) else { return }
        let style = SystemFormatStyle.DateReference(to: base)
        let la = "America/Los_Angeles"
        #expect(reference(style, -40_000_000, zone: la) == "May 2026")
        #expect(reference(style, -5_000_000, zone: la) == "Friday, May 8")
        #expect(reference(style, 5_000_000, zone: la) == "Friday, May 8")
        #expect(reference(style, 40_000_000, zone: la) == "May 2026")
        let three = SystemFormatStyle.DateReference(to: base, maxFieldCount: 3)
        #expect(reference(three, 5_000_000, zone: la).hasPrefix("Friday, May 8 at 11"))
        #expect(reference(three, 40_000_000, zone: la) == "May 8, 2026")
        let one = SystemFormatStyle.DateReference(to: base, maxFieldCount: 1)
        #expect([5_000_000.0, 40_000_000].map { reference(one, $0, zone: la) } == ["May", "2026"])
    }

    @Test("The threshold field decides where the relative form stops")
    func thresholds() {
        guard #available(macOS 15, *) else { return }
        let la = "America/Los_Angeles"
        let hour = SystemFormatStyle.DateReference(to: base, thresholdField: .hour)
        #expect(reference(hour, -3_725, zone: la) == "in 1 hour")
        #expect(reference(hour, -90_000, zone: la).hasPrefix("Friday 8, 11"))
        let month = SystemFormatStyle.DateReference(to: base, thresholdField: .month)
        #expect(reference(month, -90_000) == "tomorrow")
        #expect(reference(month, 5_000_000) == "2 months ago")
        #expect(reference(month, 40_000_000, zone: la) == "May 2026")
        // Allowed only minutes and seconds, it never runs out of relative.
        let seconds = SystemFormatStyle.DateReference(to: base, allowedFields: [.minute, .second], thresholdField: .minute)
        #expect([-30.0, 30, 125, 3_725].map { reference(seconds, $0) }
            == ["in 30 seconds", "30 seconds ago", "2 minutes ago", "62 minutes ago"])
        #expect(reference(seconds, 90_000) == "1,500 minutes ago")
    }

    @Test("A reference's boundaries: the relative form's, and where it turns absolute")
    func referenceBoundaries() {
        guard #available(macOS 15, *) else { return }
        let style = SystemFormatStyle.DateReference(to: base).locale(english).calendar(calendar())
        func after(_ seconds: Double) -> Double? { style.discreteInput(after: at(seconds))?.timeIntervalSince(base) }
        #expect(after(29.4) == 29.5)
        #expect(after(29.6) == 89.5)
        #expect(after(125) == 149.5)
        #expect(after(3_599) == 5_399.5)
        #expect(after(86_399) == 150_399.5, "midnight, in the calendar's zone")
        #expect(after(400_000) == 409_599.5)
        #expect(after(-125).map { $0 > -89.5 && $0 < -89.499 } == true)
        // From an absolute March to the relative May: at the start of May,
        // half a second early as the input is rounded.
        #expect(after(-5_000_000).map { $0 > -713_600.5 && $0 < -713_600.499 } == true)
        // A boundary is never later than the change it stands for.
        let turn = style.discreteInput(after: at(5_000_000))
        #expect(turn.map { $0 <= at(20_454_400) } == true)
        #expect(style.discreteInput(before: at(125)).map { style.format($0) != style.format(at(125)) } == true)
        #expect(SystemFormatStyle.DateReference.reference(to: base) == SystemFormatStyle.DateReference(to: base))
    }

    /// A context that takes any discrete style — what `Text(.currentDate,
    /// format:)` is.
    @available(macOS 15, *)
    private func discrete<F: DiscreteFormatStyle>(_ style: F) -> F { style }

    /// On macOS, SwiftUI's own `FormatStyle.offset(to:)` and the rest reach
    /// this target through AppKit; with TUIkit's only on `FormatStyle` these
    /// lines were ambiguous. They compile, and are TUIkit's styles, because
    /// TUIkit declares each again on `DiscreteFormatStyle`.
    @Test("In a discrete context the statics are TUIkit's, though SwiftUI's are visible on macOS")
    func staticsResolveToTUIkit() {
        guard #available(macOS 15, *) else { return }
        #expect(discrete(.offset(to: base)) == SystemFormatStyle.DateOffset(to: base, allowedFields: [.year, .month, .day, .hour, .minute, .second]))
        #expect(discrete(.reference(to: base)) == SystemFormatStyle.DateReference(to: base))
        #expect(discrete(.timer(countingDownIn: base..<at(10))) == SystemFormatStyle.Timer(countingDownIn: base..<at(10)))
        #expect(discrete(.timer(countingUpIn: base..<at(10))) == SystemFormatStyle.Timer(countingUpIn: base..<at(10)))
        #expect(discrete(.stopwatch(startingAt: base)) == SystemFormatStyle.Stopwatch(startingAt: base))
    }

    @Test("A reference in German, and both styles round-trip as JSON")
    func localisedAndCoded() throws {
        guard #available(macOS 15, *) else { return }
        let german = SystemFormatStyle.DateReference(to: base).locale(Locale(identifier: "de_DE")).calendar(calendar())
        #expect(String(german.format(at(125)).characters) == "vor 2 Minuten")
        #expect(String(german.format(at(-90_000)).characters) == "morgen")
        let reference = SystemFormatStyle.DateReference(to: base, maxFieldCount: 3)
        #expect(try JSONDecoder().decode(SystemFormatStyle.DateReference.self, from: JSONEncoder().encode(reference)) == reference)
        let offset = SystemFormatStyle.DateOffset(to: base, sign: .never)
        #expect(try JSONDecoder().decode(SystemFormatStyle.DateOffset.self, from: JSONEncoder().encode(offset)) == offset)
    }
}
