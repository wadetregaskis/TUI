//  🖥️ TUI — A Terminal UI framework for Swift
//  XtermJSHostTests.swift
//
//  xterm.js as a host TUI has measured: what names it, and what it advances each
//  class of cluster by (`xtermjs-6.0.0-graphemes-advance.json`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUITerminalHost

@Suite("xterm.js as a host")
struct XtermJSHostTests {

    @Test("TERM_PROGRAM names it, and the name goes round")
    func named() {
        #expect(TerminalClient.Program(termProgramName: "xterm.js") == .xtermJS)
        #expect(TerminalClient.Program.xtermJS.termProgramName == "xterm.js")
    }

    @Test("Its Device Attributes name it, and an XTVERSION answer rules it out")
    func deviceAttributes() {
        let silent = TerminalIdentityQuery.parse(Array("\u{1B}[?1;2c\u{1B}[>0;276;0c\u{1B}[0n".utf8))
        #expect(TerminalHost.nameFromDeviceAttributes(silent) == "xterm.js")
        let versioned = TerminalIdentityQuery.parse(
            Array("\u{1B}P>|XTerm(400)\u{1B}\\\u{1B}[?1;2c\u{1B}[>0;276;0c\u{1B}[0n".utf8))
        #expect(TerminalHost.nameFromDeviceAttributes(versioned) == nil)
    }

    @Test(
        "The clusters its record has short of their claim advance one cell",
        arguments: [
            "\u{1F5A5}",  // bare_desktop
            "\u{1F1E6}",  // lone_ri_a
            "\u{1FA77}",  // pink_heart, Unicode 15
            "\u{1FAE9}",  // face_bags, Unicode 16
            "\u{100000}",  // sf_symbol_low
            "\u{0915}\u{093F}",  // matra_deva_i
            "\u{0E01}\u{0E33}",  // thai_sara_am
        ])
    func shortOfTheClaim(text: String) {
        let cluster = Character(text)
        #expect(cluster.terminalWidth == 2)
        #expect(cluster.xtermJSCursorAdvance == 1)
    }

    @Test(
        "What its record has agreeing stays at the claim, as does what no CUF can repair",
        arguments: [
            "A",
            "\u{1F600}",  // an older emoji
            "\u{1F5A5}\u{FE0F}",  // VS-16
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",  // ZWJ, composed
            "\u{1F44D}\u{1F3FD}",  // a skin tone, merged
            "\u{0938}\u{094D}\u{0924}\u{094D}\u{0930}",  // a conjunct, which over-advances
        ])
    func atTheClaim(text: String) {
        let cluster = Character(text)
        #expect(cluster.xtermJSCursorAdvance == cluster.terminalWidth)
    }

    @Test("A short cluster gets its CUF, and a row with none is left alone")
    func compensation() {
        #expect("\u{1F5A5}x".withXtermJSCursorCompensation() != "\u{1F5A5}x")
        // Past the gate the other hosts share, which has no need of these.
        #expect("\u{0915}\u{093F}x".withXtermJSCursorCompensation() != "\u{0915}\u{093F}x")
        #expect("\u{0E01}\u{0E33}x".withXtermJSCursorCompensation() != "\u{0E01}\u{0E33}x")
        #expect("plain \u{1F600}".withXtermJSCursorCompensation() == "plain \u{1F600}")
    }
}
