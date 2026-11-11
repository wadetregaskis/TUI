//  🖥️ TUI — A Terminal UI framework for Swift
//  HoverFocusChromeTests.swift
//
//  With the focus following the pointer: the menu bar is no focus stop, so
//  the pointer passing over a closed menu's title opens nothing and takes
//  nothing; with a menu open the pointer switches menus and lights items as it
//  always did, and the page behind keeps its focus. A text editor typed in
//  keeps the keys, as a text field does (owner ruling HOVER-FOCUS b,
//  2026-11-10).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("With the focus following the pointer, the menu bar and a text editor")
struct HoverFocusChromeTests {
    /// What the menus' items ran, for one test's app alone.
    final class Log {
        var ran: [String] = []
    }

    private struct MenusApp: App {
        let log: Log
        init() { log = Log() }
        init(log: Log) { self.log = log }

        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Button("PageA") {}.focusID("a")
                    Button("PageB") {}.focusID("b")
                    Spacer()
                }
            }
            .commandsRemoved()
            .commands {
                CommandMenu("Alpha") {
                    Button("A1") { log.ran.append("a1") }
                }
                CommandMenu("Beta") {
                    Button("B1") { log.ran.append("b1") }
                    Button("B2") { log.ran.append("b2") }
                }
            }
            .focusFollowsPointer()
        }
    }

    /// The cell `offset` columns into `text`, where it first shows from row
    /// `from` on.
    private func cell(_ app: TestApp, _ text: String, from: Int = 0, offset: Int = 0) throws -> CellPoint {
        let lines = app.screen.lines
        let y = try #require(lines.indices.dropFirst(from).first { lines[$0].contains(text) }, "\(text) is on screen")
        let start = try #require(lines[y].range(of: text)).lowerBound
        return CellPoint(x: lines[y][..<start].count + offset, y: y)
    }

    private func shows(_ text: String, _ app: TestApp) -> Bool {
        app.screen.lines.dropFirst().contains { $0.contains(text) }
    }

    @Test("A closed menu's title under the pointer opens nothing and takes no focus")
    func closedTitle() throws {
        let app = TestApp(MenusApp(), width: 40, height: 12)
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, "PageB"))
        #expect(app.focusedID == "b")
        app.hover(at: try cell(app, "Beta"))
        app.hover(at: try cell(app, "Beta", offset: 1))
        #expect(!shows("B1", app), "\(app.screen.lines)")
        #expect(app.focusedID == "b")
    }

    @Test("With a menu open the pointer switches menus and lights items; the page keeps its focus")
    func openMenu() throws {
        let log = Log()
        let app = TestApp(MenusApp(log: log), width: 40, height: 12)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "a")
        try app.click("Alpha")
        #expect(shows("A1", app))
        app.hover(at: try cell(app, "Beta"))
        #expect(shows("B1", app) && !shows("A1", app), "\(app.screen.lines)")
        app.hover(at: try cell(app, "B2", from: 1))
        app.hover(at: try cell(app, "B2", from: 1, offset: 1))
        // The page's controls under the menu's pointer take nothing while it is open.
        app.hover(at: try cell(app, "PageB", from: 1, offset: 1))
        #expect(shows("B1", app), "the menu closed: \(app.screen.lines)")
        app.hover(at: try cell(app, "B2", from: 1))
        _ = app.press(.enter)
        #expect(log.ran == ["b2"], "Return ran \(log.ran), not the item under the pointer")
        #expect(app.focusedID == "a", "the page's focus moved to \(app.focusedID ?? "nothing")")
    }

    private struct EditorApp: App {
        @State private var notes = ""
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Button("Other") {}.focusID("other")
                    TextEditor(text: $notes).focusID("editor").frame(height: 3)
                    Spacer()
                }
            }
            .focusFollowsPointer()
        }
    }

    @Test("A text editor the pointer crossed gives the focus up; one typed in keeps it")
    func editorKeepsFocus() throws {
        let app = TestApp(EditorApp(), width: 40, height: 10)
        app.advance(by: .milliseconds(20))
        let other = try cell(app, "Other")
        let editor = CellPoint(x: 2, y: other.y + 2)
        app.hover(at: editor)
        #expect(app.focusedID == "editor")
        app.hover(at: other)
        #expect(app.focusedID == "other", "a crossed editor kept the focus")
        app.hover(at: CellPoint(x: editor.x + 1, y: editor.y))
        #expect(app.focusedID == "editor")
        app.type("x")
        app.hover(at: CellPoint(x: other.x + 1, y: other.y))
        #expect(app.focusedID == "editor", "what is typed next goes where the typing was")
    }
}
