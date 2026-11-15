//  🖥️ TUI — A Terminal UI framework for Swift
//  HeadedLazyStackFirstFrameTests.swift
//
//  A lazy stack whose content is a header and a loop, `LazyVStack { header;
//  ForEach(0..<n) }`, in a scroll view builds only the rows on screen on its
//  first frame, as it does on every frame after.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class Builds { var count = 0 }

@MainActor
@Suite("A lazy stack with a header and a loop builds only what shows, from its first frame")
struct HeadedLazyStackFirstFrameTests {
    private static func app(rows: Int, builds: Builds) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("header")
                    ForEach(0..<rows, id: \.self) { index in
                        builds.count += 1
                        return Text(verbatim: "r\(index)")
                    }
                }
            }
        }
    }

    /// The rows built on the first frame and on each of three page-downs.
    private static func built(rows: Int) -> [Int] {
        let builds = Builds()
        let app = app(rows: rows, builds: builds)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<3 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    @Test("The rows built on the first frame and each page do not grow with the row count")
    func firstFrameBuildsWhatShows() {
        let small = Self.built(rows: 1_000)
        let tall = Self.built(rows: 10_000)
        #expect(tall.allSatisfy { $0 < 150 }, "\(tall)")
        #expect(tall == small, "\(tall) \(small)")
    }

    /// The lazy stack, or the same content in an eager `VStack` as wide as
    /// the scroll view (a lazy stack fills its width), drawn whole.
    private static func twin(lazy: Bool, alignment: HorizontalAlignment, spacing: Int) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                if lazy {
                    LazyVStack(alignment: alignment, spacing: spacing) { Self.content }
                } else {
                    VStack(alignment: alignment, spacing: spacing) { Self.content }
                        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
                }
            }
        }
    }

    @ViewBuilder private static var content: some View {
        Text("a wide header")
        ForEach(0..<300, id: \.self) { index in
            Text(verbatim: index.isMultiple(of: 3) ? "row \(index)" : "r\(index)")
        }
    }

    @Test("It draws what the same content drawn whole draws, at its alignment and spacing",
          arguments: [(HorizontalAlignment.leading, 1), (.trailing, 0)])
    func drawsWhatTheWholeContentDraws(_ alignment: HorizontalAlignment, _ spacing: Int) {
        let lazy = Self.twin(lazy: true, alignment: alignment, spacing: spacing)
        let whole = Self.twin(lazy: false, alignment: alignment, spacing: spacing)
        // The screen without the scroll bar's column.
        func content(_ app: TestApp) -> [String] { app.screen.lines.map { String($0.prefix(29)) } }
        func check(_ step: String) {
            #expect(content(lazy) == content(whole), "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
        check("top")
        for page in 1...3 {
            for app in [lazy, whole] { _ = app.press(.pageDown) }
            check("page \(page)")
        }
        for app in [lazy, whole] { _ = app.press(.end) }
        check("end")
    }

    @Test("The header is on the first line, and End reaches the last row")
    func headerAndEnd() {
        let app = Self.app(rows: 10_000, builds: Builds())
        #expect(app.screen.lines.first?.hasPrefix("header") == true, "\(app.screen)")
        _ = app.press(.end)
        #expect(app.screen.contains("r9999"), "\(app.screen)")
    }
}
