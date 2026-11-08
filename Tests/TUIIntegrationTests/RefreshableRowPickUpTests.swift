//  🖥️ TUI — A Terminal UI framework for Swift
//  RefreshableRowPickUpTests.swift
//
//  `.refreshable` binds ⌃R, and so does a reorderable list's row pick-up
//  (`RowAction.pickUpRow`) and a `.draggable` view's carry. The refresh is a
//  view key handler, asked before the focus system where the list's own keys
//  live, and it took every ⌃R: in a refreshable list a row could never be
//  picked up from the keyboard. The focused control now has the key first, as
//  the view nearest the focus answers first elsewhere, and the refresh runs
//  when it lets the key go.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Refreshable and a focused control's ⌃R")
struct RefreshableRowPickUpTests {

    private final class Counter {
        var refreshes = 0
    }

    private struct ReorderableList: View {
        let counter: Counter
        @State private var items = ["alpha", "beta", "gamma"]

        var body: some View {
            List {
                ForEach(items, id: \.self) { Text(verbatim: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .refreshable { counter.refreshes += 1 }
            .frame(height: 6)
        }
    }

    private func rows(_ app: TestApp) -> [String] {
        app.screen.lines.compactMap { line in
            ["alpha", "beta", "gamma"].first { line.contains($0) }
        }
    }

    @Test("⌃R on a focused reorderable list picks the row up and does not refresh")
    func listPicksUp() async {
        let counter = Counter()
        let app = TestApp(width: 30, height: 8) { ReorderableList(counter: counter) }
        #expect(app.focusedID != nil, "the list took the focus")
        app.press(KeyEvent(key: .character("r"), ctrl: true))
        app.press(KeyEvent(key: .down))
        app.press(KeyEvent(key: .enter))
        await yieldToSpawnedWork()
        #expect(rows(app) == ["beta", "alpha", "gamma"], "\(app.screen.lines)")
        #expect(counter.refreshes == 0)
    }

    @Test("⌃R that no focused control takes still refreshes")
    func refreshStillReachable() async {
        let counter = Counter()
        let app = TestApp(width: 30, height: 8) {
            VStack {
                Button("press") {}
                Text("content")
            }
            .refreshable { counter.refreshes += 1 }
        }
        app.press(KeyEvent(key: .character("r"), ctrl: true))
        await settle(until: { counter.refreshes == 1 })
        #expect(counter.refreshes == 1)
    }
}
