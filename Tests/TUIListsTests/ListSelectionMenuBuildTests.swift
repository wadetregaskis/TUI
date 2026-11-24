//  🖥️ TUI — A Terminal UI framework for Swift
//  ListSelectionMenuBuildTests.swift
//
//  A list's `contextMenu(forSelectionType:menu:)` builds the app's menu only
//  while it is open: a closed menu's frames run the closure not at all, so
//  they neither pay for it nor observe what it reads (H-92, LISTS-7).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A list's selection menu is built while it is open")
struct ListSelectionMenuBuildTests {
    private final class Counter {
        var builds = 0

        /// The menu, counted each time it is built.
        func menu() -> some View {
            builds += 1
            return Button("Open") {}
        }
    }

    @Test("Frames with the menu closed run the menu closure not at all; opening it does")
    func closedMenuBuildsNothing() {
        let appState = AppState()
        let harness = InputChainHarness()
        let counter = Counter()
        var picked: Int? = 1
        let selection = Binding(get: { picked }, set: { picked = $0 })
        func view() -> some View {
            List(selection: selection) {
                ForEach(0..<5, id: \.self) { Text("row \($0)") }
            }
            .contextMenu(forSelectionType: Int.self) { _ in counter.menu() }
        }
        AmbientApp.$renderState.withValue(appState) {
            for _ in 0..<3 { harness.frame(view()) }
            #expect(counter.builds == 0)
            harness.press(KeyEvent(key: .f10, shift: true))
            harness.frame(view())
            #expect(counter.builds > 0)
        }
    }
}
