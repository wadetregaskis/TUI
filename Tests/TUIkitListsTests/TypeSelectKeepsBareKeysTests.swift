//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeSelectKeepsBareKeysTests.swift
//
//  Where type select exists, bare keys never pass to shortcuts (the owner's
//  ruling B77-KEYTIME, 2026-10-23): a focused list's type select takes every
//  character it takes, whether or not a row answers to it — TUIkit's own `q`
//  and `t`, an app's bare shortcut and a status-bar item's key among them —
//  and the status bar stops advertising those keys while it does. Played
//  through the input handler's whole chain.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Type select keeps bare keys")
struct TypeSelectKeepsBareKeysTests {
    private struct Look: Cyclable {
        let id: String
        let name: String
    }

    private final class Fixture {
        let statusBar = StatusBarState()
        let focus = FocusManager()
        let palette = ThemeManager(items: [Look(id: "p1", name: "p1"), Look(id: "p2", name: "p2")])
        let shortcuts = KeyboardShortcutRegistry()
        let list = ItemListHandler<Int>(
            focusID: "list", itemCount: 3, viewportHeight: 3, selectionMode: .single, canBeFocused: true)
        var quits = 0
        lazy var input = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: KeyEventDispatcher(),
            focusManager: focus,
            paletteManager: palette,
            appearanceManager: ThemeManager(items: [Look(id: "a1", name: "a1")]),
            keyboardShortcuts: shortcuts,
            dragAndDropSession: nil,
            onQuit: { [weak self] in self?.quits += 1 },
            onSuspend: {})

        init() {
            statusBar.showThemeItem = true
            statusBar.focusManager = focus
            focus.register(list)
            focus.focus(list)
        }
    }

    @Test("A first character TUIkit binds is type select's, not its binding's")
    func tuikitsBareKeysAreTypeSelects() {
        let fixture = Fixture()
        #expect(fixture.input.handle(KeyEvent(key: .character("q"))))
        #expect(fixture.quits == 0)
        #expect(fixture.list.pendingTypeSelect == "q")
        let before = fixture.palette.current.id
        #expect(fixture.input.handle(KeyEvent(key: .character("t"))))
        #expect(fixture.palette.current.id == before, "t did not cycle the theme")
    }

    @Test("An app's bare shortcut does not take its key from type select")
    func appShortcutKeepsNothing() {
        let fixture = Fixture()
        var fired = 0
        fixture.shortcuts.register(KeyboardShortcut("k", modifiers: [])) { fired += 1 }
        #expect(fixture.input.handle(KeyEvent(key: .character("k"))))
        #expect(fired == 0)
        #expect(fixture.list.pendingTypeSelect == "k")
    }

    @Test("A modified key still reaches its shortcut")
    func modifiedKeyPasses() {
        let fixture = Fixture()
        var fired = 0
        fixture.shortcuts.register(KeyboardShortcut("k", modifiers: .control)) { fired += 1 }
        _ = fixture.input.handle(KeyEvent(key: .character("k"), ctrl: true))
        #expect(fired == 1)
        #expect(fixture.list.pendingTypeSelect == nil)
    }

    @Test("A status-bar item's bare key neither fires nor shows while the list has the focus, and does once it has not")
    func statusBarItemsStandAside() {
        let fixture = Fixture()
        var fired = 0
        fixture.statusBar.setItemsSilently([
            StatusBarItem(shortcut: "n", label: "new") { fired += 1 },
            StatusBarItem(shortcut: "x", label: "info"),
        ])
        let shown = { fixture.statusBar.currentItems.map(\.shortcut) }
        #expect(shown() == ["x"], "the action item and q, t leave; the informational item stays")
        #expect(fixture.input.handle(KeyEvent(key: .character("n"))))
        #expect(fired == 0)
        #expect(fixture.list.pendingTypeSelect == "n")
        fixture.focus.unregister(fixture.list)
        #expect(shown().contains("n") && shown().contains("q") && shown().contains("t"))
        #expect(fixture.input.handle(KeyEvent(key: .character("n"))))
        #expect(fired == 1)
    }
}
