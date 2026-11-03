//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneRootLanguageChromeTests.swift
//
//  The app's language is the root `\.locale` of its scene (the owner's
//  A-APPSTATE-1, confirmed 2026-11-02), and what TUI's chrome reads: the status
//  bar's labels, the menu bar's and an undo title follow the scene's locale,
//  whatever locale a subtree states for its own words.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// A page whose one button has done something undoable once pressed, named as a
/// control names its undo step: with a word read in the event, no locale in hand.
private struct UndoablePage: View {
    @Environment(\.undoManager) private var undoManager
    @State private var presses = 0

    var body: some View {
        Button(localized: LocalizationKey.Button.cancel) {
            let before = presses
            presses += 1
            undoManager?.registerRestoring(
                $presses, to: before, actionName: LocalizationService.shared.string(for: LocalizationKey.Button.delete))
        }
        .statusBarItems([StatusBarItem(shortcut: "s", label: LocalizationService.shared.string(for: LocalizationKey.Button.save)) {}])
        .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
    }
}

private struct GermanApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { UndoablePage() }
            .commands { CommandMenu("Note") {} }
            .environment(\.locale, Locale(identifier: "de_DE"))
    }
}

/// The scene in German, the page in French.
private struct FrenchPageApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { UndoablePage().environment(\.locale, Locale(identifier: "fr_FR")) }
            .commands { CommandMenu("Note") {} }
            .environment(\.locale, Locale(identifier: "de_DE"))
    }
}

private struct UnstatedApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { UndoablePage() }
            .commands { CommandMenu("Note") {} }
    }
}

@MainActor
@Suite("The status bar, the menu bar and undo titles read the scene's root locale", .serialized, .rendersEnglishUI)
struct SceneRootLanguageChromeTests {
    /// What the app shows with its button pressed once: the page and bars, then the
    /// open Edit menu.
    private func shown(_ app: some App) -> (page: String, menu: String) {
        let app = TestApp(app, width: 72, height: 16)
        app.headless.adoptUndoManager()
        var now: Int64 = 0
        func frame() {
            now += 20_000_000
            app.frame(atNanos: now)
        }
        func screen() -> String { app.screen.lines.joined(separator: "\n") }
        frame()
        frame()
        app.send(KeyEvent(key: .enter))
        frame()
        frame()
        let page = screen()
        app.send(KeyEvent(key: .f10))
        frame()
        app.send(KeyEvent(key: .right))
        frame()
        app.send(KeyEvent(key: .down))
        frame()
        return (page, screen())
    }

    @Test("A scene in German has its bars and undo title in German")
    func german() {
        let (page, menu) = shown(GermanApp())
        #expect(page.contains("Bearbeiten"), "the menu bar: \(page)")
        #expect(page.contains("Speichern"), "the status bar's page item: \(page)")
        #expect(page.contains("widerrufen"), "the status bar's undo item: \(page)")
        #expect(page.contains("Abbrechen"), "the page: \(page)")
        #expect(menu.contains("Widerrufen Löschen"), "the undo title: \(menu)")
    }

    @Test("A subtree's locale has its own words, and changes none of those")
    func subtree() {
        let (page, menu) = shown(FrenchPageApp())
        #expect(page.contains("Annuler"), "the subtree's button: \(page)")
        #expect(page.contains("Bearbeiten"), "the menu bar: \(page)")
        #expect(page.contains("Speichern"), "the status bar's page item: \(page)")
        #expect(page.contains("widerrufen"), "the status bar's undo item: \(page)")
        #expect(menu.contains("Widerrufen Löschen"), "the undo title: \(menu)")
    }

    @Test("A scene that states no locale has the process's language")
    func unstated() {
        let (page, menu) = shown(UnstatedApp())
        #expect(page.contains("Edit"), "the menu bar: \(page)")
        #expect(page.contains("Save"), "the status bar's page item: \(page)")
        #expect(page.contains("undo"), "the status bar's undo item: \(page)")
        #expect(menu.contains("Undo Delete"), "the undo title: \(menu)")
    }
}
