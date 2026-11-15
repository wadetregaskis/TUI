//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyLetterCaseSurfacesTests.swift
//
//  Every place a key is drawn — the status bar, a menu's shortcut column and
//  the F1 list of shortcuts — writes a letter pressed alone as a capital by
//  default and in lower case under `.asTyped`, and a key that needs Shift as
//  `⇧K` in both (the owner's APPFB-4, 2026-11-14). Set once, on the scene.
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

/// A page with a status bar holding a bare letter and a Shift letter, under a
/// menu holding the same two kinds, in `letterCase`, set on the scene.
private struct LettersApp: App {
    let letterCase: KeyLetterCase

    init() { self.init(.capital) }

    init(_ letterCase: KeyLetterCase) {
        self.letterCase = letterCase
    }

    var body: some Scene {
        WindowGroup {
            Text("Main")
                .statusBarItems([
                    StatusBarItem(shortcut: "g", label: "signal") {},
                    StatusBarItem(shortcut: "T", label: "terminate") {},
                ])
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
        .commandsRemoved()
        .commands {
            CommandMenu("Process") {
                Button("Pause") {}.keyboardShortcut("p", modifiers: [])
                Button("Resume") {}.keyboardShortcut("r", modifiers: .shift)
            }
        }
        .environment(\.keyLetterCase, letterCase)
    }
}

@MainActor
@Suite("A key's letter case, wherever a key is drawn")
struct KeyLetterCaseSurfacesTests {
    private func launched(_ letterCase: KeyLetterCase) -> TestApp {
        let app = TestApp(LettersApp(letterCase), width: 80, height: 30)
        app.advance(by: .milliseconds(40))
        return app
    }

    private func press(_ event: KeyEvent, in app: TestApp) {
        app.press(event)
        app.advance(by: .milliseconds(40))
    }

    /// The screen row showing `text`, its frame and padding trimmed away.
    private func row(_ text: String, in app: TestApp) -> String? {
        app.screen.text.split(separator: "\n").map(String.init).first { $0.contains(text) }
    }

    /// The menu row showing `label`, its border and padding trimmed away.
    private func menuRow(_ label: String, in app: TestApp) -> String? {
        row(label, in: app).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " │┃|")) }
    }

    @Test("By default a bare letter is a capital and Shift is ⇧, in the bar, the menu and the F1 list")
    func capitals() throws {
        let app = launched(.capital)
        let bar = try #require(row("signal", in: app))
        #expect(bar.contains("G signal") && bar.contains("⇧T terminate"), "the bar: \(bar)")

        press(KeyEvent(key: .f10), in: app)
        press(KeyEvent(key: .down), in: app)
        let pause = try #require(menuRow("Pause", in: app))
        let resume = try #require(menuRow("Resume", in: app))
        #expect(pause.hasSuffix(" P") && resume.hasSuffix(" ⇧R"), "the menu: \(pause) / \(resume)")
        press(KeyEvent(key: .escape), in: app)
        press(KeyEvent(key: .escape), in: app)

        press(KeyEvent(key: .f1), in: app)
        let listed = app.screen.text
        for line in ["G  signal", "⇧T  terminate", "P  Pause", "⇧R  Resume"] {
            #expect(listed.contains(line), "F1 lists \(line): \(listed)")
        }
    }

    @Test("As typed, a bare letter is lower case and Shift is still ⇧, in the bar, the menu and the F1 list")
    func asTyped() throws {
        let app = launched(.asTyped)
        let bar = try #require(row("signal", in: app))
        #expect(bar.contains("g signal") && bar.contains("⇧T terminate"), "the bar: \(bar)")

        press(KeyEvent(key: .f10), in: app)
        press(KeyEvent(key: .down), in: app)
        let pause = try #require(menuRow("Pause", in: app))
        let resume = try #require(menuRow("Resume", in: app))
        #expect(pause.hasSuffix(" p") && resume.hasSuffix(" ⇧R"), "the menu: \(pause) / \(resume)")
        press(KeyEvent(key: .escape), in: app)
        press(KeyEvent(key: .escape), in: app)

        press(KeyEvent(key: .f1), in: app)
        let listed = app.screen.text
        for line in ["g  signal", "⇧T  terminate", "p  Pause", "⇧R  Resume"] {
            #expect(listed.contains(line), "F1 lists \(line): \(listed)")
        }
    }
}
