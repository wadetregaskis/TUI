//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBarOwnCommandsTests.swift
//
//  The scene's own commands: the app's menu (About, Quit) and the Edit
//  menu's Undo, Redo, Cut, Copy and Paste, each doing what its key does, and
//  `commandsRemoved()` taking them away.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitCommands
@testable import TUIkitFoundation
import TUIkitPresentation
import TUIkitTextInput

// MARK: - Fixtures

/// What the page heard, reachable from an `App`.
private final class OwnCommandsProbe: @unchecked Sendable {
    static let shared = OwnCommandsProbe()
    var log: [String] = []
}

/// A focused button that hears the quit key and the Copy command.
private struct ListeningPage: View {
    var body: some View {
        Button("Page") {}
            .onKeyPress("q") {
                OwnCommandsProbe.shared.log.append("q")
                return .ignored
            }
            .onCopyCommand {
                OwnCommandsProbe.shared.log.append("copy")
                return []
            }
    }
}

/// A focused text field, which types whatever key it is given.
private struct FieldApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TextField("Field", text: Binding(get: { "" }, set: { OwnCommandsProbe.shared.log.append("typed \($0)") }))
        }
        .commands { CommandMenu("Note") {} }
    }
}

private struct OwnApp: App {
    init() {}
    var body: some Scene { WindowGroup { ListeningPage() }.commands { CommandMenu("Note") {} } }
}

private struct RemovedOwnApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { ListeningPage() }.commandsRemoved().commands { CommandMenu("Note") {} }
    }
}

private struct ReplacedQuitApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { ListeningPage() }
            .commands {
                CommandGroup(replacing: .appTermination) { Button("Leave") { OwnCommandsProbe.shared.log.append("leave") } }
            }
    }
}

// MARK: - Tests

@MainActor
@Suite("The scene's own commands", .serialized)
struct MenuBarOwnCommandsTests {
    private var now: Int64 = 0

    /// A fresh app after its first frame, its log cleared.
    private func launched<A: App>(_ app: A, undo: UndoManager? = nil) -> HeadlessApp<A> {
        OwnCommandsProbe.shared.log = []
        let headless = HeadlessApp(app, width: 60, height: 14)
        if let undo { headless.services.undoManager = undo }
        headless.frame(atNanos: 0)
        return headless
    }

    /// Renders a frame after `app`'s last.
    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func rows<A: App>(_ app: HeadlessApp<A>) -> [String] { app.screen.map(\.stripped) }

    /// Opens the menu at `title` from the keyboard and chooses its item at
    /// `downs` places past the first, drawing a frame between each step.
    private mutating func choose<A: App>(_ title: Int, item downs: Int, in app: HeadlessApp<A>) {
        app.send(KeyEvent(key: .f10))
        frame(app)
        for _ in 0..<title {
            app.send(KeyEvent(key: .right))
            frame(app)
        }
        for _ in 0..<downs {
            app.send(KeyEvent(key: .down))
            frame(app)
        }
        app.send(KeyEvent(key: .enter))
        frame(app)
    }

    @Test("A scene that declares commands has the app's menu first and the Edit menu, before its own")
    func standardMenus() {
        let app = launched(OwnApp())
        let bar = rows(app)[0]
        #expect(bar.hasPrefix(" \(_MenuBarCore.appName)  Edit  Note"), "\(bar)")
    }

    @Test("Quit quits as the quit key does, and sends the focused view no key")
    mutating func quitQuits() {
        let app = launched(OwnApp())
        // The app's menu: About, then Quit.
        choose(0, item: 1, in: app)
        #expect(app.quitsRequested == 1, "\(rows(app))")
        #expect(OwnCommandsProbe.shared.log.isEmpty, "the page heard no q")
    }

    @Test("With a text field focused, Quit quits and types nothing")
    mutating func quitOverATextField() {
        let app = launched(FieldApp())
        frame(app)
        choose(0, item: 1, in: app)
        #expect(app.quitsRequested == 1, "\(rows(app))")
        #expect(OwnCommandsProbe.shared.log.isEmpty, "the field took no q: \(OwnCommandsProbe.shared.log)")
    }

    @Test("Copy is ⌘C to the focused view, through the scene's command key")
    mutating func copyIsTheCopyCommand() {
        let app = launched(OwnApp())
        // Edit, with no undo manager: Cut, Copy, Paste.
        choose(1, item: 1, in: app)
        #expect(OwnCommandsProbe.shared.log == ["copy"])
    }

    @Test("Undo undoes on the app's undo manager, showing the scene's undo key")
    mutating func undo() {
        let undo = UndoManager()
        final class Count: @unchecked Sendable { var value = 1 }
        let count = Count()
        let app = launched(OwnApp(), undo: undo)
        undo.registerUndo(withTarget: count) { $0.value = 0 }
        frame(app)
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .right))
        frame(app)
        #expect(rows(app).contains { $0.contains("Undo") && $0.contains("⌃Z") }, "\(rows(app))")
        app.send(KeyEvent(key: .enter))
        frame(app)
        #expect(count.value == 0)
    }

    @Test("With nothing to undo, Undo and Redo are disabled, and the highlight starts past them")
    mutating func nothingToUndo() {
        let app = launched(OwnApp(), undo: UndoManager())
        // Edit: Undo and Redo disabled, so the highlight starts on Cut, and one
        // Down is Copy.
        choose(1, item: 1, in: app)
        #expect(OwnCommandsProbe.shared.log == ["copy"])
    }

    @Test("About shows an alert naming the app")
    mutating func about() {
        let app = launched(OwnApp())
        choose(0, item: 0, in: app)
        frame(app)
        #expect(rows(app).dropFirst().contains { $0.contains(_MenuBarCore.appName) }, "\(rows(app))")
        #expect(rows(app).contains { $0.contains("OK") }, "\(rows(app))")
    }

    @Test("The app's menu takes no Alt letter: Alt-E is Edit's, whatever the app is called")
    mutating func appMenuHasNoLetter() {
        let app = launched(OwnApp())
        app.send(KeyEvent(key: .character(Character(_MenuBarCore.appName.prefix(1).lowercased())), alt: true))
        frame(app)
        #expect(!rows(app).dropFirst().contains { $0.contains("About") }, "\(rows(app))")
        app.send(KeyEvent(key: .escape))
        frame(app)
        app.send(KeyEvent(key: .character("e"), alt: true))
        frame(app)
        #expect(rows(app).contains { $0.contains("Copy") }, "\(rows(app))")
    }

    @Test("commandsRemoved takes the scene's own commands away")
    func removed() {
        let app = launched(RemovedOwnApp())
        let bar = rows(app)[0]
        #expect(bar.hasPrefix(" Note"), "\(bar)")
        #expect(!bar.contains("Edit"), "\(bar)")
    }

    @Test("A replacement takes Quit's place")
    mutating func replacedQuit() {
        let app = launched(ReplacedQuitApp())
        choose(0, item: 1, in: app)
        #expect(OwnCommandsProbe.shared.log == ["leave"])
    }
}
