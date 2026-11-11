//  🖥️ TUI — A Terminal UI framework for Swift
//  TextCursorFollowsFocusTests.swift
//
//  The proof of concept `TUI_TEXT_CURSOR_FOLLOWS_FOCUS` turns on: the terminal's
//  own cursor left on the focused control after each frame, shown or kept
//  hidden, and handed back shown at the end.
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
@Suite("The terminal's text cursor follows the focus")
struct TextCursorFollowsFocusTests {
    private struct Page: View {
        var body: some View {
            VStack(alignment: .leading) {
                Text("Above")
                Button("One") {}.focusID("one")
                Button("Two") {}.focusID("two")
            }
        }
    }

    private struct PageApp: App {
        var body: some Scene {
            WindowGroup { Page() }
        }
    }

    /// The first cell of the region that carries `focusID`, as the frame drew it.
    private func corner(of focusID: String, in app: TestApp) throws -> CellPoint {
        let region = try #require(
            app.services.mouseEventDispatcher.regions.first { $0.focusID == focusID }, "\(focusID) is drawn")
        return CellPoint(x: region.offsetX, y: region.offsetY)
    }

    @Test("Only `1`, `show` and `hidden` turn it on")
    func variable() {
        let key = "TUI_TEXT_CURSOR_FOLLOWS_FOCUS"
        #expect(TextCursorFollowsFocus.requested(environment: [key: "1"]) == .shown)
        #expect(TextCursorFollowsFocus.requested(environment: [key: "show"]) == .shown)
        #expect(TextCursorFollowsFocus.requested(environment: [key: "hidden"]) == .hidden)
        #expect(TextCursorFollowsFocus.requested(environment: [key: "0"]) == nil)
        #expect(TextCursorFollowsFocus.requested(environment: [:]) == nil)
    }

    @Test("Off, a button's focus leaves the cursor where the frame ended, hidden")
    func off() {
        let app = TestApp(PageApp())
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "one")
        #expect(app.cursor == nil)
        #expect(!app.cursorVisible)
    }

    @Test("Shown, the cursor sits on the focused control's first cell, and moves with the focus")
    func shown() throws {
        let app = TestApp(PageApp())
        app.textCursorFollowsFocus = .shown
        app.advance(by: .milliseconds(20))
        #expect(app.cursor == (try corner(of: "one", in: app)))
        #expect(app.cursorVisible)
        app.press(.tab)
        #expect(app.focusedID == "two")
        #expect(app.cursor == (try corner(of: "two", in: app)))
        #expect(app.cursorVisible)
    }

    @Test("Hidden, the cursor sits there and stays hidden")
    func hidden() throws {
        let app = TestApp(PageApp())
        app.textCursorFollowsFocus = .hidden
        app.advance(by: .milliseconds(20))
        #expect(app.cursor == (try corner(of: "one", in: app)))
        #expect(!app.cursorVisible)
    }

    private struct Switching: View {
        @State private var shows = true
        var body: some View {
            VStack(alignment: .leading) {
                if shows { Button("Only") { shows = false }.focusID("only") }
                Text("Below")
            }
        }
    }

    private struct SwitchingApp: App {
        var body: some Scene {
            WindowGroup { Switching() }
        }
    }

    @Test("Shown, a frame with nothing focused on screen hides it again")
    func hiddenWhenNothingFocused() throws {
        let app = TestApp(SwitchingApp())
        app.textCursorFollowsFocus = .shown
        app.advance(by: .milliseconds(20))
        #expect(app.cursorVisible)
        app.press(.enter)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == nil)
        #expect(!app.cursorVisible)
    }

    @Test("The bytes a real terminal is sent: the move to the control, the cursor shown, and shown at hand-back")
    func bytes() throws {
        let harness = RenderLoopHarness()
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        let loop = harness.loop(PageApp(), on: terminal)
        loop.textCursorFollowsFocus = .shown
        _ = loop.render()
        _ = loop.render()
        let region = try #require(
            harness.tuiContext.mouseEventDispatcher.regions.first { $0.focusID == "one" }, "the button is drawn")
        let move = ANSIRenderer.moveCursor(toRow: region.offsetY + 1, column: region.offsetX + 1)
        let frame = output.bytes
        let parked = try #require(frame.range(of: move + ANSIRenderer.showCursor, options: .backwards))
        let movedAfter = frame[parked.upperBound...].contains(/\u{1B}\[\d+;\d+H/)
        #expect(!movedAfter, "nothing moves it after it is parked")

        output.clear()
        terminal.handBack(restoringStyling: {})
        #expect(output.bytes.contains(ANSIRenderer.showCursor))
    }
}
