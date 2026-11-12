//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewNaturalHeightTests.swift
//
//  Offered no height — a vertical scroll view's content, `.fixedSize` — a
//  split view is as tall as its tallest visible column. It answered one line:
//  in a scroll view it took the viewport's height, its sidebar's rows past it
//  out of reach, and under `.fixedSize` it was one line. Offered a height, it
//  still takes what it is given.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUINavigation
import TUITesting

/// The size the split came out at, by reference so the frame's closure reaches it.
@MainActor private final class SplitSize { var value: CellSize? }

@MainActor
@Suite("A split view offered no height is as tall as its tallest visible column")
struct NavigationSplitViewNaturalHeightTests {
    private static func rows(_ prefix: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(1...count, id: \.self) { Text("\(prefix)\($0)") }
        }
    }

    private static func split(
        sidebar: Int, detail: Int, visibility: NavigationSplitViewVisibility = .all, size: SplitSize
    ) -> some View {
        NavigationSplitView(columnVisibility: .constant(visibility)) {
            rows("Row ", sidebar)
        } detail: {
            rows("Detail ", detail)
        }
        .onGeometryChange(for: CellSize.self, of: { $0.size }, action: { size.value = $0 })
    }

    @Test("In a ScrollView a 60-row sidebar makes the split 60 lines, and the wheel reaches its last row")
    func scrollViewReachesTheSidebarsLastRow() {
        let size = SplitSize()
        let app = TestApp(width: 60, height: 24) {
            ScrollView { Self.split(sidebar: 60, detail: 1, size: size) }
        }
        let first = app.screen
        #expect(size.value?.height == 60, "\(first)")
        #expect(!first.contains("Row 60"))
        app.scroll(.down, by: 40, at: CellPoint(x: 30, y: 12))
        #expect(app.screen.contains("Row 60"), "\(app.screen)")
    }

    @Test("Under .fixedSize the split is its tallest column's height, not one line")
    func fixedSizeIsTheTallestColumn() {
        let size = SplitSize()
        let app = TestApp(width: 60, height: 24) {
            VStack {
                Text("title")
                Self.split(sidebar: 3, detail: 5, size: size)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        let screen = app.screen
        #expect(size.value?.height == 5, "\(screen)")
        #expect(screen.contains("Row 3") && screen.contains("Detail 5"), "\(screen)")
    }

    @Test("A hidden column's rows do not count: under .detailOnly the detail alone sets the height")
    func hiddenColumnDoesNotCount() {
        let size = SplitSize()
        let app = TestApp(width: 60, height: 24) {
            VStack {
                Text("title")
                Self.split(sidebar: 9, detail: 2, visibility: .detailOnly, size: size)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        let screen = app.screen
        #expect(size.value?.height == 2, "\(screen)")
    }

    /// Offered a height, the split takes it all, as it did: a VStack gives it
    /// the lines below its title, however tall its sidebar.
    @Test("Offered a height, the split takes what it is given, below a title that stays on screen")
    func boundedLayoutIsUnchanged() {
        let size = SplitSize()
        let app = TestApp(width: 60, height: 24) {
            VStack {
                Text("title")
                Self.split(sidebar: 60, detail: 1, size: size)
            }
        }
        let screen = app.screen
        #expect(size.value == CellSize(width: 60, height: 23), "\(screen)")
        #expect(screen.lines[0].contains("title"), "\(screen)")
        let short = SplitSize()
        let shortApp = TestApp(width: 60, height: 24) {
            VStack {
                Text("title")
                Self.split(sidebar: 3, detail: 1, size: short)
            }
        }
        let shortScreen = shortApp.screen
        #expect(short.value == CellSize(width: 60, height: 23), "\(shortScreen)")
    }
}
