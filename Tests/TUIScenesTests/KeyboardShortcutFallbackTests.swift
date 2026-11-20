//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutFallbackTests.swift
//
//  `keyboardShortcutFallback(_:)`: a control's second key, bound beside its
//  shortcut and named only where the terminal cannot send the shortcut (the
//  owner, 2026-11-19).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
@testable import TUIScenes
import TUITesting

// MARK: - Fixtures

@MainActor
private final class Presses {
    var preview = 0
    var wraps = false
}

/// ⇧⌘P, which a legacy encoding sends without its Shift, with ⌥⌘P beside it.
private let shortcut = KeyboardShortcut("p", modifiers: [.command, .shift])
private let fallback = KeyboardShortcut("p", modifiers: [.command, .option])

private struct PreviewMenuApp: App {
    let presses: Presses
    init() { presses = Presses() }
    init(presses: Presses) { self.presses = presses }
    var body: some Scene {
        WindowGroup { WrapPage(presses: presses) }
            .commands {
                CommandMenu("Panels") {
                    Button("Show Preview") { presses.preview += 1 }
                        .keyboardShortcut(shortcut)
                        .keyboardShortcutFallback(fallback)
                }
            }
            .aboutPanel(applicationName: "Notes")
    }
}

/// A toggle on ⇧⌘W, with ⌥⌘W beside it.
private struct WrapPage: View {
    let presses: Presses

    var body: some View {
        Toggle("Wrap", isOn: Binding(get: { presses.wraps }, set: { presses.wraps = $0 }))
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .keyboardShortcutFallback("w", modifiers: [.command, .option])
    }
}

// MARK: - Tests

@MainActor
@Suite("A control's fallback key", .serialized)
struct KeyboardShortcutFallbackTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched(_ presses: Presses, reporting: KeyboardReporting) -> TestApp {
        let app = TestApp(PreviewMenuApp(presses: presses), width: 60, height: 30)
        frame(app)
        app.keyboardReporting = reporting
        frame(app)
        frame(app)
        return app
    }

    /// The Panels menu's Show Preview row, the menu closed again: F10, Right
    /// to Panels (after the app menu), Down.
    private mutating func previewRow(_ app: TestApp) -> String {
        let titles = app.screen.lines[0].split(separator: " ").map(String.init)
        let index = titles.firstIndex(of: "Panels") ?? 0
        app.send(KeyEvent(key: .f10))
        frame(app)
        for _ in 0..<index {
            app.send(KeyEvent(key: .right))
            frame(app)
        }
        app.send(KeyEvent(key: .down))
        frame(app)
        let row = app.screen.lines.first { $0.contains("Show Preview") } ?? app.screen.lines.joined(separator: "\n")
        app.send(KeyEvent(key: .escape))
        frame(app)
        return row
    }

    /// The rows of F1's list, taken down again.
    private mutating func shortcutList(_ app: TestApp) -> [String] {
        app.send(KeyEvent(key: .f1))
        frame(app)
        let listed = app.screen.lines
        app.send(KeyEvent(key: .escape))
        frame(app)
        return listed
    }

    private var named: String { shortcut.resolved(commandKey: .control)!.displayString! }
    private var namedFallback: String { fallback.resolved(commandKey: .control)!.displayString! }

    @Test("Where the terminal sends the shortcut, the menu and F1's list name it, and not the fallback")
    mutating func shortcutNamed() {
        let app = launched(Presses(), reporting: KeyboardReporting(flags: .requested))
        let row = previewRow(app)
        #expect(row.contains(named) && !row.contains(namedFallback), "\(row)")
        let listed = shortcutList(app).filter { $0.contains("Show Preview") }
        #expect(listed.count == 1 && listed[0].contains(named), "\(listed)")
    }

    @Test("Where a legacy encoding loses the shortcut's Shift, the menu and F1's list name the fallback")
    mutating func fallbackNamedUnderLegacy() {
        let app = launched(Presses(), reporting: .legacy)
        let row = previewRow(app)
        #expect(row.contains(namedFallback) && !row.contains(named), "\(row)")
        let listed = shortcutList(app).filter { $0.contains("Show Preview") }
        #expect(listed.count == 1 && listed[0].contains(namedFallback), "\(listed)")
    }

    @Test("Where the terminal keeps the shortcut for itself, the fallback is named even under the kitty protocol")
    mutating func fallbackNamedWhereKept() {
        let app = launched(
            Presses(),
            reporting: KeyboardReporting(
                flags: .requested, keptChords: [shortcut.resolved(commandKey: .control)!.trigger]))
        let row = previewRow(app)
        #expect(row.contains(namedFallback) && !row.contains(named), "\(row)")
    }

    @Test("Both keys run a button's action, and flip a toggle")
    mutating func bothKeysBound() throws {
        let presses = Presses()
        let app = launched(presses, reporting: KeyboardReporting(flags: .requested))
        app.send(try #require(shortcut.keyEvent(commandKey: .control)))
        frame(app)
        app.send(try #require(fallback.keyEvent(commandKey: .control)))
        frame(app)
        #expect(presses.preview == 2)

        let wrap = KeyboardShortcut("w", modifiers: [.command, .shift])
        let wrapFallback = KeyboardShortcut("w", modifiers: [.command, .option])
        app.send(try #require(wrap.keyEvent(commandKey: .control)))
        frame(app)
        #expect(presses.wraps)
        app.send(try #require(wrapFallback.keyEvent(commandKey: .control)))
        frame(app)
        #expect(!presses.wraps)
    }
}
