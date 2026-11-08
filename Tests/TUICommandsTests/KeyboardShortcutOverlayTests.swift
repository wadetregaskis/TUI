//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutOverlayTests.swift
//
//  The list F1 shows: what it lists, how it scrolls and goes away, that an
//  app's own F1 comes first, and that an app that turned it off gets F1 itself.
//  In a real app, through the real input chain.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
import TUICore
@testable import TUIFoundation
import TUIPresentation
import TUITesting
import TUITextInput

// MARK: - Fixtures

/// What the fixtures' keys did, reachable from an `App`.
private final class Heard: @unchecked Sendable {
    static let shared = Heard()
    var f1 = 0
    var save = 0
    var text = ""
    var sheetShown = false

    func reset() {
        f1 = 0
        save = 0
        text = ""
        sheetShown = false
    }
}

private let f1Equivalent = KeyEquivalent("\u{F704}")

/// A page with a shortcut of each kind, under a menu bar.
private struct FullApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("Save") { Heard.shared.save += 1 }.keyboardShortcut("s", modifiers: .control)
                Button {
                } label: {
                    Text("Drawn Label")
                }
                .keyboardShortcut("l", modifiers: .control)
                Button("Off Button") {}.keyboardShortcut("o", modifiers: .control).disabled(true)
                Toggle("Wrap Lines", isOn: .constant(true)).keyboardShortcut("w", modifiers: [.control, .option])
                Button("Page Wins") {}.keyboardShortcut("d", modifiers: .control)
            }
            .statusBarItems([StatusBarItem(shortcut: "x", label: "Export") {}])
        }
        .commands {
            CommandMenu("Note") {
                Button("Archive") {}.keyboardShortcut("r", modifiers: .control)
                Button("Menu Loses") {}.keyboardShortcut("d", modifiers: .control)
            }
        }
    }
}

/// A window scene with a key, which the Window menu shows, under a menu bar.
private struct WindowsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("Main") }
            .commands { CommandMenu("Note") {} }
        Window("Other", id: "other") { Text("Other") }.keyboardShortcut("y", modifiers: .control)
    }
}

/// The same with no menu bar: the key is bound all the same.
private struct BareWindowsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("Main") }
        Window("Other", id: "other") { Text("Other") }.keyboardShortcut("y", modifiers: .control)
    }
}

/// A plain page with no menu bar.
private struct PlainApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Save") {}.keyboardShortcut("s", modifiers: .control)
        }
    }
}

/// A page with more shortcuts than a short window shows.
private struct LongApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack {
                ForEach(Array("abcdefgnpqrtuy"), id: \.self) { letter in
                    Button("Command " + String(letter)) {}.keyboardShortcut(KeyEquivalent(letter), modifiers: .control)
                }
            }
        }
    }
}

/// F1 on an `onKeyPress` of the focused view's.
private struct KeyPressApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") {}
                .onKeyPress(f1Equivalent) {
                    Heard.shared.f1 += 1
                    return .handled
                }
        }
        .commands { CommandMenu("Note") {} }
    }
}

/// F1 on an `onKeyEvent` of the page's.
private struct KeyEventApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") {}
                .onKeyEvent { event in
                    guard event.key == .f1 else { return false }
                    Heard.shared.f1 += 1
                    return true
                }
        }
    }
}

/// F1 on a `.keyboardShortcut`, spelled as SwiftUI source spells it.
private struct ShortcutApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Own Help") { Heard.shared.f1 += 1 }.keyboardShortcut(f1Equivalent, modifiers: [])
        }
        .commands { CommandMenu("Note") {} }
    }
}

/// F1 on a status-bar item.
private struct StatusItemApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") {}
                .statusBarItems([StatusBarItem(shortcut: "F1", label: "own", key: .f1) { Heard.shared.f1 += 1 }])
        }
    }
}

/// The list turned off, with and without something of the app's on F1.
private struct OffApp: App {
    nonisolated(unsafe) static var hears = false
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") {}
                .onKeyEvent { event in
                    guard unsafe Self.hears, event.key == .f1 else { return false }
                    Heard.shared.f1 += 1
                    return true
                }
        }
        .commands { CommandMenu("Note") {} }
        .keyboardShortcutOverlayDisabled()
    }
}

/// A sheet up over a page, each with a shortcut.
private struct SheetApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Behind") {}
                .keyboardShortcut("b", modifiers: .control)
                .sheet(isPresented: .constant(true)) {
                    Button("In Sheet") {}.keyboardShortcut("i", modifiers: [.control, .option])
                }
        }
    }
}

/// A focused text field.
private struct FieldApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TextField("Name", text: Binding(get: { Heard.shared.text }, set: { Heard.shared.text = $0 }))
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("The keyboard shortcut list on F1", .serialized)
struct KeyboardShortcutOverlayTests {
    private let heading = "Keyboard Shortcuts"

    private func launched<A: App>(_ app: A, width: Int = 80, height: Int = 40) -> TestApp {
        Heard.shared.reset()
        let app = TestApp(app, width: width, height: height)
        app.advance(by: .milliseconds(40))
        return app
    }

    /// `key`, with the frames it takes to be drawn.
    @discardableResult
    private func press(_ event: KeyEvent, in app: TestApp) -> Bool {
        let taken = app.press(event)
        app.advance(by: .milliseconds(40))
        return taken
    }

    private let f1 = KeyEvent(key: .f1)

    /// The screen row showing `text`.
    private func row(_ text: String, in app: TestApp) -> String? {
        app.screen.text.split(separator: "\n").map(String.init).first { $0.contains(text) }
    }

    // MARK: What it lists

    @Test("F1 lists the page's shortcuts, by the button's words or its drawn label, and the toggle's")
    func listsThePage() throws {
        let app = launched(FullApp())
        #expect(!app.screen.contains(heading))
        press(f1, in: app)
        #expect(app.screen.contains(heading))
        #expect(app.screen.contains("On This Screen"))
        let save = try #require(row("Save", in: app))
        #expect(save.contains("⌃S"))
        let drawn = try #require(row("Drawn Label", in: app))
        #expect(drawn.contains("⌃L"))
        let toggle = try #require(row("Wrap Lines", in: app))
        #expect(toggle.contains("⌃⌥W"))
    }

    @Test("It lists the menu bar's commands under their menus, and the scene's own")
    func listsTheMenus() throws {
        let app = launched(FullApp())
        press(f1, in: app)
        #expect(app.screen.contains("Note"))
        let archive = try #require(row("Archive", in: app))
        #expect(archive.contains("⌃R"))
        // A hint: the quit key, which a menu row shows and the chain binds.
        #expect(row("Quit", in: app)?.contains("⌃Q") == true)
        // F10 enters the bar, which is no shortcut, but is in force.
        #expect(row("Menu Bar", in: app)?.contains("F10") == true)
    }

    @Test("It lists the status bar's items and TUI's own keys, each key once")
    func listsTheBarAndGeneral() throws {
        let app = launched(FullApp())
        press(f1, in: app)
        #expect(app.screen.contains("Status Bar"))
        #expect(row("Export", in: app) != nil)
        #expect(app.screen.contains("General"))
        #expect(row("Next Control", in: app)?.contains("⇥") == true)
        #expect(row("Keyboard Shortcuts", in: app) != nil)
        let quits = app.screen.text.split(separator: "\n").filter { $0.contains("⌃Q") }
        #expect(quits.count == 1, "\(quits)")
    }

    @Test("A scene's key is listed under the menu item that shows it, and without a menu bar on the screen's")
    func sceneKeys() throws {
        let app = launched(WindowsApp())
        press(f1, in: app)
        let lines = app.screen.text.split(separator: "\n").map(String.init)
        let scene = try #require(lines.firstIndex { $0.contains("⌃Y") })
        let menu = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Window") })
        #expect(menu < scene, "\(lines)")
        #expect(!lines.contains { $0.contains("On This Screen") }, "\(lines)")

        let bare = launched(BareWindowsApp())
        press(f1, in: bare)
        #expect(bare.screen.contains("On This Screen"))
        #expect(row("Other", in: bare)?.contains("⌃Y") == true)
    }

    @Test("Close's key isn't listed where it would close nothing")
    func closeWithOneWindow() {
        let app = launched(BareWindowsApp())
        press(f1, in: app)
        #expect(row("Close", in: app) == nil)
    }

    @Test("A disabled control isn't listed: its key isn't in force")
    func disabledIsNotListed() {
        let app = launched(FullApp())
        press(f1, in: app)
        #expect(row("Off Button", in: app) == nil)
    }

    @Test("A key the page and a menu both bind lists the page's, which is what it fires")
    func shadowedMenuCommand() {
        let app = launched(FullApp())
        press(f1, in: app)
        #expect(row("Page Wins", in: app) != nil)
        #expect(row("Menu Loses", in: app) == nil)
    }

    @Test("With no menu bar, there's no menu to list and no F10")
    func noMenuBar() {
        let app = launched(PlainApp())
        press(f1, in: app)
        #expect(row("Save", in: app) != nil)
        #expect(row("Menu Bar", in: app) == nil)
    }

    @Test("Over a sheet it lists the sheet's shortcuts, and goes away leaving the sheet up")
    func overASheet() {
        let app = launched(SheetApp())
        press(f1, in: app)
        #expect(row("In Sheet", in: app)?.contains("⌃⌥I") == true)
        #expect(!app.screen.text.contains("⌃B"))
        press(KeyEvent(key: .escape), in: app)
        #expect(!app.screen.contains(heading))
        #expect(app.screen.contains("In Sheet"))
    }

    // MARK: Going away, and scrolling

    @Test("Escape takes it down, the page's focus back")
    func escapeDismisses() {
        let app = launched(FullApp())
        let focused = app.focusedID
        press(f1, in: app)
        #expect(app.focusedID != focused)
        press(KeyEvent(key: .escape), in: app)
        #expect(!app.screen.contains(heading))
        #expect(app.focusedID == focused)
    }

    @Test("F1 takes it down again")
    func f1Dismisses() {
        let app = launched(FullApp())
        press(f1, in: app)
        #expect(app.screen.contains(heading))
        press(f1, in: app)
        #expect(!app.screen.contains(heading))
    }

    @Test("Done takes it down, by click and by Return")
    func doneDismisses() throws {
        let app = launched(PlainApp())
        press(f1, in: app)
        try app.click("Done")
        app.advance(by: .milliseconds(40))
        #expect(!app.screen.contains(heading))
    }

    @Test("A repeat of F1 neither shows nor hides it, and goes no further")
    func heldKey() {
        let app = launched(FullApp())
        #expect(press(KeyEvent(key: .f1, phase: .repeat), in: app))
        #expect(!app.screen.contains(heading))
        press(f1, in: app)
        #expect(press(KeyEvent(key: .f1, phase: .repeat), in: app))
        #expect(app.screen.contains(heading))
    }

    @Test("Too long for the window, the arrows and paging keys scroll it")
    func scrolls() {
        let app = launched(LongApp(), width: 60, height: 14)
        press(f1, in: app)
        #expect(app.screen.contains("Command a"))
        #expect(!app.screen.contains("Next Control"))
        for _ in 0..<4 { press(KeyEvent(key: .pageDown), in: app) }
        #expect(app.screen.contains("Next Control"))
        #expect(!app.screen.contains("Command a"))
        press(KeyEvent(key: .up), in: app)
        press(KeyEvent(key: .escape), in: app)
        #expect(!app.screen.contains(heading))
    }

    @Test("It holds the keyboard: the page's shortcut doesn't fire under it")
    func holdsTheKeyboard() {
        let app = launched(FullApp())
        press(f1, in: app)
        press(KeyEvent(key: .character("s"), ctrl: true), in: app)
        #expect(Heard.shared.save == 0)
    }

    @Test("F1 in a focused text field shows it and types nothing")
    func inATextField() {
        let app = launched(FieldApp())
        press(f1, in: app)
        #expect(app.screen.contains(heading))
        #expect(Heard.shared.text.isEmpty)
    }

    // MARK: An app's own F1

    @Test("An onKeyPress on F1 comes first, and the Help menu still shows the list")
    func onKeyPressWins() {
        let app = launched(KeyPressApp())
        press(f1, in: app)
        #expect(Heard.shared.f1 == 1)
        #expect(!app.screen.contains(heading))
        chooseKeyboardShortcuts(in: app)
        #expect(app.screen.contains(heading))
    }

    @Test("An onKeyEvent on F1 comes first")
    func onKeyEventWins() {
        let app = launched(KeyEventApp())
        press(f1, in: app)
        #expect(Heard.shared.f1 == 1)
        #expect(!app.screen.contains(heading))
    }

    @Test("A keyboardShortcut on F1 comes first, and the Help menu doesn't claim the key")
    func shortcutWins() {
        let app = launched(ShortcutApp())
        press(f1, in: app)
        #expect(Heard.shared.f1 == 1)
        #expect(!app.screen.contains(heading))
        openHelp(in: app)
        #expect(row(heading, in: app)?.contains("F1") == false)
    }

    @Test("A status-bar item on F1 comes first")
    func statusItemWins() {
        let app = launched(StatusItemApp())
        press(f1, in: app)
        #expect(Heard.shared.f1 == 1)
        #expect(!app.screen.contains(heading))
    }

    @Test("A tooltip help key moved to F1 comes first")
    func helpKeyWins() {
        var handler = chain()
        handler.tooltipState = TooltipState()
        handler.tooltipState?.helpKey = .f1
        _ = handler.handle(KeyEvent(key: .f1))
        #expect(handler.shortcutOverlay?.isPresented == false)
    }

    // MARK: Turned off

    @Test("Turned off, F1 reaches what the app binds on it")
    func offReachesTheApp() {
        unsafe OffApp.hears = true
        let app = launched(OffApp())
        #expect(press(f1, in: app))
        #expect(Heard.shared.f1 == 1)
        #expect(!app.screen.contains(heading))
    }

    @Test("Turned off with nothing on it, F1 goes unanswered, and there's no menu item")
    func offIsUnanswered() {
        unsafe OffApp.hears = false
        let app = launched(OffApp())
        #expect(press(f1, in: app) == false)
        #expect(!app.screen.contains(heading))
        openHelp(in: app)
        #expect(!app.screen.contains(heading))
        #expect(app.screen.contains("Show Tooltips"))
    }

    // MARK: The Help menu

    @Test("Help ▸ Keyboard Shortcuts shows F1, and lists the page's keys, not the menu's")
    func helpMenuItem() throws {
        let app = launched(FullApp())
        openHelp(in: app)
        let item = try #require(row(heading, in: app))
        #expect(item.contains("F1"))
        chooseKeyboardShortcuts(alreadyOpen: true, in: app)
        #expect(app.screen.contains(heading))
        #expect(row("Save", in: app) != nil)
        #expect(row("Archive", in: app) != nil)
    }

    // MARK: Helpers

    /// F10, then Down to open the first menu, and Left round to Help, the bar's
    /// last.
    private func openHelp(in app: TestApp) {
        press(KeyEvent(key: .f10), in: app)
        press(KeyEvent(key: .down), in: app)
        press(KeyEvent(key: .left), in: app)
    }

    /// Chooses Help ▸ Keyboard Shortcuts, the menu's first item, and waits out
    /// the frame that closes the menu.
    private func chooseKeyboardShortcuts(alreadyOpen: Bool = false, in app: TestApp) {
        if !alreadyOpen { openHelp(in: app) }
        press(KeyEvent(key: .enter), in: app)
        app.advance(by: .milliseconds(40))
    }

    /// An input chain of its own, for what an app's scene can't set.
    private func chain() -> InputHandler {
        let tui = TUIContext()
        return InputHandler(
            statusBar: StatusBarState(), keyEventDispatcher: tui.keyEventDispatcher, focusManager: FocusManager(),
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts, dragAndDropSession: nil,
            shortcutOverlay: KeyboardShortcutOverlay(requestFrame: {}), onQuit: {}, onSuspend: {})
    }
}

// MARK: - What arrives

@Suite("The bytes F1 arrives as")
struct F1ArrivalTests {
    @Test("F1's legacy forms read as F1, with no Shift", arguments: ["\u{1B}OP", "\u{1B}[1;1P"])
    func legacy(_ bytes: String) {
        let event = KeyEvent.parse(Array(bytes.utf8))
        #expect(event?.key == .f1, "\(bytes.debugDescription) read as \(String(describing: event))")
        #expect(event?.shift == false)
    }

    @Test(
        "F1's kitty keyboard protocol forms read as F1, with no Shift",
        arguments: ["\u{1B}[P", "\u{1B}[1P", "\u{1B}[1;1P", "\u{1B}[1;1:1P", "\u{1B}[11~"])
    func kitty(_ bytes: String) {
        let decoded = KittyKeyDecoder.decode(Array(bytes.utf8))
        guard case .key(let event)? = decoded?.first else {
            Issue.record("\(bytes.debugDescription) read as \(String(describing: decoded))")
            return
        }
        #expect(event.key == .f1)
        #expect(!event.shift)
    }
}
