//  🖥️ TUI — A Terminal UI framework for Swift
//  ConsoleFontTests.swift
//
//  What GDI says a console font has: Consolas, the classic Windows console's
//  default and on every Windows, has the half blocks and none of the
//  quadrants, and `◄ ► ○` and not `◀ ▶ ◯` (measured 2026-11-18, build 26300).
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Testing

@testable import TUIApp
@testable import TUIFoundation

@Suite("The classic Windows console's font")
struct ConsoleFontTests {
    @Test("Consolas has the half blocks and none of the quadrants")
    func consolas() {
        #expect(ConsoleFont.has(["▀", "▄", "▌", "▐", "█"], face: "Consolas") == true)
        #expect(ConsoleFont.has(["▖"], face: "Consolas") == false)
        #expect(ConsoleFont.has(TerminalSymbols.quadrants.filter { $0 != " " }, face: "Consolas") == false)
    }

    @Test("A face that is not installed cannot be told about, rather than being another's")
    func missingFace() {
        #expect(ConsoleFont.has(["▖"], face: "No Such Console Font") == nil)
        #expect(ConsoleFont.standIns(face: "No Such Console Font").isEmpty)
    }

    @Test("Consolas lacks ◀ ▶ ◯ and has ◄ ► ○, so each is the other's stand-in")
    func consolasStandIns() {
        #expect(ConsoleFont.missing(["◀", "◄", "▶", "►", "◯", "○"], face: "Consolas") == ["◀", "▶", "◯"])
        #expect(ConsoleFont.standIns(face: "Consolas") == ["◀": "◄", "▶": "►", "◯": "○"])
    }
}

#endif
