//  🖥️ TUI — A Terminal UI framework for Swift
//  FileCloseCommandsTests.swift
//
//  File ▸ Close (⌘W) and Close All (⌥⌘W), for an app that can have more than
//  one window open: the window in front, and every window that may close but
//  the one at the back. They come before a focused text field's Ctrl-W, its
//  word rubout, as every Command chord does (the owner, 2026-10-29, replacing
//  O9), and a key of the window's own content wins.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUIPresentation
import TUITesting
import TUITextInput

// MARK: - Fixtures

/// What the windows heard, reachable from an `App`.
private final class CloseProbe: @unchecked Sendable {
    static let shared = CloseProbe()
    var text = ""
    var saves = 0
}

/// The main window: a button that opens the welcome window.
private struct MainPage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("welcome") { openWindow(id: "welcome") }
    }
}

/// What the welcome window holds.
private enum WelcomeContent {
    case button
    case field
    case ownShortcut
}

private struct WelcomePage: View {
    let content: WelcomeContent

    var body: some View {
        switch content {
        case .button:
            Button("hello") {}
        case .field:
            TextField("Field", text: Binding(get: { CloseProbe.shared.text }, set: { CloseProbe.shared.text = $0 }))
        case .ownShortcut:
            Button("save") { CloseProbe.shared.saves += 1 }.keyboardShortcut("w")
        }
    }
}

private struct TwoWindowApp: App {
    let content: WelcomeContent

    init() { self.init(content: .button) }

    init(content: WelcomeContent) {
        self.content = content
    }

    var body: some Scene {
        WindowGroup { MainPage() }.commands { CommandMenu("Note") {} }
        Window("Welcome", id: "welcome") { WelcomePage(content: content) }
    }
}

/// An app with one window, which has nothing to close.
private struct OneWindowApp: App {
    init() {}
    var body: some Scene { WindowGroup { MainPage() }.commands { CommandMenu("Note") {} } }
}

private func ctrl(_ letter: Character, alt: Bool = false) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true, alt: alt)
}

// MARK: - Tests

@MainActor
@Suite("File ▸ Close and Close All", .serialized)
struct FileCloseCommandsTests {
    private var now: Int64 = 0

    /// The app with its welcome window opened over the main one.
    private mutating func welcoming(_ content: WelcomeContent) -> TestApp {
        CloseProbe.shared.text = ""
        CloseProbe.shared.saves = 0
        let app = TestApp(TwoWindowApp(content: content), width: 60, height: 14)
        app.frame(atNanos: 0)
        send(KeyEvent(key: .enter), to: app)
        frame(app)
        return app
    }

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func send(_ key: KeyEvent, to app: TestApp) {
        app.send(key)
        frame(app)
    }

    @Test("⌘W closes the window in front, and on the last window closes nothing")
    mutating func closeClosesTheFront() {
        let app = welcoming(.button)
        #expect(app.scenes.windows.count == 2)
        send(ctrl("w"), to: app)
        #expect(app.scenes.windows.count == 1)
        send(ctrl("w"), to: app)
        #expect(app.scenes.windows.count == 1, "the last window closed, which quits")
    }

    @Test("⌥⌘W closes every window but the one at the back")
    mutating func closeAllKeepsTheBack() {
        let app = welcoming(.button)
        let back = app.scenes.windows.first?.serial
        #expect(app.scenes.windowsCloseAllCloses.count == 1)
        send(ctrl("w", alt: true), to: app)
        #expect(app.scenes.windows.map(\.serial) == [back].compactMap { $0 })
        #expect(app.scenes.windowsCloseAllCloses.isEmpty, "Close All would close the last window")
    }

    @Test("Close takes Ctrl-W from a focused text field's word rubout")
    mutating func closeTakesControlWFromAField() {
        let app = welcoming(.field)
        for character in "ab cd" { send(KeyEvent(character: character), to: app) }
        #expect(CloseProbe.shared.text == "ab cd", "the field did not have the focus")
        send(ctrl("w"), to: app)
        #expect(CloseProbe.shared.text == "ab cd", "the field rubbed out a word as well")
        #expect(app.scenes.windows.count == 1, "Ctrl-W did not close the window from a text field")
    }

    @Test("A key of the window's own content wins over Close")
    mutating func ownShortcutWins() {
        let app = welcoming(.ownShortcut)
        send(ctrl("w"), to: app)
        #expect(CloseProbe.shared.saves == 1)
        #expect(app.scenes.windows.count == 2)
    }

    @Test("File holds Close and Close All, showing their keys")
    mutating func fileMenuShowsThem() {
        let app = welcoming(.button)
        send(KeyEvent(key: .f10), to: app)
        send(KeyEvent(key: .down), to: app)
        send(KeyEvent(key: .right), to: app)
        let screen = app.screen.lines.joined(separator: "\n")
        #expect(screen.contains("Close All"), "\(screen)")
    }

    @Test("An app with one window has no Close, and Ctrl-W does nothing")
    mutating func oneWindowHasNoClose() {
        let app = TestApp(OneWindowApp(), width: 60, height: 14)
        app.frame(atNanos: 0)
        #expect(!app.scenes.opensSeveralWindows)
        send(ctrl("w"), to: app)
        #expect(app.scenes.windows.count == 1)
    }
}
