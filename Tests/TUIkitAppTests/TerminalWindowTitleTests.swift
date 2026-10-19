//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalWindowTitleTests.swift
//
//  The terminal's window title (refusal review P15; decisions O9, B-O9-13):
//  the window in front's scene title, or a root `.navigationTitle` no top bar
//  shows; written when it changes, the terminal's own saved before the first
//  and given back for a window with none, and on the hand-back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation

// MARK: - Fixtures

private struct TitledApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Notes") { Text("notes window") }
        Window("Inspector", id: "inspector") { Text("inspector window") }
        WindowGroup(id: "untitled") { Text("untitled window") }
    }
}

private struct UntitledApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("plain window") }
    }
}

/// A root navigation title, with no bar to show it.
private struct NavigationTitledApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Mail") {
            Text("inbox").navigationTitle("Inbox")
        }
    }
}

/// A root navigation title the top bar shows.
private struct BarTitledApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Mail") {
            Text("inbox")
                .navigationTitle("Inbox")
                .toolbar { ToolbarItem(placement: .primaryAction) { Text("NEW") } }
        }
    }
}

/// A title with controls in it.
private struct UnsafeTitleApp: App {
    init() {}
    var body: some Scene {
        WindowGroup(verbatimTitle) { Text("window") }
    }

    private var verbatimTitle: String { "Bell\u{07}\u{1B}]0;pwned\u{1B}\\Line\nTwo" }
}

// MARK: - Tests

@MainActor
@Suite("The terminal's window title", .serialized)
struct TerminalWindowTitleTests {
    private var now: Int64 = 0

    private static let save = "\u{1B}[22;2t"
    private static let restore = "\u{1B}[23;2t"

    private static func set(_ title: String) -> String { "\u{1B}]2;\(title)\u{1B}\\" }

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

    @Test("A window group's title titles the terminal once, the terminal's own saved first")
    mutating func sceneTitle() {
        let app = launched(TitledApp())
        #expect(app.hostWrites == [Self.save + Self.set("Notes")])
        #expect(app.terminalWindowTitle == "Notes")
    }

    @Test("An app with no title leaves the terminal's title alone")
    mutating func noTitleNoWrites() {
        let app = launched(UntitledApp())
        #expect(app.hostWrites.isEmpty)
        #expect(app.terminalWindowTitle == nil)
    }

    @Test("The window in front titles the terminal; closing it gives the title back to the window behind")
    mutating func frontWindowTitles() {
        let app = launched(TitledApp())
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        #expect(app.terminalWindowTitle == "Inspector")
        app.scenes.close([app.scenes.windows.last!.serial])
        frame(app)
        #expect(app.hostWrites == [Self.save + Self.set("Notes"), Self.set("Inspector"), Self.set("Notes")])
    }

    @Test("A window with no title in front gives the terminal its own title back")
    mutating func untitledWindowRestores() {
        let app = launched(TitledApp())
        app.scenes.open(WindowTarget(id: "untitled"))
        frame(app)
        #expect(app.terminalWindowTitle == nil)
        #expect(app.hostWrites.last == Self.restore)
    }

    @Test("A root navigation title no top bar shows titles the terminal, over the scene's")
    mutating func navigationTitleWithoutBar() {
        let app = launched(NavigationTitledApp())
        #expect(app.terminalWindowTitle == "Inbox", "\(app.hostWrites)")
    }

    @Test("A root navigation title the top bar shows leaves the terminal the scene's")
    mutating func navigationTitleInBar() {
        let app = launched(BarTitledApp())
        #expect(app.screen.map(\.stripped).joined().contains("Inbox"), "\(app.screen.map(\.stripped))")
        #expect(app.terminalWindowTitle == "Mail", "\(app.hostWrites)")
    }

    @Test("Handing the terminal back restores its title, and the next frame sets the app's again")
    mutating func handBack() {
        let app = launched(TitledApp())
        app.handBackHostState()
        frame(app)
        #expect(app.hostWrites == [Self.save + Self.set("Notes"), Self.restore, Self.save + Self.set("Notes")])
    }

    @Test("A title cannot end its sequence early: its control characters are dropped and its line breaks spaced")
    mutating func sanitisedTitle() {
        let app = launched(UnsafeTitleApp())
        #expect(app.terminalWindowTitle == "Bell]0;pwned\\Line Two")
        #expect(app.hostWrites.count == 1)
        #expect(app.hostWrites.first?.filter { $0 == "\u{1B}" }.count == 3, "the save, the OSC and its ST: no more")
    }
}
