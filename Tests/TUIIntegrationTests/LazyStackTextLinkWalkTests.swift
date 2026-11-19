//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackTextLinkWalkTests.swift
//
//  A link inside a `Text` is a focus stop (the owner's ruling B85), so the
//  lazy stack's walk for the row Tab comes in at (LAZY-EDGE, deviation L7)
//  must find one, as an eager `VStack`'s Tab does. It did not: the walk draws
//  its rows with the mouse dispatcher taken away, and a link was a stop only
//  where there was one. Now the focus system alone makes it a stop; the walk
//  still leaves nothing in the live dispatcher, and a link on a drawn row
//  answers the pointer as before.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITesting

@MainActor
@Suite("A lazy stack's walk for the focus finds a text's links", .serialized)
struct LazyStackTextLinkWalkTests {
    static let destination = URL(string: "https://example.com/")!

    /// The URLs the links opened.
    final class Opened: @unchecked Sendable {
        var urls: [URL] = []
    }

    /// A button over `rows` lines of text, the one at `link` (if any) a link
    /// and the one at `pointer` (if any) one that hears the pointer but takes
    /// no focus, in a lazy stack (an eager one, `lazy` false) in a scroll
    /// view, with a button under it.
    private struct Page: View {
        let rows: Int
        let link: Int?
        let pointer: Int?
        let lazy: Bool
        let opened: Opened

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}.focusID("top")
                ScrollView {
                    if lazy {
                        LazyVStack(alignment: .leading, spacing: 0) { lines }
                    } else {
                        VStack(alignment: .leading, spacing: 0) { lines }
                    }
                }
                .frame(height: 6)
                Button("bottom") {}.focusID("bottom")
            }
            // Opening a link launches nothing here.
            .environment(\.openURL, OpenURLAction { [opened] url in
                opened.urls.append(url)
                return .handled
            })
        }

        private var lines: some View {
            ForEach(0..<rows, id: \.self) { index in
                if index == link {
                    Text("[go](https://example.com/)")
                } else if index == pointer {
                    Text("line \(index)").onHover { _ in }.onTapGesture {}.pointerStyle(.link)
                } else {
                    Text("line \(index)")
                }
            }
        }
    }

    private func app(
        rows: Int = 1_000, link: Int? = 300, pointer: Int? = nil, lazy: Bool = true, opened: Opened = Opened()
    ) -> TestApp {
        let app = TestApp(width: 30, height: 12) {
            Page(rows: rows, link: link, pointer: pointer, lazy: lazy, opened: opened)
        }
        // A terminal TUI's controls set the pointer's shape on, as a link's
        // pointing hand needs.
        app.services.terminalFeatures = TerminalFeatures(pointerShapes: true, controlPointerShapes: true)
        // Two frames: the first focuses the top button, the second walks the
        // stack for the row a Tab from it comes in at.
        for frame in 1...2 {
            _ = app.takeFrameRequest()
            app.frame(atNanos: Int64(frame) * 16_666_667)
        }
        return app
    }

    /// What holds the focus, as a kind: a link, the scroll view, or its id.
    private func focus(_ app: TestApp) -> String {
        guard let id = app.focusedID else { return "nothing" }
        if id.hasPrefix("text-link-") { return "link" }
        if id.hasPrefix("scrollview-") { return "scroll" }
        return id
    }

    @Test("Tab and Shift-Tab reach a link 300 rows into a LazyVStack of text, as in a VStack")
    func textLinkWalked() {
        for lazy in [false, true] {
            let tab = app(lazy: lazy)
            _ = tab.press(.tab)
            #expect(focus(tab) == "link", "lazy \(lazy)")
            #expect(tab.screen.lines.contains { $0.contains("go") }, "lazy \(lazy): the link is scrolled in")

            // Shift-Tab from the top wraps to the bottom button, then to the
            // scroll view's own stop, which registers after its content.
            let shiftTab = app(lazy: lazy)
            var seen: [String] = []
            for _ in 0..<3 {
                _ = shiftTab.press(.tab, modifiers: .shift)
                seen.append(focus(shiftTab))
            }
            #expect(seen == ["bottom", "scroll", "link"], "lazy \(lazy)")
        }
    }

    @Test("A link the walk found opens on Return and has Link's menu, as one drawn on screen does")
    func walkedLinkIsAControl() {
        let opened = Opened()
        let app = app(opened: opened)
        _ = app.press(.tab)
        _ = app.press(.enter)
        #expect(opened.urls == [Self.destination])
        _ = app.press(.escape)
        _ = app.press(.f10, modifiers: .shift)
        #expect(app.screen.lines.contains { $0.contains("Copy Link") }, "\(app.screen.lines)")
    }

    @Test("A link on a row drawn on screen still takes a click and shows the pointing hand")
    func drawnLinkAnswersThePointer() throws {
        let opened = Opened()
        let app = app(rows: 50, link: 2, opened: opened)
        let lines = app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains("go") })
        let x = try #require(lines[y].range(of: "go")).lowerBound.utf16Offset(in: lines[y])
        #expect(app.services.mouseEventDispatcher.resolvePointerShape(at: x, y: y) == .link)
        try app.click("go")
        #expect(opened.urls == [Self.destination])
    }

    /// The walk to the link at row 300 looks at row 150, whose text hears the
    /// pointer (a hover, a tap, a pointer shape) but takes no focus, and the
    /// frame does not draw it: nothing of it may stand in the live dispatcher.
    /// Fails if the walk draws its rows with the live dispatcher.
    @Test("The walk leaves no handler or pointer shape of a row it only looked at in the live dispatcher")
    func walkLeavesNoPointerRegistrations() {
        let plain = app().services.mouseEventDispatcher
        let walked = app(pointer: 150)
        #expect(walked.screen.lines.allSatisfy { !$0.contains("line 150") }, "row 150 is off screen")
        let dispatcher = walked.services.mouseEventDispatcher
        #expect(dispatcher.handlerCount == plain.handlerCount)
        #expect(dispatcher.controlPointerShapes.count == plain.controlPointerShapes.count)
        #expect(dispatcher.pointerStyleRegions.count == plain.pointerStyleRegions.count)
        #expect(dispatcher.hoverObserverIDs.count == plain.hoverObserverIDs.count)
        // And the walk did reach the link past it.
        _ = walked.press(.tab)
        #expect(focus(walked) == "link")
    }
}
