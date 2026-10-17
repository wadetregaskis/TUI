//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkContextMenuTests.swift
//
//  A link's context menu: Open Link, Copy Link, Copy Label where the label is
//  not the destination, and Copy as Markdown — opened by a right-click or by
//  Shift+F10 on the link's own focus stop, which stays the link's only one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Link context menu")
struct LinkContextMenuTests {
    static let docs = URL(string: "https://swift.org/documentation/")!
    static let home = URL(string: "https://swift.org/")!

    /// The URLs the links opened.
    final class Opened: @unchecked Sendable {
        var urls: [URL] = []
    }

    private struct LinksApp: App {
        let board: FakeClipboard?
        let opened: Opened?
        let activation: LinkActivation

        init() {
            board = nil
            opened = nil
            activation = .open
        }

        init(board: FakeClipboard, opened: Opened, activation: LinkActivation) {
            self.board = board
            self.opened = opened
            self.activation = activation
        }

        var body: some Scene {
            WindowGroup {
                if let board, let opened {
                    VStack(alignment: .leading) {
                        Link("Swift docs", destination: LinkContextMenuTests.docs)
                        Link("swift.org", destination: LinkContextMenuTests.home)
                    }
                    .environment(\.clipboardAccess, board.access)
                    // Opening a link launches nothing here.
                    .environment(\.openURL, OpenURLAction { url in
                        opened.urls.append(url)
                        return .handled
                    })
                    .linkActivation(activation)
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let board = FakeClipboard()
        let opened = Opened()
        let app: HeadlessApp<LinksApp>
        private var now: Int64 = 0

        init(activation: LinkActivation = .open) {
            app = HeadlessApp(LinksApp(board: board, opened: opened, activation: activation), width: 50, height: 16)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func row(_ text: String) -> Int? { app.screen.map(\.stripped).firstIndex { $0.contains(text) } }

        func shows(_ text: String) -> Bool { row(text) != nil }

        /// Right-clicks the first cell of `text`.
        func rightClick(_ text: String) throws {
            let lines = app.screen.map(\.stripped)
            let y = try #require(lines.firstIndex { $0.contains(text) })
            let x = try #require(lines[y].range(of: text)).lowerBound.utf16Offset(in: lines[y])
            app.send(MouseEvent(button: .right, phase: .pressed, x: x, y: y))
            app.send(MouseEvent(button: .right, phase: .released, x: x, y: y))
            frame()
        }

        /// Clicks the menu row that says `title`.
        func choose(_ title: String) throws {
            let lines = app.screen.map(\.stripped)
            let y = try #require(lines.firstIndex { $0.contains(title) })
            let x = try #require(lines[y].range(of: title)).lowerBound.utf16Offset(in: lines[y])
            app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
            frame()
        }
    }

    @Test("A right-click on a link offers Open Link and three copies, and Copy Link copies the destination")
    func rightClickMenu() throws {
        let harness = Harness()
        try harness.rightClick("Swift docs")
        for title in ["Open Link", "Copy Link", "Copy Label", "Copy as Markdown"] {
            #expect(harness.shows(title), "\(title) is offered")
        }
        try harness.choose("Copy Link")
        #expect(harness.board.writes == [Self.docs.absoluteString])
        #expect(!harness.shows("Copy Label"), "the menu closed")
    }

    @Test("A right-click on the destination's popover offers Copy Link")
    func popoverMenu() throws {
        let harness = Harness()
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.shows(Self.docs.absoluteString), "precondition: the popover shows the destination")
        try harness.rightClick(Self.docs.absoluteString)
        #expect(!harness.shows("Copy Label"), "the popover's menu, not the link's")
        try harness.choose("Copy Link")
        #expect(harness.board.writes == [Self.docs.absoluteString])
    }

    @Test(".linkActivation(.copy): activating copies the destination and opens nothing, and Open Link still opens")
    func activationCopies() throws {
        let harness = Harness(activation: .copy)
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.board.writes == [Self.docs.absoluteString])
        #expect(harness.opened.urls.isEmpty)
        #expect(harness.shows(Self.docs.absoluteString), "the popover shows what was copied")
        harness.app.send(KeyEvent(key: .escape))
        harness.frame()
        try harness.rightClick("Swift docs")
        try harness.choose("Open Link")
        #expect(harness.opened.urls == [Self.docs])
        #expect(harness.board.writes.count == 1)
    }

    @Test("Copy Label copies the words shown, and Copy as Markdown both")
    func copies() throws {
        let harness = Harness()
        try harness.rightClick("Swift docs")
        try harness.choose("Copy Label")
        try harness.rightClick("Swift docs")
        try harness.choose("Copy as Markdown")
        #expect(harness.board.writes == ["Swift docs", "[Swift docs](https://swift.org/documentation/)"])
    }

    @Test("A link whose words are its address offers no Copy Label, and copies as an autolink")
    func labelIsAddress() throws {
        let harness = Harness()
        try harness.rightClick("swift.org")
        #expect(harness.shows("Copy Link"))
        #expect(!harness.shows("Copy Label"))
        try harness.choose("Copy as Markdown")
        #expect(harness.board.writes == ["<https://swift.org/>"])
    }

    @Test("Shift+F10 opens the focused link's menu, and each link is still one Tab stop")
    func keyboard() throws {
        let harness = Harness()
        /// Shift+F10, whether the menu is the first link's — whose label is
        /// not its address, so it offers Copy Label — and Escape.
        func menuIsTheFirstLinks() -> Bool {
            harness.app.send(KeyEvent(key: .f10, shift: true))
            harness.frame()
            #expect(harness.shows("Copy Link"), "a menu opened")
            let first = harness.shows("Copy Label")
            harness.app.send(KeyEvent(key: .escape))
            harness.frame()
            return first
        }
        #expect(menuIsTheFirstLinks())
        harness.app.send(KeyEvent(key: .tab))
        harness.frame()
        #expect(!menuIsTheFirstLinks(), "one Tab reaches the second link")
        harness.app.send(KeyEvent(key: .tab))
        harness.frame()
        #expect(menuIsTheFirstLinks(), "and the next comes back round: two links, two stops")
    }

    @Test("The label's brackets are escaped, and the destination's parentheses encoded")
    func markdownEscapes() throws {
        let url = try #require(URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)"))
        #expect(
            LinkContextMenu.markdown(label: "Swift [lang]", destination: url)
                == "[Swift \\[lang\\]](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)")
        #expect(LinkContextMenu.markdown(label: "", destination: url) == "<\(url.absoluteString)>")
        #expect(LinkContextMenu.labelIsDestination("www.swift.org", Self.home))
        #expect(!LinkContextMenu.labelIsDestination("Swift", Self.home))
    }

    @Test("Copy Label leaves out an icon drawn as an SF Symbol")
    func iconLeftOut() {
        let record = LinkLabelText()
        let drawn = FrameBuffer(lines: ["\u{100ACA} apple/swift"])
        _ = RecordsLinkLabelText(record: record).modify(buffer: drawn, context: RenderContext(availableWidth: 20, availableHeight: 1))
        #expect(record.text == "apple/swift")
    }
}
