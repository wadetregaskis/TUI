//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusFollowsPointerTests.swift
//
//  `Scene.focusFollowsPointer(_:)` and `TUI_FOCUS_FOLLOWS_POINTER`: the
//  focusable control the pointer moves onto takes the focus — not from an edit,
//  not out of a sheet, not while a menu is open, and never by a pointer at rest.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Focus follows the pointer")
struct FocusFollowsPointerTests {
    private struct Page: View {
        @State private var text = ""

        var body: some View {
            VStack(alignment: .leading) {
                Button("One") {}.focusID("one")
                Button("Two") {}.focusID("two")
                TextField("Name", text: $text)
                Button("Inert") {}.focusID("inert").disabled(true)
            }
        }
    }

    private struct FollowingApp: App {
        let follows: Bool
        init() { follows = true }
        init(follows: Bool) { self.follows = follows }

        var body: some Scene {
            WindowGroup { Page() }
                .focusFollowsPointer(follows)
        }
    }

    private struct PlainApp: App {
        var body: some Scene {
            WindowGroup { Page() }
        }
    }

    /// The cell `offset` columns into `text`, where it first shows.
    private func cell(_ app: TestApp, _ text: String, offset: Int = 0) throws -> CellPoint {
        let lines = app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains(text) }, "\(text) is on screen")
        let start = try #require(lines[y].range(of: text)).lowerBound
        return CellPoint(x: lines[y][..<start].count + offset, y: y)
    }

    @Test("Only `1` and `0` say anything")
    func variable() {
        #expect(TerminalClient.focusFollowsPointerRequested(environment: ["TUI_FOCUS_FOLLOWS_POINTER": "1"]) == true)
        #expect(TerminalClient.focusFollowsPointerRequested(environment: ["TUI_FOCUS_FOLLOWS_POINTER": "0"]) == false)
        #expect(TerminalClient.focusFollowsPointerRequested(environment: ["TUI_FOCUS_FOLLOWS_POINTER": "yes"]) == nil)
        #expect(TerminalClient.focusFollowsPointerRequested(environment: [:]) == nil)
    }

    @Test("Off unless asked: the pointer only hovers", arguments: [false, true])
    func offByDefault(stated: Bool) throws {
        let app = stated ? TestApp(FollowingApp(follows: false)) : TestApp(PlainApp())
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "one")
        app.hover(at: try cell(app, "Two"))
        #expect(app.focusedID == "one")
    }

    private struct QuietApp: App {
        let follows: Bool?
        let support: MouseSupport
        init() {
            follows = nil
            support = .standard
        }
        init(follows: Bool?, support: MouseSupport) {
            self.follows = follows
            self.support = support
        }

        var body: some Scene {
            WindowGroup { Text("Nothing here asks for the pointer") }
                .mouseSupport(support)
                .focusFollowsPointer(follows ?? false)
        }
    }

    @Test(
        "On, the terminal reports motion, but only where it reports clicks",
        arguments: [(true, MouseSupport.standard, true), (false, .standard, false), (true, .scrollOnly, false)])
    func motion(follows: Bool, support: MouseSupport, reported: Bool) {
        let app = TestApp(QuietApp(follows: follows, support: support))
        app.advance(by: .milliseconds(20))
        #expect(app.services.mouseEventDispatcher.frameFinalSupport.motion == reported)
    }

    @Test("On, a move onto a control focuses it")
    func moveFocuses() throws {
        let app = TestApp(FollowingApp())
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, "Two"))
        #expect(app.focusedID == "two")
        app.hover(at: try cell(app, "One"))
        #expect(app.focusedID == "one")
    }

    @Test("The keyboard takes it back from a resting pointer, and the next move takes it again")
    func keyboardTakesItBack() throws {
        let app = TestApp(FollowingApp())
        app.advance(by: .milliseconds(20))
        let two = try cell(app, "Two")
        app.hover(at: two)
        #expect(app.focusedID == "two")
        app.press(.tab, modifiers: .shift)
        #expect(app.focusedID == "one")
        // Reported again from the cell it rests on: nothing moves.
        app.hover(at: two)
        #expect(app.focusedID == "one")
        // Onto another cell of the same control: it takes the focus again.
        app.hover(at: try cell(app, "Two", offset: 1))
        #expect(app.focusedID == "two")
    }

    @Test("A field the pointer crossed gives the focus up; one typed in keeps it")
    func editKeepsFocus() throws {
        let app = TestApp(FollowingApp())
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, "Name"))
        let field = try #require(app.focusedID)
        #expect(field.hasPrefix("textfield"))
        app.hover(at: try cell(app, "Two"))
        #expect(app.focusedID == "two")

        app.hover(at: try cell(app, "Name"))
        #expect(app.focusedID == field)
        app.type("x")
        app.hover(at: try cell(app, "One"))
        #expect(app.focusedID == field, "what is typed next goes where the typing was")
        app.press(.tab, modifiers: .shift)
        #expect(app.focusedID == "two")
        app.hover(at: try cell(app, "One", offset: 1))
        #expect(app.focusedID == "one", "once the keyboard moved on, the pointer leads again")
    }

    @Test("A disabled control takes nothing")
    func disabledTakesNothing() throws {
        let app = TestApp(FollowingApp())
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, "Inert"))
        #expect(app.focusedID == "one")
    }

    private struct SheetApp: App {
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Button("Behind") {}.focusID("behind")
                    Spacer()
                }
                .sheet(isPresented: .constant(true)) {
                    VStack {
                        Button("First") {}.focusID("first")
                        Button("Second") {}.focusID("second")
                    }
                }
            }
            .focusFollowsPointer()
        }
    }

    @Test("While a sheet is up, the pointer moves the focus only within it")
    func sheetKeepsIt() throws {
        let app = TestApp(SheetApp())
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, "Second"))
        #expect(app.focusedID == "second")
        app.hover(at: try cell(app, "Behind"))
        #expect(app.focusedID == "second")
        app.hover(at: try cell(app, "First"))
        #expect(app.focusedID == "first")
    }
}
