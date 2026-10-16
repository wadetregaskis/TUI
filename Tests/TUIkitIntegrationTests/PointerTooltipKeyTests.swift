//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PointerTooltipKeyTests.swift
//
//  A key press sends the pointer's tooltip away until the pointer moves, as on
//  a Mac — except the help key, which asks for help.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("A key and the pointer's tooltip")
struct PointerTooltipKeyTests {
    private struct Fixture {
        let handler: InputHandler
        let tooltips: TooltipState
    }

    /// A minimal ``Cyclable``: `ThemeManager` preconditions on a non-empty list.
    private struct FakeCyclable: Cyclable {
        let id: String
        let name: String
    }

    private func makeFixture() -> Fixture {
        let appState = AppState()
        let tooltips = TooltipState()
        let handler = InputHandler(
            statusBar: StatusBarState(appState: appState),
            keyEventDispatcher: KeyEventDispatcher(),
            focusManager: FocusManager(),
            paletteManager: ThemeManager(items: [FakeCyclable(id: "p", name: "p")]),
            appearanceManager: ThemeManager(items: [FakeCyclable(id: "a", name: "a")]),
            keyboardShortcuts: KeyboardShortcutRegistry(),
            dragAndDropSession: nil,
            tooltipState: tooltips,
            onQuit: {}, onSuspend: {})
        return Fixture(handler: handler, tooltips: tooltips)
    }

    /// As on a Mac: a reader who has started using the keyboard is not reading
    /// the help of the view the pointer happens to rest on. Kept, a toolbar
    /// button's "Hide Sidebar" stayed in the status bar while Tab moved the
    /// focus round the page.
    @Test("A key sends the pointer's tooltip away until the pointer moves")
    func keySilencesThePointerTooltip() {
        let fixture = makeFixture()
        fixture.tooltips.hovering("Hide Sidebar", handlerID: nil, nowNanos: 0)
        #expect(fixture.tooltips.resolved(nowNanos: 0)?.source == .hover)
        #expect(fixture.handler.silencePointerTooltip(for: KeyEvent(key: .tab)), "a frame is owed")
        #expect(fixture.tooltips.resolved(nowNanos: 0) == nil, "the tooltip went with the key")
        #expect(!fixture.handler.silencePointerTooltip(for: KeyEvent(key: .tab)), "nothing more to send away")
        #expect(fixture.tooltips.notePointerMoved(), "the move that brings it back owes a frame")
        #expect(fixture.tooltips.resolved(nowNanos: 0)?.text == "Hide Sidebar", "back once the pointer moved")
    }

    /// The help key asks for help, so it is the one key that does not send it
    /// away — it reveals the focused view's, and the pointer's still wins.
    @Test("The help key leaves the pointer's tooltip where it is")
    func helpKeyKeepsThePointerTooltip() {
        let fixture = makeFixture()
        fixture.tooltips.hovering("Hide Sidebar", handlerID: nil, nowNanos: 0)
        #expect(!fixture.handler.silencePointerTooltip(for: KeyEvent(key: .character("?"))))
        #expect(fixture.tooltips.resolved(nowNanos: 0)?.text == "Hide Sidebar")
    }
}
