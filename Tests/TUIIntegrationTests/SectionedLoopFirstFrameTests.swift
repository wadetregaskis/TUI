//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionedLoopFirstFrameTests.swift
//
//  A lazy stack of a loop of sections whose rows together pass the lazy
//  stack's threshold, though the loop and each section's loop are below it —
//  `ForEach(0..<100) { Section { ForEach(0..<100) } }` — builds only the rows
//  it samples and the rows on screen from its first frame, pinning its
//  sections' headers or not, however many sections and rows there are, and
//  draws what the same content in an eager `VStack` draws, the header of the
//  section under the top edge pinned there when the stack pins.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class Builds { var count = 0 }

@MainActor
@Suite("A lazy stack of a loop of sections builds only what it samples and shows, from its first frame")
struct SectionedLoopFirstFrameTests {
    /// A row of section `section`.
    private static func row(_ section: Int, _ index: Int) -> Text {
        Text(verbatim: index.isMultiple(of: 3) ? "s\(section) row \(index)" : "s\(section) r\(index)")
    }

    /// `sections` sections of `rows` rows, under a title or not, in a lazy
    /// stack pinning their headers or not, or in an eager `VStack` as wide
    /// as the scroll view (a lazy stack fills its width).
    private static func app(
        sections: Int, rows: Int, titled: Bool = false, lazy: Bool = true, pinned: Bool = false,
        spacing: Int = 0, builds: Builds = Builds()
    ) -> TestApp {
        func loop() -> some View {
            ForEach(0..<sections, id: \.self) { section in
                Section {
                    ForEach(0..<rows, id: \.self) { row in
                        builds.count += 1
                        return Self.row(section, row)
                    }
                } header: {
                    Text(verbatim: "Header \(section)")
                }
            }
        }
        let pins: PinnedScrollableViews = pinned ? .sectionHeaders : []
        let stack: AnyView
        switch (titled, lazy) {
        case (false, true):
            stack = AnyView(LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: pins) { loop() })
        case (true, true):
            stack = AnyView(
                LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: pins) {
                    Text("a title")
                    loop()
                })
        case (false, false):
            stack = AnyView(
                VStack(alignment: .leading, spacing: spacing) { loop() }.frame(maxWidth: .infinity, alignment: .leading))
        case (true, false):
            stack = AnyView(
                VStack(alignment: .leading, spacing: spacing) {
                    Text("a title")
                    loop()
                }.frame(maxWidth: .infinity, alignment: .leading))
        }
        return TestApp(width: 30, height: 12) { ScrollView { stack } }
    }

    /// The rows built on the first frame and on each of three page-downs.
    private static func built(sections: Int, rows: Int, titled: Bool, pinned: Bool) -> [Int] {
        let builds = Builds()
        let app = app(sections: sections, rows: rows, titled: titled, pinned: pinned, builds: builds)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<3 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    @Test(
        "The rows built on the first frame and each page do not grow with the sections or their rows",
        arguments: [false, true], [false, true])
    func firstFrameBuildsWhatShows(_ titled: Bool, _ pinned: Bool) {
        // Before: 31,200 rows on the first frame for 100 sections of 100,
        // every section measured whole for each measure of the stack.
        let base = Self.built(sections: 100, rows: 100, titled: titled, pinned: pinned)
        let moreSections = Self.built(sections: 200, rows: 100, titled: titled, pinned: pinned)
        let moreRows = Self.built(sections: 100, rows: 200, titled: titled, pinned: pinned)
        // The stack prices its sections by a sample of sixteen, and each
        // section its rows by a sample of sixteen, so the first frame is
        // bounded by the samples (1,076 to 2,017 rows here); a page builds
        // the band.
        for counts in [base, moreSections, moreRows] {
            #expect(counts[0] < 2_500, "\(base) \(moreSections) \(moreRows)")
            #expect(counts.dropFirst().allSatisfy { $0 < 150 }, "\(base) \(moreSections) \(moreRows)")
        }
    }

    /// The screen without the scroll bar's column, nor the blanks before it,
    /// which a line carries only where the bar's thumb is: the bar is sized
    /// from an estimate of the height below the band.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { line in
            var text = String(line.prefix(29))
            while text.last == " " { text.removeLast() }
            return text
        }
    }

    /// The twins compared at the top, paged down across several sections,
    /// at the end and paged up from it.
    private static func positions(_ apps: [TestApp], check: (String) -> Void) {
        check("top")
        for page in 1...12 {
            for app in apps { _ = app.press(.pageDown) }
            check("page \(page)")
        }
        for app in apps { _ = app.press(.end) }
        check("end")
        for page in 1...2 {
            for app in apps { _ = app.press(.pageUp) }
            check("end, page up \(page)")
        }
    }

    @Test("Unpinned, it draws what the same content drawn whole draws", arguments: [false, true], [0, 1])
    func drawsWhatTheWholeContentDraws(_ titled: Bool, _ spacing: Int) {
        let lazy = Self.app(sections: 40, rows: 20, titled: titled, spacing: spacing)
        let whole = Self.app(sections: 40, rows: 20, titled: titled, lazy: false, spacing: spacing)
        Self.positions([lazy, whole]) { step in
            #expect(Self.content(lazy) == Self.content(whole), "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
    }

    @Test("Pinned, it draws the same, the header of the section under the top edge on the first line",
          arguments: [false, true])
    func pinnedHeaders(_ titled: Bool) {
        let lazy = Self.app(sections: 40, rows: 20, titled: titled, pinned: true)
        let whole = Self.app(sections: 40, rows: 20, titled: titled, lazy: false)
        Self.positions([lazy, whole]) { step in
            var expected = Self.content(whole)
            // The eager column pins nothing: where its first line is a row,
            // the pinned stack draws that row's section's header over it.
            let first = expected[0].trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("s"), let section = first.dropFirst().split(separator: " ").first {
                expected[0] = "Header \(section)"
            }
            #expect(Self.content(lazy) == expected, "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
    }
}
