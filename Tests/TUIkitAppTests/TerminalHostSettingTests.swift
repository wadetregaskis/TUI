//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostSettingTests.swift
//
//  The one shape every value the app sets outside the grid takes — the
//  window title, the progress bar, the pointer's shape: change-only writes
//  spelled by the caller, a lead before a value set over the terminal's own,
//  a reset owed from the first send until it goes out or an unset that
//  settles does, and a value forgotten when the terminal may have changed it
//  (decisions HOSTLEDGER, B-HOSTLEDGER-3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTerminalHost
@testable import TUIkitTestSupport

@MainActor
@Suite("One value outside the grid")
struct TerminalHostSettingTests {
    private static func spell(_ value: String) -> String { "<\(value)>" }

    /// A setting shaped like the title's: led by a save, settled by its unset.
    private static func titleLike() -> TerminalHostSetting<String> {
        TerminalHostSetting(lead: "save;", unset: "pop;", reset: "pop;", unsetSettles: true)
    }

    /// A setting shaped like the pointer's: no lead, its unset not its reset,
    /// and owed until the reset goes out.
    private static func pointerLike() -> TerminalHostSetting<String> {
        TerminalHostSetting(unset: "<default>", reset: "<>", unsetSettles: false)
    }

    @Test("A value is written when it changes, spelled by the caller; the terminal's own over its own is nothing")
    func changeOnly() {
        var setting = Self.pointerLike()
        #expect(setting.update(to: nil, spelling: Self.spell) == nil)
        #expect(!setting.isOwed)
        #expect(setting.update(to: "pointer", spelling: Self.spell) == "<pointer>")
        #expect(setting.update(to: "pointer", spelling: Self.spell) == nil)
        #expect(setting.value == "pointer")
        #expect(setting.update(to: "text", spelling: Self.spell) == "<text>")
    }

    @Test("The lead goes before a value set over the terminal's own, and only then")
    func leadOverOwn() {
        var setting = Self.titleLike()
        #expect(setting.update(to: "Notes", spelling: Self.spell) == "save;<Notes>")
        #expect(setting.update(to: "Mail", spelling: Self.spell) == "<Mail>")
        #expect(setting.update(to: nil, spelling: Self.spell) == "pop;")
        #expect(setting.update(to: "Notes", spelling: Self.spell) == "save;<Notes>")
    }

    @Test("An unset that settles leaves nothing owed; one that does not leaves the reset owed until it goes out")
    func unsetSettlesOrNot() {
        var title = Self.titleLike()
        _ = title.update(to: "Notes", spelling: Self.spell)
        #expect(title.owedReset == "pop;")
        _ = title.update(to: nil, spelling: Self.spell)
        #expect(!title.isOwed)
        #expect(title.takeReset().isEmpty, "a second pop would take a title that is not the app's")

        var pointer = Self.pointerLike()
        _ = pointer.update(to: "pointer", spelling: Self.spell)
        #expect(pointer.update(to: nil, spelling: Self.spell) == "<default>")
        #expect(pointer.owedReset == "<>")
        #expect(pointer.takeReset() == "<>")
        #expect(!pointer.isOwed)
        #expect(pointer.value == nil)
    }

    @Test("A value the terminal may have changed itself is sent again, without the lead; its own is not")
    func forgotten() {
        var setting = Self.pointerLike()
        setting.forgetSent()
        #expect(setting.update(to: nil, spelling: Self.spell) == nil, "the terminal's own was never left")
        _ = setting.update(to: "pointer", spelling: Self.spell)
        setting.forgetSent()
        #expect(setting.value == nil)
        #expect(setting.update(to: "pointer", spelling: Self.spell) == "<pointer>")

        var title = Self.titleLike()
        _ = title.update(to: "Notes", spelling: Self.spell)
        title.forgetSent()
        #expect(title.update(to: "Notes", spelling: Self.spell) == "<Notes>", "the save is still on the stack")
    }

    @Test("A reset taken forgets the value, so a resume sends it afresh, led again")
    func resetThenResume() {
        var setting = Self.titleLike()
        _ = setting.update(to: "Notes", spelling: Self.spell)
        #expect(setting.takeReset() == "pop;")
        #expect(setting.takeReset().isEmpty)
        #expect(setting.update(to: "Notes", spelling: Self.spell) == "save;<Notes>")
    }

    /// On every host but Ghostty the pointer's unset is the empty name, the
    /// very bytes of its reset. It still leaves the reset owed, as O12 has it
    /// (B-O12-4), which is why a setting says whether its unset settles
    /// rather than comparing the two.
    @Test("On iTerm2 the pointer's unset, the reset's own bytes, still leaves the reset owed")
    func pointerUnsetIsNotItsReset() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(
            environment: ["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.6.11"])
        terminal.enableRawMode()
        terminal.showPointerShape(.link)
        terminal.showPointerShape(nil)
        #expect(terminal.signalDebt.contains(PointerShapeHost.reset + Terminal.inputModesOff))
        output.clear()
        terminal.disableRawMode()
        #expect(output.bytes.contains(PointerShapeHost.reset + Terminal.inputModesOff))
    }
}
