//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeSelectGiveWayTests.swift
//
//  A focused list's type select gives the FIRST character of a prefix up to
//  an app shortcut or one of TUIkit's own bare keys that claims it — `q`
//  quits, `t` cycles the theme — and keeps every character once a prefix is
//  under way. Played through the input handler's whole chain.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitStyling

@MainActor
@Suite("Type select gives way")
struct TypeSelectGiveWayTests {
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
            focus.register(list)
            focus.focus(list)
        }
    }

    @Test("A first character TUIkit binds goes to its binding, not to type select")
    func boundFirstCharacterGivesWay() {
        let fixture = Fixture()
        _ = fixture.input.handle(KeyEvent(key: .character("q")))
        #expect(fixture.quits == 1)
        #expect(fixture.list.pendingTypeSelect == nil)
        let before = fixture.palette.current.id
        _ = fixture.input.handle(KeyEvent(key: .character("t")))
        #expect(fixture.palette.current.id != before, "t cycled the theme")
        #expect(fixture.list.pendingTypeSelect == nil)
    }

    @Test("An app's bare shortcut takes its key from type select")
    func appShortcutGivesWay() {
        let fixture = Fixture()
        var fired = 0
        fixture.shortcuts.register(KeyboardShortcut("k", modifiers: [])) { fired += 1 }
        _ = fixture.input.handle(KeyEvent(key: .character("k")))
        #expect(fired == 1)
        #expect(fixture.list.pendingTypeSelect == nil)
    }

    @Test("Any other character starts a prefix, and once one is under way every character continues it")
    func prefixUnderWayTakesEverything() {
        let fixture = Fixture()
        #expect(fixture.input.handle(KeyEvent(key: .character("x"))))
        #expect(fixture.list.pendingTypeSelect == "x")
        #expect(fixture.input.handle(KeyEvent(key: .character("q"))))
        #expect(fixture.list.pendingTypeSelect == "xq")
        #expect(fixture.quits == 0, "a prefix under way keeps the quit key")
    }
}
