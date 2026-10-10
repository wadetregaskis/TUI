//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimeDataSourceTests.swift
//
//  `Text(_:format:)` over a `TimeDataSource`: the source's value at the frame's
//  date through the style, the readings SwiftUI drew (macOS 15), and a frame
//  asked for where the style says its output next changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("TimeDataSource")
struct TimeDataSourceTests {
    /// 2026-05-09 06:13:20 UTC.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var environment: LiveTextEnvironment {
        LiveTextEnvironment(
            locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC")!)
    }

    /// The text's words at a frame dated `base`, in en_US and UTC.
    private func drawn(_ text: Text) -> String {
        let context = makeRenderContext(width: 60, height: 1) { environment, _ in
            environment.locale = Locale(identifier: "en_US")
            environment.calendar = Calendar(identifier: .gregorian)
            environment.timeZone = TimeZone(identifier: "UTC")!
        }
        context.renderCache?.frameDate = base
        return renderToBuffer(text, context: context).lines.first?.stripped ?? ""
    }

    /// When the text next changes, in seconds after `base`.
    private func change(_ text: Text) -> Double? {
        guard let (_, next) = text.readingLive(at: base, in: environment) else { return nil }
        return next?.timeIntervalSince(base)
    }

    private func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }

    @Test("The system styles over the current date draw what SwiftUI drew")
    func systemStyles() {
        guard #available(macOS 15, *) else { return }
        #expect(drawn(Text(.currentDate, format: .reference(to: at(-125.5)))) == "2 minutes ago")
        #expect(drawn(Text(.currentDate, format: .offset(to: at(-125.5)))) == "2 minutes, 5 seconds")
        #expect(drawn(Text(.currentDate, format: .timer(countingDownIn: at(-0.5)..<at(90)))) == "1:30")
        #expect(drawn(Text(.currentDate, format: .stopwatch(startingAt: at(-65.5)))) == "01:05.50")
    }

    @Test("A format into a String draws, and the environment's locale reaches it")
    func stringStyles() {
        guard #available(macOS 15, *) else { return }
        let time = Date.FormatStyle(date: .omitted, time: .standard, timeZone: TimeZone(identifier: "UTC")!)
        #expect(drawn(Text(.currentDate, format: time)).hasPrefix("6:13:20"))
        #expect(drawn(Text(.durationOffset(to: at(-125.5)), format: .time(pattern: .minuteSecond))) == "2:06")
        #expect(drawn(Text(.durationOffset(to: at(125.5)), format: .time(pattern: .minuteSecond))) == "-2:06")
    }

    @Test("Each asks for a frame where its style's output next changes")
    func wakes() {
        guard #available(macOS 15, *) else { return }
        #expect(change(Text(.currentDate, format: .reference(to: at(-125)))) == 24.5)
        #expect(change(Text(.currentDate, format: .offset(to: at(-125.5)))) == 0.5)
        #expect(change(Text(.currentDate, format: .timer(countingDownIn: at(-0.5)..<at(90)))) == 1)
        // A finished timer asks for nothing.
        #expect(change(Text(.currentDate, format: .timer(countingDownIn: at(-100)..<at(-10)))) == nil)
        // The offset runs with time: the next input after 125.5 s is 126.5 s.
        #expect(change(Text(.durationOffset(to: at(-125.5)), format: .time(pattern: .minuteSecond))) == 1)
        let seconds = Date.FormatStyle(date: .omitted, time: .standard)
        #expect(change(Text(.currentDate, format: seconds)) == 1)
    }

    #if !canImport(FoundationEssentials)
        @Test("Date ranges: since a date, until one, and nothing before it starts")
        func dateRanges() {
            guard #available(macOS 15, *) else { return }
            let style = Date.ComponentsFormatStyle(style: .wide)
            #expect(drawn(Text(.dateRange(startingAt: at(-125.5)), format: style)) == "2 minutes, 5 seconds")
            #expect(drawn(Text(.dateRange(endingAt: at(125.5)), format: style)) == "2 minutes, 5 seconds")
            #expect(drawn(Text(.dateRange(startingAt: at(125.5)), format: style)) == "0 seconds")
            // Since a date, it grows; until one, it shrinks — just after half a
            // second, when 2:05.5 left becomes 2:04.something.
            #expect(change(Text(.dateRange(startingAt: at(-125.5)), format: style)) == 0.5)
            let until = change(Text(.dateRange(endingAt: at(125.5)), format: style))
            #expect(until.map { $0 > 0.5 && $0 < 0.501 } == true)
        }
    #endif

    @Test("Two texts over the same source and style are equal")
    func equality() {
        guard #available(macOS 15, *) else { return }
        let start = at(-1_000_000)
        let first = Text(.currentDate, format: .reference(to: start))
        let second = Text(.currentDate, format: .reference(to: start))
        #expect(first == second)
        #expect(first != Text(.currentDate, format: .offset(to: start)))
    }

    @Test("An AttributedString style formats a plain value, and interpolates")
    func attributedFormat() {
        guard #available(macOS 15, *) else { return }
        let offset = SystemFormatStyle.DateOffset(to: base).locale(Locale(identifier: "en_US"))
        #expect(Text(at(125), format: offset).content == "2 minutes, 5 seconds")
        let key: LocalizedStringKey = "In \(at(-125), format: offset)"
        #expect(key.localized == "In \u{2212}2 minutes, 5 seconds")
    }
}
