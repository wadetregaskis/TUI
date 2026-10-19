//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostStateTests.swift
//
//  The ledger of what the app sets on the terminal emulator beyond its screen
//  — the window title: written on a change only, the terminal's own saved
//  before the first and restored for none, on suspend and on exit; sanitised
//  so nothing in it can end the OSC; owed to a fatal signal. And the progress
//  bar: written on a change of its whole percent, sent again when it has gone
//  five seconds unsent, taken down on the hand-back and owed to a signal.
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
        #expect(TerminalHostState.sanitizedText("a\u{07}b\u{1B}]0;x\u{7F}c\u{9B}d\u{9C}") == "ab]0;xcd")
        #expect(TerminalHostState.sanitizedText("one\ntwo\r\nthree\tfour\u{85}five") == "one two three four five")
        #expect(TerminalHostState.sanitizedText("Café 🇳🇿 ノート") == "Café 🇳🇿 ノート")
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

    // MARK: - The progress bar

    private static let second: Int64 = 1_000_000_000

    private static func progress(_ state: Int, _ percent: Int? = nil) -> String {
        "\u{1B}]9;4;\(state)" + (percent.map { ";\($0)" } ?? "") + "\u{1B}\\"
    }

    @Test("Each kind of progress is ConEmu's state, with its value as a whole percent where it has one")
    func progressSpellings() {
        var ledger = TerminalHostState()
        #expect(ledger.show(progress: .value(0.5), atNanos: 0) == Self.progress(1, 50))
        #expect(ledger.show(progress: .error(0.25), atNanos: 0) == Self.progress(2, 25))
        #expect(ledger.show(progress: .error(nil), atNanos: 0) == Self.progress(2))
        #expect(ledger.show(progress: .indeterminate, atNanos: 0) == Self.progress(3))
        #expect(ledger.show(progress: .paused(0.7), atNanos: 0) == Self.progress(4, 70))
        #expect(ledger.show(progress: .paused(nil), atNanos: 0) == Self.progress(4))
        #expect(ledger.show(progress: nil, atNanos: 0) == Self.progress(0))
    }

    @Test("A fraction is clamped to 0...1 and rounded to the percent; NaN is none done")
    func progressClamped() {
        typealias Report = TerminalHostState.ProgressReport
        #expect(Report(.value(-0.5)).percent == 0)
        #expect(Report(.value(1.5)).percent == 100)
        #expect(Report(.value(.infinity)).percent == 100)
        #expect(Report(.value(-.infinity)).percent == 0)
        #expect(Report(.value(.nan)).percent == 0)
        #expect(Report(.value(0.334)).percent == 33)
        #expect(Report(.value(0.336)).percent == 34)
        #expect(Report(.value(0.125)).percent == 13, "a half rounds up")
        #expect(Report(.error(2)).percent == 100)
    }

    @Test("The same percent again writes nothing; a move of a whole percent writes it")
    func progressChangeOnly() {
        var ledger = TerminalHostState()
        _ = ledger.show(progress: .value(0.5), atNanos: 0)
        #expect(ledger.show(progress: .value(0.5), atNanos: 0).isEmpty)
        #expect(ledger.show(progress: .value(0.504), atNanos: 0).isEmpty)
        #expect(ledger.show(progress: .value(0.51), atNanos: 0) == Self.progress(1, 51))
        #expect(ledger.show(progress: .paused(0.51), atNanos: 0) == Self.progress(4, 51))
    }

    @Test("No bar asked for writes nothing until one was shown")
    func noProgressNothingWritten() {
        var ledger = TerminalHostState()
        #expect(ledger.show(progress: nil, atNanos: 0).isEmpty)
        #expect(ledger.keepAliveDeadline == nil)
        #expect(ledger.keepAlive(atNanos: 60 * Self.second).isEmpty)
        #expect(ledger.debt.isEmpty)
    }

    @Test("A bar gone five seconds unsent is sent again, and the next five count from then")
    func progressKeepAlive() {
        var ledger = TerminalHostState()
        _ = ledger.show(progress: .value(0.5), atNanos: Self.second)
        #expect(ledger.keepAliveDeadline == 6 * Self.second)
        #expect(ledger.keepAlive(atNanos: 6 * Self.second - 1).isEmpty)
        #expect(ledger.keepAlive(atNanos: 6 * Self.second) == Self.progress(1, 50))
        #expect(ledger.keepAliveDeadline == 11 * Self.second)
        #expect(ledger.keepAlive(atNanos: 7 * Self.second).isEmpty)
        // A change sent is a send: the five seconds count from it.
        _ = ledger.show(progress: .value(0.6), atNanos: 8 * Self.second)
        #expect(ledger.keepAliveDeadline == 13 * Self.second)
        // And with the bar down there is nothing to keep alive.
        _ = ledger.show(progress: nil, atNanos: 9 * Self.second)
        #expect(ledger.keepAliveDeadline == nil)
        #expect(ledger.keepAlive(atNanos: 20 * Self.second).isEmpty)
    }

    @Test("Handing the terminal back takes the bar down with the title, and the next frame puts it up again")
    func progressHandBack() {
        var ledger = TerminalHostState()
        _ = ledger.show(title: "Notes")
        _ = ledger.show(progress: .indeterminate, atNanos: 0)
        #expect(ledger.debt == Self.restore + Self.progress(0))
        #expect(ledger.restore() == Self.restore + Self.progress(0))
        #expect(ledger.debt.isEmpty)
        #expect(ledger.keepAliveDeadline == nil)
        #expect(ledger.show(progress: .indeterminate, atNanos: 0) == Self.progress(3))
    }

    @Test("A frame with no title keeps the bar up; one with no bar keeps the title")
    func titleAndProgressApart() {
        var ledger = TerminalHostState()
        _ = ledger.show(title: "Notes")
        _ = ledger.show(progress: .value(0.2), atNanos: 0)
        #expect(ledger.show(title: nil) == Self.restore)
        #expect(ledger.writtenProgress != nil)
        _ = ledger.show(title: "Notes")
        #expect(ledger.show(progress: nil, atNanos: 0) == Self.progress(0))
        #expect(ledger.writtenTitle == "Notes")
    }
}
