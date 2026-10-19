//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostStateTests.swift
//
//  The ledger of what the app sets on the terminal emulator beyond its screen
//  — the window title: written on a change only, the terminal's own saved
//  before the first and restored for none, on suspend and on exit; sanitised
//  so nothing in it can end the OSC; owed to a fatal signal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitTestSupport

@MainActor
@Suite("The terminal host state ledger")
struct TerminalHostStateTests {
    private static let save = "\u{1B}[22;2t"
    private static let restore = "\u{1B}[23;2t"

    private static func set(_ title: String) -> String { "\u{1B}]2;\(title)\u{1B}\\" }

    @Test("The first title saves the terminal's own, then sets it; the same title again writes nothing")
    func firstTitleSavesThenSets() {
        var ledger = TerminalHostState()
        #expect(ledger.show(title: "Notes") == Self.save + Self.set("Notes"))
        #expect(ledger.show(title: "Notes").isEmpty)
        #expect(ledger.writtenTitle == "Notes")
    }

    @Test("Another title sets it without saving again")
    func changeSetsOnly() {
        var ledger = TerminalHostState()
        _ = ledger.show(title: "Notes")
        #expect(ledger.show(title: "Inspector") == Self.set("Inspector"))
    }

    @Test("No title restores the terminal's own, and the next title saves it again")
    func noTitleRestores() {
        var ledger = TerminalHostState()
        _ = ledger.show(title: "Notes")
        #expect(ledger.show(title: nil) == Self.restore)
        #expect(ledger.show(title: nil).isEmpty)
        #expect(ledger.show(title: "Notes") == Self.save + Self.set("Notes"))
    }

    @Test("A ledger that never set a title writes nothing for none, and restores nothing")
    func nothingSetNothingOwed() {
        var ledger = TerminalHostState()
        #expect(ledger.show(title: nil).isEmpty)
        #expect(ledger.restore().isEmpty)
        #expect(ledger.debt.isEmpty)
    }

    @Test("Handing the terminal back restores its title and forgets the app's, which the next frame sets again")
    func handBackAndResume() {
        var ledger = TerminalHostState()
        _ = ledger.show(title: "Notes")
        #expect(ledger.debt == Self.restore)
        #expect(ledger.restore() == Self.restore)
        #expect(ledger.debt.isEmpty)
        #expect(ledger.writtenTitle == nil)
        #expect(ledger.show(title: "Notes") == Self.save + Self.set("Notes"))
    }

    @Test("BEL, ESC, DEL and the C1 controls are dropped from a title; line breaks and tabs are spaces")
    func sanitised() {
        #expect(TerminalHostState.sanitizedTitle("a\u{07}b\u{1B}]0;x\u{7F}c\u{9B}d\u{9C}") == "ab]0;xcd")
        #expect(TerminalHostState.sanitizedTitle("one\ntwo\r\nthree\tfour\u{85}five") == "one two three four five")
        #expect(TerminalHostState.sanitizedTitle("Café 🇳🇿 ノート") == "Café 🇳🇿 ノート")
        var ledger = TerminalHostState()
        #expect(ledger.show(title: "x\u{1B}\\y") == Self.save + Self.set("x\\y"))
    }

    @Test("A title that is nothing once sanitised is no title")
    func emptyIsNone() {
        var ledger = TerminalHostState()
        #expect(ledger.show(title: "").isEmpty)
        #expect(ledger.show(title: "\u{07}\u{1B}").isEmpty)
        _ = ledger.show(title: "Notes")
        #expect(ledger.show(title: "\u{07}") == Self.restore)
    }

    @Test("A saved title is owed to a fatal signal and to a quit, and owed no more once paid")
    func signalDebt() {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(!terminal.signalDebt.contains(Self.restore))
        terminal.oweHostState(Self.restore)
        #expect(terminal.signalDebt.contains(Self.restore))
        #expect(terminal.quitDebt.contains(Self.restore))
        terminal.oweHostState("")
        #expect(!terminal.signalDebt.contains(Self.restore))
    }
}
