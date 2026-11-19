//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackTabThenOtherMoveTests.swift
//
//  A Tab into a lazy stack followed, in the same batch of input, by a click
//  or a key that moves the focus somewhere else. The frame after a Tab asks
//  whether the Tab came into the stack from outside (`arrivalEdge`), and if
//  so takes the focus on to the stack's first row with something to focus
//  (`resolveEdgeArrival`). It asked of the Tab's record alone, so a click on
//  row 5 after the Tab, before any frame, was undone: the frame took the
//  focus back to row 0, the row the Tab would have landed on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITesting

@MainActor
@Suite("Tab into a lazy stack, then another move in the same batch", .serialized)
struct LazyStackTabThenOtherMoveTests {
    private struct Page: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}.focusID("top")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<300, id: \.self) { index in
                            Button("row\(index)") {}.focusID("r\(index)")
                        }
                    }
                }
                .frame(height: 8)
                Button("bottom") {}.focusID("bottom")
            }
        }
    }

    /// The app, with `top` focused and a few frames drawn, so last frame's
    /// ring is the page's.
    private func focusedOnTop() throws -> TestApp {
        let app = TestApp(width: 30, height: 14) { Page() }
        app.frame(atNanos: 16_666_667)
        try app.click("top")
        app.frame(atNanos: 33_333_334)
        app.frame(atNanos: 50_000_001)
        #expect(app.focusedID == "top")
        return app
    }

    /// The cell in the middle of `text`, where it first shows.
    private func middle(of text: String, in app: TestApp) throws -> CellPoint {
        let lines = app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains(text) }, "\(text) is on screen: \(lines)")
        let start = try #require(lines[y].range(of: text)).lowerBound
        return CellPoint(x: lines[y][..<start].count + text.count / 2, y: y)
    }

    @Test("A click on row 5 after the Tab keeps the focus on row 5")
    func tabThenClick() throws {
        let app = try focusedOnTop()
        let row5 = try middle(of: "row5", in: app)
        app.send(KeyEvent(key: .tab))
        app.send(MouseEvent(button: .left, phase: .pressed, x: row5.x, y: row5.y))
        app.send(MouseEvent(button: .left, phase: .released, x: row5.x, y: row5.y))
        app.frame(atNanos: 66_666_668)
        app.frame(atNanos: 83_333_335)
        #expect(app.focusedID == "r5")
    }

    @Test("A Tab alone from the control above still lands on row 0")
    func tabAlone() throws {
        let app = try focusedOnTop()
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 66_666_668)
        app.frame(atNanos: 83_333_335)
        #expect(app.focusedID == "r0")
    }
}
