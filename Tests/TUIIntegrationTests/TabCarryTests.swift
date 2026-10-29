//  🖥️ TUI — A Terminal UI framework for Swift
//  TabCarryTests.swift
//
//  A draggable tab from the keyboard (A53-KEYBOARD-DRAG): while the strip or
//  the sidebar holds the focus, Ctrl-R carries the selected tab's drag to a
//  destination that takes it, and Copy takes its payload — in every look.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

private final class Log: @unchecked Sendable {
    var selected = 2
    var dropped: [String] = []
    var selection: Binding<Int> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor
@Suite("A draggable tab carried from the keyboard")
struct TabCarryTests {
    /// A tab view whose second tab, selected, is draggable, above a bin.
    private func board(_ log: Log, _ look: TabInteractionsLook) -> some View {
        let tabs = TabView(selection: log.selection) {
            Tab("One", systemImage: "star", value: 1) { Text("first") }
            Tab("Two", systemImage: "star", value: 2) { Text("second") }
                .draggable("two")
        }
        return VStack(alignment: .leading) {
            Group {
                switch look {
                case .compact: tabs
                case .bordered: tabs.tabViewStyle(.bordered)
                case .sidebar: tabs.tabViewStyle(.sidebarAdaptable)
                }
            }
            .frame(height: 8)
            Text("BIN").dropDestination(for: String.self) { items, _ in
                log.dropped += items
                return true
            }
        }
    }

    @Test("Ctrl-R carries the selected tab, Tab takes it to the bin, Return drops it", arguments: TabInteractionsLook.allCases)
    func carriesTheSelectedTab(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { board(log, look) }
        #expect(consumed == [true, true, true])
        #expect(log.dropped == ["two"])
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("Copy copies the selected tab's payload", arguments: TabInteractionsLook.allCases)
    func copyTakesTheSelectedTab(look: TabInteractionsLook) {
        let clipboard = FakeClipboard()
        let typed = TypedClipboard()
        let harness = InputChainHarness(width: 50, height: 14) {
            $0.clipboardAccess = clipboard.access
            $0.typedClipboard = typed
        }
        let log = Log()
        let consumed = harness.play([KeyEvent(key: .character("c"), ctrl: true)]) { board(log, look) }
        #expect(consumed == [true])
        #expect(clipboard.writes == ["two"])
    }
}
