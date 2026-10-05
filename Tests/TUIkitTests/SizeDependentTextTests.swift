//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SizeDependentTextTests.swift
//
//  `.textVariant(.sizeDependent)`: each live source's ladder of spellings,
//  widest first (SwiftUI's, measured on macOS 15 in en_US — decisions A32),
//  German's among them, and a text choosing the widest that fits, the measure
//  and the render alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Size-dependent text variants")
struct SizeDependentTextTests {
    /// 2026-05-09 06:13:20 UTC, a Saturday.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func environment(_ locale: String = "en_US") -> LiveTextEnvironment {
        LiveTextEnvironment(
            locale: Locale(identifier: locale), calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC")!)
    }

    /// A Gregorian calendar in UTC, for the format styles that keep their own.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// `Text(date, style:)`'s ladder, the date `offset` seconds before `base`.
    private func ladder(_ style: Text.DateStyle, _ offset: Double, locale: String = "en_US") -> [String] {
        DateStyleSource(date: base.addingTimeInterval(-offset), style: style)
            .sizeVariants(at: base, in: environment(locale))
    }

    /// Spaces as one kind: Foundation spells some with narrow no-break ones.
    private func plain(_ strings: [String]) -> [String] {
        strings.map { $0.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{A0}", with: " ") }
    }

    // MARK: - The ladders

    @Test("Text(_:style:) steps down as SwiftUI's does")
    func dateStyleLadders() {
        #expect(ladder(.relative, 3_725) == ["1 hr, 2 min", "1h 2m"])
        #expect(ladder(.offset, 3_600) == ["+1 hour", "+1 hr", "+1h"])
        // 2026-05-08 23:13 UTC: SwiftUI's own examples.
        let eighth = base.addingTimeInterval(-25_200)
        #expect(plain(DateStyleSource(date: eighth, style: .time).sizeVariants(at: base, in: environment())) == [
            "11:13 PM", "11 PM",
        ])
        #expect(DateStyleSource(date: eighth, style: .date).sizeVariants(at: base, in: environment()) == [
            "May 8, 2026", "May 2026", "2026",
        ])
        #expect(ladder(.timer, 3_725) == ["1:02:05"], "a timer's face has no narrower spelling")
    }

    @available(macOS 15, *)
    @Test("The SystemFormatStyle dates step down as SwiftUI's do")
    func formatStyleLadders() {
        let offset = SystemFormatStyle.DateOffset(to: base).calendar(utc)
        #expect(offset.sizeVariants(of: base.addingTimeInterval(3_725), locale: Locale(identifier: "en_US")) == [
            "1 hour, 2 minutes", "1 hr, 2 min", "1h 2m",
        ])
        let reference = SystemFormatStyle.DateReference(to: base.addingTimeInterval(-120)).calendar(utc)
        #expect(reference.sizeVariants(of: base, locale: Locale(identifier: "en_US")) == [
            "2 minutes ago", "2 min. ago", "2m ago",
        ])
        // Friday the 8th, read a month on: the absolute form.
        let friday = SystemFormatStyle.DateReference(to: base.addingTimeInterval(-25_200)).calendar(utc)
        #expect(friday.sizeVariants(of: base.addingTimeInterval(30 * 86_400), locale: Locale(identifier: "en_US")) == [
            "Friday, May 8", "Fri, May 8", "5/8",
        ])
        let timer = SystemFormatStyle.Timer(countingUpIn: base..<base.addingTimeInterval(7_200), maxFieldCount: 2)
        #expect(timer.sizeVariants(of: base.addingTimeInterval(3_725), locale: Locale(identifier: "en_US")) == [
            "1 hour, 2 minutes", "1 hr 2 min", "1:02",
        ])
        let stopwatch = SystemFormatStyle.Stopwatch(startingAt: base)
        #expect(stopwatch.sizeVariants(of: base.addingTimeInterval(3_725.5), locale: Locale(identifier: "en_US")) == [
            "01:02:05.50", "1:02:05", "1:02", "1h",
        ])
    }

    @Test("German steps down in German, each rung narrower than the one before")
    func germanRungs() {
        let offset = plain(ladder(.offset, 3_600, locale: "de_DE"))
        #expect(offset.first == "+1 Stunde")
        let relative = plain(ladder(.relative, 3_725, locale: "de_DE"))
        #expect(relative.count == 2)
        for rungs in [offset, relative] {
            for (wider, narrower) in zip(rungs, rungs.dropFirst()) {
                #expect(narrower.count <= wider.count, "\(narrower) is not narrower than \(wider)")
            }
            #expect(rungs.allSatisfy { !$0.contains("hour") && !$0.contains("hr") }, "\(rungs) is not German")
        }
        let eighth = base.addingTimeInterval(-25_200)
        let date = DateStyleSource(date: eighth, style: .date).sizeVariants(at: base, in: environment("de_DE"))
        #expect(date == ["8. Mai 2026", "Mai 2026", "2026"])
    }

    @Test("An interpolated key's live value steps down inside its words")
    func interpolatedKey() {
        let past = base.addingTimeInterval(-3_725)
        let text = Text("Started \(past, style: .relative) ago")
        let rungs = text.liveSizeVariants(at: base, in: environment()).map(\.content)
        #expect(rungs == ["Started 1 hr, 2 min ago", "Started 1h 2m ago"])
    }

    // MARK: - Choosing

    private func harness(width: Int) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.locale = Locale(identifier: "en_US")
        environment.timeZone = TimeZone(identifier: "UTC")!
        return (tui, RenderContext(availableWidth: width, availableHeight: 4, environment: environment, tuiContext: tui))
    }

    /// The text drawn, one line, in a box `width` cells wide — and what its
    /// measure reported, which must be what it drew.
    private func drawn(_ view: some View, width: Int) -> (line: String, measured: Int) {
        let (tui, context) = harness(width: width)
        tui.renderCache.beginRenderPass()
        tui.renderCache.frameDate = base
        let size = measureChild(view, proposal: ProposedSize(width: width, height: nil), context: context)
        let buffer = renderToBuffer(view, context: context)
        return (buffer.lines.first?.stripped ?? "", size.width)
    }

    @Test("A size-dependent text draws the widest spelling that fits on its line, and measures it")
    func choosesTheWidestThatFits() {
        let past = base.addingTimeInterval(-3_600)
        let text = Text(past, style: .offset).textVariant(.sizeDependent).lineLimit(1)
        for (width, expected) in [(20, "+1 hour"), (7, "+1 hour"), (6, "+1 hr"), (5, "+1 hr"), (4, "+1h"), (3, "+1h")] {
            let (line, measured) = drawn(text, width: width)
            #expect(line == expected, "at \(width) cells")
            #expect(measured == expected.count, "at \(width) cells the measure chose otherwise")
        }
        // Nothing fits: the narrowest, cut as any text is.
        #expect(drawn(text, width: 2).line.count <= 2)
        // A fixed text keeps the widest, cut.
        #expect(drawn(Text(past, style: .offset).textVariant(.fixed).lineLimit(1), width: 4).line != "+1h")
    }

    @Test("Without a line limit the widest wraps and is kept, as SwiftUI keeps it")
    func wrappingKeepsTheWidest() {
        let past = base.addingTimeInterval(-3_725)
        let text = Text("Started \(past, style: .relative) ago").textVariant(.sizeDependent)
        let (tui, context) = harness(width: 12)
        tui.renderCache.beginRenderPass()
        tui.renderCache.frameDate = base
        let lines = renderToBuffer(text, context: context).lines.map(\.stripped)
        #expect(lines.joined(separator: " ").contains("1 hr, 2 min"), "\(lines)")
        let limited = Text("Started \(past, style: .relative) ago").textVariant(.sizeDependent).lineLimit(1)
        #expect(drawn(limited, width: 17).line == "Started 1h 2m ago")
    }
}
