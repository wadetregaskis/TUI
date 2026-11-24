//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyDialectTests.swift
//
//  Keys in the spellings the xterm family's legacy parser did not know:
//  a modified key re-coded by tmux's `extended-keys` or xterm's
//  `modifyOtherKeys`, the Linux console's F1 to F5, and rxvt's Home, End and
//  modified arrows. Hunt H-60; the sequences are in
//  `Documentation/Terminals/Terminal compatibility survey.md`, "Modified keys
//  an app did not ask for".
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

@Suite("Key dialects: modifyOtherKeys, the Linux console, rxvt")
struct KeyDialectTests {
    private func parse(_ text: String) -> KeyEvent? {
        KeyEvent.parse([0x1B] + Array(text.utf8))
    }

    @Test("Shift-Space in xterm's modifyOtherKeys spelling is Space with Shift")
    func shiftSpaceModifyOtherKeys() {
        #expect(parse("[27;2;32~") == KeyEvent(key: .space, shift: true))
    }

    @Test("Ctrl-Return in the CSI u spelling is Return with Control")
    func controlReturnCSIu() {
        let event = parse("[13;5u")
        #expect(event == KeyEvent(key: .enter, ctrl: true))
        #expect(event?.isControlReturn == true)
    }

    /// What tmux 3.7c hands a pane under `extended-keys always`, in each
    /// format (measured 2026-11-23, `tmux_extended_keys_probe.py`).
    @Test(
        "Every key tmux re-codes under extended-keys always decodes to its chord",
        arguments: [
            ("[27;2;13~", KeyEvent(key: .enter, shift: true)),
            ("[27;5;13~", KeyEvent(key: .enter, ctrl: true)),
            ("[27;5;9~", KeyEvent(key: .tab, ctrl: true)),
            ("[27;2;32~", KeyEvent(key: .space, shift: true)),
            ("[13;2u", KeyEvent(key: .enter, shift: true)),
            ("[13;5u", KeyEvent(key: .enter, ctrl: true)),
            ("[9;5u", KeyEvent(key: .tab, ctrl: true)),
            ("[32;2u", KeyEvent(key: .space, shift: true)),
        ])
    func tmuxExtendedKeys(sequence: String, expected: KeyEvent) {
        #expect(parse(sequence) == expected)
    }

    /// xterm's level 2 re-codes the Control letters too: each is the letter
    /// with Control, as its C0 byte reads, and a capital where Shift was held.
    @Test("The Control letters xterm's level 2 re-codes are the letters with Control")
    func controlLettersAtLevelTwo() {
        #expect(parse("[27;5;113~") == KeyEvent.parse([0x11]))
        #expect(parse("[113;5u") == KeyEvent(key: .character("q"), ctrl: true))
        #expect(parse("[27;6;65~") == KeyEvent(key: .character("A"), ctrl: true, shift: true))
        #expect(parse("[27;6;97~") == KeyEvent(key: .character("A"), ctrl: true, shift: true))
        // Ctrl-H is Backspace's byte where nothing binds the chord.
        #expect(parse("[27;5;104~")?.legacyControlEquivalent == KeyEvent(key: .backspace))
    }

    @Test("Meta in the modifier code is Option, as in every legacy CSI key")
    func metaIsOption() {
        #expect(parse("[27;9;13~") == KeyEvent(key: .enter, alt: true))
        #expect(parse("[13;3u") == KeyEvent(key: .enter, alt: true))
    }

    /// The same code and modifiers are one key whichever encoding brought
    /// them: the legacy reading of `CSI code ; mods u` is the kitty decoder's,
    /// for the modifiers the two read alike (Shift, Option, Control).
    @Test("A CSI u key reads as the kitty decoder reads it", arguments: [9, 13, 27, 32, 49, 65, 97, 113, 127, 0xE9])
    func matchesKittyDecoder(code: Int) {
        for modifier in 1...8 {
            let bytes = [0x1B] + Array("[\(code);\(modifier)u".utf8)
            guard case .key(let kitty)? = KittyKeyDecoder.decode(bytes)?.first else {
                Issue.record("kitty decoder read nothing for \(code);\(modifier)")
                continue
            }
            #expect(KeyEvent.parse(bytes) == kitty, "code \(code), modifier \(modifier)")
        }
    }

    @Test(
        "A malformed or foreign extended key is dropped",
        arguments: [
            "[27;0;13~", "[27;17;13~", "[27;2~", "[27;2;13;1~", "[27;;13~", "[27;2;-13~",
            "[13;2;5u", "[;2u", "[u", "[?1u", "[>1u", "[13;0u", "[57399;1u", "[27;2;1~", "[1;2u",
        ])
    func malformedIsDropped(sequence: String) {
        #expect(parse(sequence) == nil)
    }

    @Test("A key numbered 27 is not taken for the extended form")
    func plainTildeKeysUnchanged() {
        #expect(parse("[27~") == nil)
        #expect(parse("[3;2~") == KeyEvent(key: .delete, shift: true))
    }
}
