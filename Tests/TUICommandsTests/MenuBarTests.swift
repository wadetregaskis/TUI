//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarTests.swift
//
//  A scene that declares commands has a menu bar on the window's top row, and
//  its commands' shortcuts work with every menu closed, reading the focused
//  view's value of the frame they are pressed after.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUIPresentation
import TUITesting

// MARK: - Fixtures

/// What the commands did, reachable from an `App`.
private final class MenuBarProbe: @unchecked Sendable {
    static let shared = MenuBarProbe()
    var log: [String] = []
}

private struct NoteKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    fileprivate var menuBarNote: String? {
        get { self[NoteKey.self] }
        set { self[NoteKey.self] = newValue }
    }
}

/// Commands of the app's own type that act on the focused view's note.
private struct NoteCommands: Commands {
    @FocusedValue(\.menuBarNote) private var note

    var body: some Commands {
        CommandMenu("Note") {
            Button("Show") { MenuBarProbe.shared.log.append("show \(note ?? "none")") }
                .keyboardShortcut("s", modifiers: .control)
            Button("Gone") { MenuBarProbe.shared.log.append("gone") }
                .keyboardShortcut("g", modifiers: .control)
                .disabled(true)
        }
    }
}

/// Commands whose item is enabled by the focused view's note alone — the
/// pattern `Commands`' documentation teaches.
private struct GatedNoteCommands: Commands {
    @FocusedValue(\.menuBarNote) private var note

    var body: some Commands {
        CommandMenu("Note") {
            Button("Show") { MenuBarProbe.shared.log.append("show \(note ?? "none")") }
                .disabled(note == nil)
        }
    }
}

/// A view on the page that reads the focused view's note.
private struct NoteReader: View {
    @FocusedValue(\.menuBarNote) private var note

    var body: some View { Text("note: \(note ?? "none")") }
}

/// Two buttons, each publishing a note while it has the focus.
private struct NotesPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Button("A") {}.focusedValue(\.menuBarNote, "a")
            Button("B") {}.focusedValue(\.menuBarNote, "b")
        }
    }
}

private struct BareApp: App {
    init() {}
    var body: some Scene { WindowGroup { NotesPage() } }
}

/// The scene's own commands taken away, so the bar is Note's alone.
private struct CommandsApp: App {
    init() {}
    var body: some Scene { WindowGroup { NotesPage() }.commandsRemoved().commands { NoteCommands() } }
}

/// The gated commands, over the notes and a reader of them at the foot of the
/// page, out from under the open menu.
private struct GatedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                NotesPage()
                Spacer()
                NoteReader()
            }
        }
        .commandsRemoved()
        .commands { GatedNoteCommands() }
    }
}

/// The page binds the command's key itself.
private struct PageKeyApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") { MenuBarProbe.shared.log.append("page") }
                .keyboardShortcut("s", modifiers: .control)
        }
        .commands { NoteCommands() }
    }
}

/// A sheet over the page.
private struct SheetApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { NotesPage().sheet(isPresented: .constant(true)) { Text("SHEET") } }
            .commands { NoteCommands() }
    }
}

/// ``SheetApp`` with no sheet.
private struct UnsheetedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { NotesPage() }
            .commands { NoteCommands() }
    }
}

/// Two modifiers' menus, the scene's own commands taken away.
private struct TwoModifiersApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commandsRemoved()
            .commands { CommandMenu("Alpha") {} }
            .commands { CommandMenu("Beta") {} }
    }
}

private struct RemovedApp: App {
    init() {}
    var body: some Scene { WindowGroup { Text("PAGE") }.commands { CommandMenu("Alpha") {} }.commandsRemoved() }
}

private struct RemovedInsideApp: App {
    init() {}
    var body: some Scene { WindowGroup { Text("PAGE") }.commandsRemoved().commands { CommandMenu("Alpha") {} } }
}

private struct ReplacedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commands { CommandMenu("Alpha") {} }
            .commandsReplaced { CommandMenu("Beta") {} }
    }
}

/// A menu bar over a boxed top bar, the scene's own commands taken away.
private struct BarsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("PAGE").toolbar { ToolbarItem(placement: .navigation) { Text("HEADER") } }
        }
        .commandsRemoved()
        .commands { CommandMenu("Note") {} }
    }
}

// MARK: - Tests

@MainActor
@Suite("The menu bar", .serialized)
struct MenuBarTests {

    /// `app` after two frames — the second adopts any toolbar the first
    /// declared — as its rows, stripped.
    private func screen(_ app: TestApp) -> [String] {
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app.screen.lines
    }

    @Test("Declaring commands gives the window a menu bar on its top row; a bare scene has none")
    func menuBarRow() {
        let bare = screen(TestApp(BareApp(), width: 40, height: 8))
        #expect(!bare.contains { $0.contains("Note") }, "\(bare)")
        let rows = screen(TestApp(CommandsApp(), width: 40, height: 8))
        #expect(rows[0].hasPrefix(" Note"), "\(rows)")
        #expect(rows.count == 8)
    }

    @Test("Above a top bar, the menu bar takes the first row and the top bar the rows below it")
    func aboveTheTopBar() {
        let rows = screen(TestApp(BarsApp(), width: 30, height: 10))
        #expect(rows[0].hasPrefix(" Note"), "\(rows)")
        #expect(rows[1].hasPrefix("╭"), "the top bar's box opens on the row below: \(rows)")
        #expect(rows[2].contains("HEADER"), "\(rows)")
    }

    @Test("In a terminal too short for every bar, the menu bar keeps its row and the top bar gives way")
    func shortTerminal() {
        let rows = screen(TestApp(BarsApp(), width: 30, height: 2))
        #expect(rows.count == 2)
        #expect(rows[0].hasPrefix(" Note"), "\(rows)")
        #expect(rows[1].hasPrefix("╭"), "what is left of the top bar: \(rows)")
    }

    @Test("A command's shortcut works with its menu closed, reading the focused view's value of that frame")
    func shortcutReadsTheFocus() {
        MenuBarProbe.shared.log = []
        let app = TestApp(CommandsApp(), width: 40, height: 8)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .character("s"), ctrl: true))
        #expect(MenuBarProbe.shared.log == ["show a"])
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 20_000_000)
        app.send(KeyEvent(key: .character("s"), ctrl: true))
        #expect(MenuBarProbe.shared.log == ["show a", "show b"], "the frame after the focus moved reads B's note")
    }

    @Test("With a menu open, its commands and the page read the focused view's @FocusedValue, as before it opened")
    func openMenuReadsTheFocus() {
        MenuBarProbe.shared.log = []
        let app = TestApp(GatedApp(), width: 40, height: 10)
        var now: Int64 = 0
        func frame() {
            app.frame(atNanos: now)
            now += 20_000_000
        }
        frame()
        app.send(KeyEvent(key: .tab))
        frame()
        app.send(KeyEvent(key: .f10))
        frame()
        app.send(KeyEvent(key: .down))
        frame()
        frame()
        let asked = app.framesAsked
        frame()
        frame()
        let rows = app.screen.lines
        #expect(rows.dropFirst().contains { $0.contains("Show") }, "the menu is open: \(rows)")
        #expect(rows.contains { $0.contains("note: b") }, "the page's reader still reads B's note: \(rows)")
        #expect(app.framesAsked == asked, "no reading goes stale while the menu is open")
        app.send(KeyEvent(key: .enter))
        #expect(MenuBarProbe.shared.log == ["show b"], "the item is enabled by B's note, and reads it: \(rows)")
    }

    @Test("A disabled command's shortcut does nothing")
    func disabledCommand() {
        MenuBarProbe.shared.log = []
        let app = TestApp(CommandsApp(), width: 40, height: 8)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .character("g"), ctrl: true))
        #expect(MenuBarProbe.shared.log.isEmpty)
    }

    @Test("The page's own shortcut on a command's key is asked first")
    func pageShortcutWins() {
        MenuBarProbe.shared.log = []
        let app = TestApp(PageKeyApp(), width: 40, height: 8)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .character("s"), ctrl: true))
        #expect(MenuBarProbe.shared.log == ["page"])
    }

    @Test("While a modal holds the input, no command's shortcut fires from behind it")
    func inertUnderAModal() {
        MenuBarProbe.shared.log = []
        let app = TestApp(SheetApp(), width: 40, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        #expect(app.screen.contains("SHEET"), "sanity: the sheet is up")
        app.send(KeyEvent(key: .character("s"), ctrl: true))
        #expect(MenuBarProbe.shared.log.isEmpty)
    }

    /// The owner, 2026-10-28: the bar must look disabled when it is.
    @Test("While a modal holds the input, the bar's titles are drawn faint, as a disabled control's are")
    func dimmedUnderAModal() {
        let sheeted = TestApp(SheetApp(), width: 40, height: 10)
        sheeted.frame(atNanos: 0)
        sheeted.frame(atNanos: 20_000_000)
        let plain = TestApp(UnsheetedApp(), width: 40, height: 10)
        plain.frame(atNanos: 0)
        plain.frame(atNanos: 20_000_000)
        #expect(sheeted.screen.styledLines[0].stripped == plain.screen.styledLines[0].stripped, "the same titles")
        #expect(
            sheeted.screen.styledLines[0] != plain.screen.styledLines[0],
            "drawn in another ink: \(sheeted.screen.styledLines[0].debugDescription) vs \(plain.screen.styledLines[0].debugDescription)")
    }

    @Test("Commands of several modifiers add up, the innermost first")
    func modifiersAddUp() {
        let rows = screen(TestApp(TwoModifiersApp(), width: 40, height: 6))
        #expect(rows[0].hasPrefix(" Alpha  Beta"), "\(rows)")
    }

    @Test("commandsRemoved takes away the commands inside it, and commands outside it stay")
    func removed() {
        let removed = screen(TestApp(RemovedApp(), width: 40, height: 6))
        #expect(!removed.contains { $0.contains("Alpha") }, "no menu bar: \(removed)")
        let outside = screen(TestApp(RemovedInsideApp(), width: 40, height: 6))
        #expect(outside[0].hasPrefix(" Alpha"), "\(outside)")
    }

    @Test("commandsReplaced puts its commands in place of those inside it")
    func replaced() {
        let rows = screen(TestApp(ReplacedApp(), width: 40, height: 6))
        #expect(rows[0].hasPrefix(" Beta"), "\(rows)")
        #expect(!rows[0].contains("Alpha"), "\(rows)")
    }
}
