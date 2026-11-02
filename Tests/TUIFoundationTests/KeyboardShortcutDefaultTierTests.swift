//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutDefaultTierTests.swift
//
//  Shortcuts the framework registers for itself (a split view's sidebar chord)
//  sit in a tier below the app's. Under the default `.commandKey(.control)`,
//  SwiftUI's ⌃⌘S and an app's plain ⌘S resolve to the same trigger, ⌃S, and the
//  registry's last-registration-wins rule would hand the app's Save to whichever
//  registered later in render order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Framework-default shortcuts yield to the app's")
struct KeyboardShortcutDefaultTierTests {

    private let controlS = KeyEvent(key: .character("s"), ctrl: true)

    /// Records which registered action ran.
    private final class Log {
        var ran: [String] = []
    }

    @Test("An app shortcut registered BEFORE a default on the same key wins")
    func appBeforeDefault() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.register(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("app") }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["app"])
    }

    @Test("An app shortcut registered AFTER a default on the same key wins")
    func appAfterDefault() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        registry.register(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("app") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["app"])
    }

    @Test("A default fires when no app shortcut has the key")
    func defaultAlone() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.register(KeyboardShortcut("d", modifiers: .control)) { log.ran.append("app") }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["default"])
    }

    @Test("Of two defaults on one key, the first registered wins")
    func firstDefaultWins() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("first") }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("second") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["first"])
    }

    @Test("A default registered by a view holding the focus beats earlier and later ones that do not")
    func focusedDefaultWins() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        let shortcut = KeyboardShortcut("s", modifiers: .control)
        registry.registerDefault(shortcut) { log.ran.append("unfocused first") }
        registry.registerDefault(shortcut, holdsFocus: true) { log.ran.append("focused") }
        registry.registerDefault(shortcut, holdsFocus: true) { log.ran.append("focused second") }
        registry.registerDefault(shortcut) { log.ran.append("unfocused last") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["focused"])
    }

    @Test("A new render pass clears the defaults too")
    func beginRenderPassClears() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        registry.beginRenderPass()
        #expect(!registry.trigger(for: controlS))
        #expect(log.ran.isEmpty)
    }
}

@MainActor
@Suite("A shortcut on a function key")
struct KeyboardShortcutFunctionKeyTests {
    /// `NSF1FunctionKey`, which is how SwiftUI source names F1.
    private let f1 = KeyboardShortcut(KeyEquivalent("\u{F704}"), modifiers: [])

    @Test("AppKit's scalar for a function key names it, drawn as itself")
    func namedAndDrawn() {
        #expect(f1.displayString == "F1")
        #expect(KeyboardShortcut(KeyEquivalent("\u{F70D}"), modifiers: .shift).displayString == "⇧F10")
    }

    @Test("It fires on its key, and not with a modifier the shortcut doesn't state")
    func fires() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(f1) { fired += 1 }
        #expect(registry.trigger(for: KeyEvent(key: .f1)))
        #expect(fired == 1)
        #expect(registry.trigger(for: KeyEvent(key: .f1, shift: true)) == false)
        #expect(registry.trigger(for: KeyEvent(key: .f2)) == false)
    }

    @Test("onKeyPress reports the same scalars it always did, and the Menu key")
    func keyPress() {
        #expect(KeyPress(KeyEvent(key: .f1))?.key == KeyEquivalent("\u{F704}"))
        #expect(KeyPress(KeyEvent(key: .f20))?.key == KeyEquivalent("\u{F717}"))
        #expect(KeyPress(KeyEvent(key: .menu))?.key == KeyEquivalent("\u{F735}"))
    }
}
