//  🖥️ TUI — A Terminal UI framework for Swift
//  DrawnTextEscapeSequenceTests.swift
//
//  The owner's ruling TEXT-ESC (2026-11-10): the words every view draws lose
//  their escape sequences and bare control characters, so text from outside the
//  app cannot write the clipboard (OSC 52), set the window title (OSC 0 and 2)
//  or change colours (CSI); `.textKeepsEscapeSequences()` keeps them for a
//  subtree.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Escape sequences in drawn text")
struct DrawnTextEscapeSequenceTests {
    /// Payloads a hostile string might carry, each with the bytes that must not
    /// reach the terminal.
    nonisolated static let payloads: [(name: String, text: String, forbidden: [String])] = [
        ("OSC 52 clipboard write, BEL-terminated", "x\u{1B}]52;c;aGVsbG8=\u{07}y", ["]52;", "\u{07}"]),
        ("OSC 52 clipboard write, ST-terminated", "x\u{1B}]52;c;aGVsbG8=\u{1B}\\y", ["]52;", "\u{1B}\\"]),
        ("OSC 0 title, BEL-terminated", "x\u{1B}]0;pwned\u{07}y", ["]0;", "pwned"]),
        ("OSC 2 title, ST-terminated", "x\u{1B}]2;pwned\u{1B}\\y", ["]2;", "pwned"]),
        ("CSI colour", "x\u{1B}[31my", ["\u{1B}[31m"]),
        ("CSI clear screen", "x\u{1B}[2Jy", ["\u{1B}[2J"]),
        ("8-bit OSC title", "x\u{9D}0;pwned\u{07}y", ["\u{9D}", "pwned"]),
        ("bare C0 controls", "x\u{07}\u{08}\u{00}y", ["\u{07}", "\u{08}", "\u{00}"]),
    ]

    private func drawn(_ view: some View, width: Int = 40, height: Int = 8) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines.joined(separator: "\n")
    }

    private func expectClean(_ output: String, _ payload: (name: String, text: String, forbidden: [String])) {
        for bytes in payload.forbidden {
            #expect(!output.contains(bytes), "\(payload.name): \(output.debugDescription)")
        }
        #expect(output.stripped.contains("xy"), "\(payload.name): the words around it stay")
    }

    @Test("A Text drops every escape sequence and bare control in its string", arguments: 0..<payloads.count)
    func textDropsThem(index: Int) {
        let payload = Self.payloads[index]
        expectClean(drawn(Text(verbatim: payload.text)), payload)
    }

    @Test("So do the views that draw their words without a Text", arguments: 0..<payloads.count)
    func otherViewsDropThem(index: Int) {
        struct Row: Identifiable {
            let id: Int
            let name: String
        }
        let payload = Self.payloads[index]
        let text = payload.text
        // A button's label, a panel's title in its border, a tab's title in
        // the strip, a table's header and its key-path cell: each spells its
        // words through `RenderContext.spelled(_:)` rather than a `Text`.
        expectClean(drawn(Button(text) {}), payload)
        expectClean(drawn(Panel(text) { Text("body") }), payload)
        expectClean(drawn(TabView(selection: .constant(0)) { Tab(text, value: 0) { Text("body") } }), payload)
        let table = drawn(Table([Row(id: 0, name: text)]) { TableColumn(text, value: \Row.name) })
        for bytes in payload.forbidden {
            #expect(!table.contains(bytes), "table, \(payload.name): \(table.debugDescription)")
        }
    }

    @Test("Tabs and line breaks keep their handling")
    func tabsAndLineBreaksStay() {
        #expect("a\tb\nc\r\nd\re".sanitizedForTerminal == "a\tb\nc\r\nd\re")
        let lines = renderToBuffer(Text(verbatim: "one\ntwo"), context: makeRenderContext(width: 20, height: 4))
            .lines.map(\.stripped)
        #expect(lines == ["one", "two"])
    }

    @Test(".textKeepsEscapeSequences() keeps them, for the subtree it is on")
    func optInKeepsThem() {
        let red = "x\u{1B}[31my\u{1B}[0m"
        #expect(drawn(Text(verbatim: red).textKeepsEscapeSequences()).contains("\u{1B}[31m"))
        #expect(drawn(VStack { Text(verbatim: red) }.textKeepsEscapeSequences()).contains("\u{1B}[31m"))
        #expect(drawn(Button(red) {}.textKeepsEscapeSequences()).contains("\u{1B}[31m"))
        // `false` is the default again, below one that kept them.
        #expect(
            !drawn(VStack { Text(verbatim: red).textKeepsEscapeSequences(false) }.textKeepsEscapeSequences())
                .contains("\u{1B}[31m"))
        // An OSC 52 the app wrote itself goes through too: the opt-in passes
        // what was written, whatever it does.
        let clipboard = "x\u{1B}]52;c;aGVsbG8=\u{07}y"
        #expect(drawn(Text(verbatim: clipboard).textKeepsEscapeSequences()).contains("]52;"))
    }
}
