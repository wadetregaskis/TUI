//  🖥️ TUI — A Terminal UI framework for Swift
//  TextDateStyleTests.swift
//
//  `Text(_:style:)`: the strings SwiftUI draws for each style (measured on
//  macOS 15 by rendering and reading the picture back, en_US), the instant
//  each next changes, and the environment it formats in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Text(_:style:)")
struct TextDateStyleTests {
    /// 2026-05-09 06:13:20 UTC.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func environment(_ locale: String = "en_US", zone: String = "UTC") -> LiveTextEnvironment {
        LiveTextEnvironment(
            locale: Locale(identifier: locale), calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: zone)!)
    }

    /// What `Text(date, style:)` reads `offset` seconds after `date` — so a
    /// positive offset is a date that has passed.
    private func reading(_ style: Text.DateStyle, _ offset: Double, locale: String = "en_US") -> String {
        let date = base.addingTimeInterval(-offset)
        return DateStyleSource(date: date, style: style).text(at: base, in: environment(locale))
    }

    /// When that reading next changes, as seconds after `base`.
    private func change(_ style: Text.DateStyle, _ offset: Double) -> Double? {
        let date = base.addingTimeInterval(-offset)
        return DateStyleSource(date: date, style: style).nextChange(after: base, in: environment())
            .map { $0.timeIntervalSince(base) }
    }

    // MARK: - The strings

    @Test("time and date read the date itself, in the environment's zone and locale")
    func timeAndDate() {
        #expect(reading(.time, 0) == "6:13\u{202F}AM" || reading(.time, 0) == "6:13 AM")
        #expect(reading(.date, 0) == "May 9, 2026")
        #expect(reading(.time, 0, locale: "de_DE") == "06:13")
        #expect(reading(.date, 0, locale: "de_DE") == "9. Mai 2026")
        // Neither moves with the clock.
        #expect(change(.time, 0) == nil)
        #expect(change(.date, 1_000) == nil)
    }

    /// Each pair is SwiftUI's reading for a date that many seconds past and the
    /// same distance ahead; `.relative` has no sign, so they agree.
    @Test(
        "relative: two abbreviated units, truncated, either side of now",
        arguments: [
            (0.3, "0 sec"), (0.7, "0 sec"), (1.5, "1 sec"), (9.5, "9 sec"), (59.5, "59 sec"),
            (60.5, "1 min, 0 sec"), (119.5, "1 min, 59 sec"), (3_599.5, "59 min, 59 sec"),
            (3_600.5, "1 hr, 0 min"), (3_659.5, "1 hr, 0 min"), (3_779.5, "1 hr, 2 min"),
            (86_399.5, "23 hr, 59 min"), (86_400.5, "1 day"), (90_061.5, "1 day, 1 hr"),
            (172_800.5, "2 days"), (40_000_000.5, "1 yr, 3 mths"),
        ] as [(Double, String)])
    func relative(_ offset: Double, _ expected: String) {
        #expect(reading(.relative, offset) == expected)
        #expect(reading(.relative, -offset) == expected)
    }

    @Test("relative counts months and years by the calendar, in the environment's zone")
    func relativeCalendar() {
        // A month and a day back from 9 May is 8 April.
        #expect(reading(.relative, 2_678_400.5) == "1 mth, 1 day")
        // 366 days back is a year and a day, and the day is not the unit after
        // the year: "1 yr", as SwiftUI drew it.
        #expect(reading(.relative, 31_622_400.5) == "1 yr")
        // Across the autumn clock change in Los Angeles, 31 days ahead is an
        // hour short of a month: SwiftUI drew "30 days, 23 hr" on 3 October.
        let october = Date(timeIntervalSinceReferenceDate: 812_746_800)  // 2026-10-03 12:00 PDT
        let ahead = october.addingTimeInterval(2_678_400.5)
        #expect(
            DateStyleSource(date: ahead, style: .relative).text(
                at: october, in: environment(zone: "America/Los_Angeles")) == "30 days, 23 hr")
    }

    @Test(
        "offset: one wide unit, truncated, + for a date passed and − for one ahead",
        arguments: [
            (0.3, "0 seconds"), (1.5, "1 second"), (9.5, "9 seconds"), (59.5, "59 seconds"),
            (60.5, "1 minute"), (119.5, "1 minute"), (3_599.5, "59 minutes"), (3_600.5, "1 hour"),
            (3_779.5, "1 hour"), (86_399.5, "23 hours"), (86_400.5, "1 day"), (90_061.5, "1 day"),
            (172_800.5, "2 days"), (31_622_400.5, "1 year"), (40_000_000.5, "1 year"),
        ] as [(Double, String)])
    func offset(_ offset: Double, _ expected: String) {
        #expect(reading(.offset, offset) == "+" + expected)
        #expect(reading(.offset, -offset) == "\u{2212}" + expected)
    }

    @Test("offset's months are calendar months")
    func offsetMonths() {
        #expect(reading(.offset, 2_678_400.5) == "+1 month")
    }

    @Test(
        "timer: whole seconds either side of the date, hours as many as it takes",
        arguments: [
            (0.3, "0:00"), (0.7, "0:00"), (1.5, "0:01"), (9.5, "0:09"), (59.5, "0:59"),
            (60.5, "1:00"), (3_599.5, "59:59"), (3_600.5, "1:00:00"), (86_400.5, "24:00:00"),
            (400_000.5, "111:06:40"),
        ] as [(Double, String)])
    func timer(_ offset: Double, _ expected: String) {
        #expect(reading(.timer, offset) == expected)
        #expect(reading(.timer, -offset) == expected)
    }

    @Test("relative and offset are spelt in the environment's locale")
    func localised() {
        #expect(reading(.relative, 3_725.5, locale: "de_DE") == "1 Std., 2 Min.")
        #expect(reading(.offset, 3_725.5, locale: "de_DE") == "+1 Stunde")
    }

    // MARK: - When each changes

    @Test("relative changes when its finest shown unit does")
    func relativeChanges() {
        // "2 min, 5 sec" past: at 2:06.
        #expect(change(.relative, 125.5) == 0.5)
        // "1 hr, 2 min" past: at 1:03:00, a minute's resolution.
        #expect(change(.relative, 3_725.5) == 54.5)
        // "1 day" past: the hidden hour still counts — at a day and an hour.
        #expect(change(.relative, 86_400.5) == 3_599.5)
        // "2 min, 5 sec" ahead: just after it falls to 2:05 left.
        let ahead = change(.relative, -125.5)
        #expect(ahead.map { $0 > 0.5 && $0 < 0.500_01 } == true)
    }

    @Test("offset changes sign at the date, and timer reads 0:00 a second either side of it")
    func aroundTheDate() {
        #expect(change(.offset, -0.5) == 0.5)
        #expect(change(.timer, -0.5) == 1.5)
        #expect(change(.timer, 0.5) == 0.5)
    }

    // MARK: - Drawn

    @Test("The text draws its style at the frame's date, in the environment's locale and zone")
    func drawn() {
        let context = makeRenderContext(width: 40, height: 3) { environment, _ in
            environment.locale = Locale(identifier: "en_US")
            environment.calendar = Calendar(identifier: .gregorian)
            environment.timeZone = TimeZone(identifier: "UTC")!
        }
        context.renderCache?.frameDate = base
        let lines = renderToBuffer(
            VStack(alignment: .leading) {
                Text(base.addingTimeInterval(-125.5), style: .relative)
                Text(base.addingTimeInterval(125.5), style: .offset)
                Text(base.addingTimeInterval(-65.5), style: .timer)
            }, context: context
        ).lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(lines == ["2 min, 5 sec", "\u{2212}2 minutes", "1:05"])
    }

    @Test("DateStyle encodes as SwiftUI's does")
    func codable() throws {
        let encoded = try JSONEncoder().encode(Text.DateStyle.relative)
        #expect(String(data: encoded, encoding: .utf8) == #"{"storage":2}"#)
        #expect(try JSONDecoder().decode(Text.DateStyle.self, from: Data(#"{"storage":4}"#.utf8)) == .timer)
    }
}
