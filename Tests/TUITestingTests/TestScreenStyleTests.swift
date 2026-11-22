//  🖥️ TUI — A Terminal UI framework for Swift
//  TestScreenStyleTests.swift
//
//  What a TestApp's screen draws a cell in (B-ATTRED-62): colours, weight
//  and underline read from a row's escape codes, by cell and by text, a wide
//  character's two cells both its.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

@MainActor
@Suite("A test screen's cell styles")
struct TestScreenStyleTests {
    @Test("A cell's colours, weight and underline read back, by its place and by its text")
    func styles() throws {
        let app = TestApp(width: 30, height: 2) {
            HStack(spacing: 1) {
                Text("plain")
                Text("red").foregroundStyle(Color(red: 1, green: 0, blue: 0))
                Text("bold").bold()
                Text("lined").underline()
                Text("界x")
            }
        }
        let plain = app.screen.style(of: "plain")
        #expect(plain?.isBold == false && plain?.underline == nil)
        #expect(app.screen.style(of: "red")?.foreground == .rgb(red: 255, green: 0, blue: 0))
        #expect(plain?.foreground != .rgb(red: 255, green: 0, blue: 0))
        #expect(app.screen.style(of: "bold")?.isBold == true)
        #expect(app.screen.style(of: "lined")?.underline == 1, "a single line")
        // A wide character's second cell is its own.
        let wide = try #require(app.screen.location(of: "界"))
        #expect(app.screen.style(at: CellPoint(x: wide.x + 1, y: wide.y)) == app.screen.style(at: wide))
        #expect(app.screen.style(at: CellPoint(x: 0, y: 5)) == nil, "past the screen")
        #expect(app.screen.style(of: "absent") == nil)
    }
}
