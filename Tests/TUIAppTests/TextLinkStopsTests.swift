//  🖥️ TUI — A Terminal UI framework for Swift
//  TextLinkStopsTests.swift
//
//  A link inside a `Text` is a control (the owner's ruling B85-KEYBOARD,
//  2026-10-23, "full control"): Tab reaches it, Return or a click opens it
//  and shows where it goes, and Shift+F10 or a right-click opens `Link`'s
//  menu on it. Where the destination is written on the row, or the text is
//  disabled, it is not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUICore

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Links inside a Text are controls")
struct TextLinkStopsTests {
    static let docs = URL(string: "https://swift.org/documentation/")!
    static let home = URL(string: "https://swift.org/")!

    /// The URLs the links opened, and the button's presses.
    final class Log: @unchecked Sendable {
        var opened: [URL] = []
        var started = 0
    }

    private struct TextLinksApp: App {
        let board: FakeClipboard?
        let log: Log?
        let display: LinkDisplay
        let enabled: Bool

        init() {
            board = nil
            log = nil
            display = .popover
            enabled = true
        }

        init(board: FakeClipboard, log: Log, display: LinkDisplay, enabled: Bool) {
            self.board = board
            self.log = log
            self.display = display
            self.enabled = enabled
        }

        var body: some Scene {
            WindowGroup {
                if let board, let log {
                    VStack(alignment: .leading) {
                        Button("Start") { log.started += 1 }
                        Text("Read the [guide](https://swift.org/documentation/) or [home](https://swift.org/).")
                            .disabled(!enabled)
                    }
                    .environment(\.clipboardAccess, board.access)
                    // Opening a link launches nothing here.
                    .environment(\.openURL, OpenURLAction { url in
                        log.opened.append(url)
                        return .handled
                    })
                    .linkDisplay(display)
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let board = FakeClipboard()
        let log = Log()
        let app: TestApp
        private var now: Int64 = 0

        init(display: LinkDisplay = .popover, enabled: Bool = true) {
            app = TestApp(
                TextLinksApp(board: board, log: log, display: display, enabled: enabled), width: 60, height: 16)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func key(_ event: KeyEvent) {
            app.send(event)
            frame()
        }

        func row(_ text: String) -> Int? { app.screen.lines.firstIndex { $0.contains(text) } }

        func shows(_ text: String) -> Bool { row(text) != nil }

        /// The cell of the first character of `text` on the screen.
        func cell(_ text: String) throws -> (x: Int, y: Int) {
            let lines = app.screen.lines
            let y = try #require(lines.firstIndex { $0.contains(text) })
            let x = try #require(lines[y].range(of: text)).lowerBound.utf16Offset(in: lines[y])
            return (x, y)
        }

        func click(_ text: String, button: MouseButton = .left) throws {
            let (x, y) = try cell(text)
            app.send(MouseEvent(button: button, phase: .pressed, x: x, y: y))
            app.send(MouseEvent(button: button, phase: .released, x: x, y: y))
            frame()
        }
    }

    @Test("Tab reaches each link in turn, and Return opens it and shows where it goes")
    func tabAndReturn() {
        let harness = Harness()
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.log.opened == [Self.docs])
        #expect(harness.log.started == 0)
        #expect(harness.shows(Self.docs.absoluteString), "the popover shows the destination")
        harness.key(KeyEvent(key: .escape))
        #expect(!harness.shows(Self.docs.absoluteString), "Escape put the popover away")
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.log.opened == [Self.docs, Self.home])
    }

    @Test("A link's destination popover lines up with the link, as a Link's does")
    func popoverLinesUpWithTheLink() throws {
        // Owner, 2026-10-24: the popover under a link inside a text sat centred
        // on it, and under a `Link` left-aligned to it. Both start where the
        // link starts now: the panel's left wall is in the link's first column.
        let harness = Harness()
        let link = try harness.cell("home")
        try harness.click("home")
        let url = try harness.cell(Self.home.absoluteString)
        #expect(url.y > link.y)
        let row = Array(harness.app.screen.lines[url.y])
        #expect(row[link.x] == "│", "the URL at \(url.x), the link at \(link.x): \(String(row))")
        #expect(row[link.x + 1..<url.x].allSatisfy { $0 == " " }, "\(String(row))")
    }

    @Test("A click on a link's words opens it")
    func click() throws {
        let harness = Harness()
        try harness.click("home")
        #expect(harness.log.opened == [Self.home])
        try harness.click("Read")
        #expect(harness.log.opened == [Self.home], "the text's other words are no link")
    }

    @Test("Shift+F10 on a focused link opens Link's menu, and Copy Link copies that link")
    func keyboardMenu() throws {
        let harness = Harness()
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .f10, shift: true))
        for title in ["Show Link", "Copy Link", "Copy Label", "Copy as Markdown"] {
            #expect(harness.shows(title), "\(title) is offered")
        }
        try harness.click("Copy Link")
        #expect(harness.board.writes == [Self.home.absoluteString])
        #expect(harness.log.opened.isEmpty)
    }

    @Test("A right-click on a link opens its menu; on the text's other words, none")
    func rightClickMenu() throws {
        let harness = Harness()
        try harness.click("Read", button: .right)
        #expect(!harness.shows("Copy Link"))
        try harness.click("guide", button: .right)
        #expect(harness.shows("Copy Link"))
        try harness.click("Copy as Markdown")
        #expect(harness.board.writes == ["[guide](\(Self.docs.absoluteString))"])
    }

    /// A text whose link wraps, through the real input chain at a width
    /// that breaks it over two rows.
    private func wrappedLink(log: Log) -> some View {
        VStack(alignment: .leading) {
            Button("Go") {}
            Text("Read [the long guide](https://swift.org/documentation/) now")
        }
        .environment(\.openURL, OpenURLAction { url in
            log.opened.append(url)
            return .handled
        })
    }

    @Test("A link the text wraps is one stop that breathes on its rows alone, and a click on either row opens it")
    func wrappedLinkBreathesAndClicks() throws {
        let log = Log()
        let harness = InputChainHarness(width: 14, height: 8)
        harness.frame(wrappedLink(log: log))
        let rows = harness.frame(wrappedLink(log: log)).lines.map(\.stripped)
        let first = try #require(rows.firstIndex { $0.contains("the long") })
        let second = try #require(rows.firstIndex { $0.contains("guide") })
        #expect(second == first + 1, "the link wraps: \(rows)")
        harness.press(KeyEvent(key: .tab))
        let focused = harness.frame(wrappedLink(log: log))
        let breathing = Set(focused.animatedCells.map(\.offsetY))
        #expect(breathing == [first, second], "the link's rows breathe, and only they: \(breathing)")
        // One stop: a second Tab leaves the text, for the button.
        harness.press(KeyEvent(key: .tab))
        let left = harness.frame(wrappedLink(log: log)).animatedCells.map(\.offsetY)
        #expect(!left.contains(first) && !left.contains(second), "\(left)")
        let column = try #require(rows[second].range(of: "guide")).lowerBound.utf16Offset(in: rows[second])
        harness.click(column, second) { wrappedLink(log: log) }
        #expect(log.opened == [Self.docs])
    }

    @Test("No stops where the destination is written on the row, or the text is disabled")
    func notControls() {
        for harness in [Harness(display: .urlInParentheses), Harness(enabled: false)] {
            // The button is the one stop: Tab comes back round to it.
            harness.key(KeyEvent(key: .tab))
            harness.key(KeyEvent(key: .enter))
            #expect(harness.log.opened.isEmpty)
            #expect(harness.log.started == 1)
        }
    }
}
