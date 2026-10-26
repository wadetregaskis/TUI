//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneKeyboardShortcutTests.swift
//
//  `Scene.keyboardShortcut`: the key that opens a scene's window — a
//  `Window`'s, opened or brought to the front; a new one of a window group —
//  with the menus closed or no menu bar at all, through `commandKey`, and
//  below the window's own shortcut on the same key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation

// MARK: - Fixtures

private struct ShortcutApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        Window("Library", id: "library") { Text("library window") }
            .keyboardShortcut("o")
        WindowGroup("Note", id: "note") { Text("note window") }
            .keyboardShortcut("y", modifiers: [.command, .shift])
    }
}

/// What the main window's own shortcut did.
private final class OwnKeyProbe: @unchecked Sendable {
    static let shared = OwnKeyProbe()
    var pressed = 0
}

/// A window whose content binds the key a scene states.
private struct ClashingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("own") { OwnKeyProbe.shared.pressed += 1 }
                .keyboardShortcut("o")
        }
        Window("Library", id: "library") { Text("library window") }
            .keyboardShortcut("o")
    }
}

// MARK: - Tests

@MainActor
@Suite("Scenes' keyboard shortcuts", .serialized)
struct SceneKeyboardShortcutTests {
    private var now: Int64 = 0

    private mutating func launched<A: App>(_ app: A) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: 50, height: 10)
        frame(headless)
        frame(headless)
        return headless
    }

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    /// Presses `character` with Control — ⌘ through the default `commandKey`
    /// — and Shift if `shift`, which a terminal reports with the letter's
    /// capital, and draws.
    private mutating func press<A: App>(_ character: Character, shift: Bool = false, in app: HeadlessApp<A>) {
        let typed = shift ? Character(character.uppercased()) : character
        app.send(KeyEvent(key: .character(typed), ctrl: true, shift: shift))
        frame(app)
        frame(app)
    }

    private func screen<A: App>(_ app: HeadlessApp<A>) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    @Test("A Window's key opens its window, and brings it to the front: one window")
    mutating func windowKey() {
        let app = launched(ShortcutApp())
        press("o", in: app)
        #expect(screen(app).contains("library window"), "\(screen(app))")
        app.scenes.open(WindowTarget(id: "note"))
        frame(app)
        press("o", in: app)
        #expect(screen(app).contains("library window"), "\(screen(app))")
        #expect(app.scenes.windows.count == 3)
    }

    @Test("A window group's key opens a new window of it each time, its modifiers resolved through commandKey")
    mutating func groupKey() {
        let app = launched(ShortcutApp())
        press("y", shift: true, in: app)
        #expect(screen(app).contains("note window"), "\(screen(app))")
        press("y", shift: true, in: app)
        #expect(app.scenes.windows.count == 3)
        press("y", in: app)
        #expect(app.scenes.windows.count == 3, "without Shift it is another key")
    }

    @Test("The window's own shortcut on the same key keeps it")
    mutating func contentKeepsItsKey() {
        OwnKeyProbe.shared.pressed = 0
        let app = launched(ClashingApp())
        press("o", in: app)
        #expect(OwnKeyProbe.shared.pressed == 1)
        #expect(app.scenes.windows.count == 1, "\(screen(app))")
    }

    @Test("A scene with no key stated has none: an app's window groups have no ⌘N")
    mutating func noDefaultKey() {
        let app = launched(ShortcutApp())
        press("n", in: app)
        #expect(app.scenes.windows.count == 1, "\(screen(app))")
    }
}
