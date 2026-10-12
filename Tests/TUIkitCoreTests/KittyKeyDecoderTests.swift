//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyKeyDecoderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The kitty keyboard protocol's key reports, decoded.
///
/// The shapes are the specification's
/// (<https://sw.kovidgoyal.net/kitty/keyboard-protocol/>), as a terminal with
/// flags 1, 2, 4, 8 and 16 pushed sends them. No terminal has been captured
/// sending them yet; see `Documentation/Terminals/Terminal compatibility survey.md`.
@Suite("Kitty keyboard protocol decoding")
struct KittyKeyDecoderTests {

    /// Decodes `CSI <body>`.
    private func decode(_ body: String) -> [TerminalInput]? {
        KittyKeyDecoder.decode(Array("\u{1B}[\(body)".utf8))
    }

    private func key(_ event: KeyEvent) -> [TerminalInput] { [.key(event)] }

    // MARK: Text keys

    @Test("A letter that typed text is that text")
    func letterWithText() {
        #expect(decode("97;;97u") == key(KeyEvent(key: .character("a"))))
    }

    @Test("Shift on a typed key is the text's case, as KeyEvent(character:) reads a legacy byte")
    func shiftedPrintable() {
        #expect(decode("97:65;2;65u") == key(KeyEvent(key: .character("A"), shift: true)))
        #expect(decode("97:65;2;65u") == key(KeyEvent(character: "A")))
        #expect(decode("49:33;2;33u") == key(KeyEvent(character: "!")))
        #expect(decode("61:43;2;43u") == key(KeyEvent(character: "+")))
        #expect(decode("45:95;2;95u") == key(KeyEvent(character: "_")))
    }

    @Test("Text the key typed with Option is the text, without Option")
    func optionComposedText() {
        // Option-S on a Mac layout types ß; a legacy terminal sends ß alone.
        #expect(decode("115;3;223u") == key(KeyEvent(key: .character("ß"))))
    }

    @Test("A key that typed several characters is one event per character")
    func multiCharacterText() {
        #expect(
            decode("0;;26085:26412u")
                == [.key(KeyEvent(key: .character("日"))), .key(KeyEvent(key: .character("本")))])
    }

    @Test("Space with text is the space key")
    func spaceWithText() {
        #expect(decode("32;;32u") == key(KeyEvent(key: .space)))
        #expect(decode("32;2;32u") == key(KeyEvent(key: .space)))
    }

    @Test("Caps Lock is reported, and its capital carries Shift as the legacy byte does")
    func capsLock() {
        #expect(
            decode("97;65;65u") == key(KeyEvent(key: .character("A"), shift: true, capsLock: true)))
    }

    @Test("A text-carrying report with a control code in its text falls back to its key")
    func controlCodeText() {
        #expect(decode("97;;1u") == key(KeyEvent(key: .character("a"))))
    }

    // MARK: Chords

    @Test("Control and Option chords on a letter")
    func controlAndOptionChords() {
        #expect(decode("97;5u") == key(KeyEvent(key: .character("a"), ctrl: true)))
        #expect(decode("97;3u") == key(KeyEvent(key: .character("a"), alt: true)))
        #expect(decode("97;7u") == key(KeyEvent(key: .character("a"), ctrl: true, alt: true)))
    }

    @Test("Ctrl-H, I, J, M and [ arrive as themselves")
    func controlChordsTheLegacyBytesSpentElsewhere() {
        for letter in "hijm[" {
            let code = Int(letter.unicodeScalars.first!.value)
            #expect(decode("\(code);5u") == key(KeyEvent(key: .character(letter), ctrl: true)))
        }
    }

    @Test("A shifted chord is its shifted key, Shift its case: Ctrl-Shift-Z is Z, Ctrl-Shift-minus is _")
    func shiftedChordUsesShiftedKey() {
        #expect(
            decode("122:90;6u") == key(KeyEvent(key: .character("Z"), ctrl: true, shift: true)))
        #expect(decode("45:95;6u") == key(KeyEvent(key: .character("_"), ctrl: true)))
        #expect(decode("45:95;4u") == key(KeyEvent(key: .character("_"), alt: true)))
        #expect(decode("45;5u") == key(KeyEvent(key: .character("-"), ctrl: true)))
    }

    @Test("Without the shifted key reported, a shifted letter is its capital and anything else keeps the bit")
    func shiftedChordWithoutAlternateKeys() {
        #expect(decode("122;6u") == key(KeyEvent(key: .character("Z"), ctrl: true, shift: true)))
        #expect(decode("45;6u") == key(KeyEvent(key: .character("-"), ctrl: true, shift: true)))
    }

    @Test("A chord on a non-Latin layout is its base-layout key")
    func baseLayoutKey() {
        // Ctrl-С on a Russian layout: С is U+0441, at C's place.
        #expect(decode("1089::99;5u") == key(KeyEvent(key: .character("c"), ctrl: true)))
    }

    @Test("A chord on ⌘ is dropped, reporting only the modifier state")
    func commandChordDropped() {
        #expect(decode("107;9u") == [.modifierKeys(ModifierKeyState(command: true))])
        #expect(decode("1;9A") == [.modifierKeys(ModifierKeyState(command: true))])
    }

    // MARK: Phases

    @Test("A repeat and a release are reported")
    func repeatAndRelease() {
        #expect(decode("97;1:2;97u") == key(KeyEvent(key: .character("a"), phase: .repeat)))
        #expect(decode("97;1:3u") == key(KeyEvent(key: .character("a"), phase: .release)))
        #expect(decode("1;1:3A") == key(KeyEvent(key: .up, phase: .release)))
        #expect(decode("5;1:2~") == key(KeyEvent(key: .pageUp, phase: .repeat)))
    }

    @Test("A release carries no text, and is decoded from its key")
    func releaseIgnoresText() {
        #expect(decode("97:65;2:3u") == key(KeyEvent(key: .character("A"), shift: true, phase: .release)))
    }

    /// Decodes each `CSI <body>` in turn, remembering between them as the
    /// live parser does.
    private func decodeInTurn(_ bodies: [String]) -> [[TerminalInput]?] {
        var memory = KittyKeyMemory()
        return bodies.map { KittyKeyDecoder.decode(Array("\u{1B}[\($0)".utf8), memory: &memory) }
    }

    /// ``decodeInTurn(_:)``'s key events alone, for a test of keys rather
    /// than of the modifier state reported beside them.
    private func keysInTurn(_ bodies: [String]) -> [[TerminalInput]] {
        decodeInTurn(bodies).map { ($0 ?? []).filter { $0.keyEvent != nil } }
    }

    @Test("A release is the key its press was: Caps Lock's A comes up as A, a dead key's é as é")
    func releaseMatchesPress() {
        #expect(
            keysInTurn(["97;65;65u", "97;65:3u"])
                == [
                    key(KeyEvent(key: .character("A"), shift: true, capsLock: true)),
                    key(KeyEvent(key: .character("A"), shift: true, phase: .release, capsLock: true)),
                ])
        #expect(
            keysInTurn(["101;;233u", "101;1:3u"])
                == [key(KeyEvent(key: .character("é"))), key(KeyEvent(key: .character("é"), phase: .release))])
        // Shift let go before the key: still the key that went down.
        #expect(
            keysInTurn(["97:65;2;65u", "97;1:3u"]).last
                == key(KeyEvent(key: .character("A"), shift: true, phase: .release)))
        // A chord's release is the chord's key too.
        #expect(
            keysInTurn(["122:90;6u", "122;5:3u"]).last
                == key(KeyEvent(key: .character("Z"), ctrl: true, shift: true, phase: .release)))
    }

    @Test("A release of a key not seen going down is decoded from its code, and a release is remembered once")
    func releaseWithoutPress() {
        #expect(keysInTurn(["97;1:3u"]) == [key(KeyEvent(key: .character("a"), phase: .release))])
        #expect(
            keysInTurn(["97;65;65u", "97;65:3u", "97;1:3u"]).last
                == key(KeyEvent(key: .character("a"), phase: .release)))
    }

    // MARK: Modifier state across reports

    @Test("With both Shift keys held, letting one go leaves Shift held, whatever bit the report carries")
    func twoShiftKeys() {
        let shift = [TerminalInput.modifierKeys(ModifierKeyState(shift: true))]
        let none = [TerminalInput.modifierKeys(ModifierKeyState())]
        #expect(decodeInTurn(["57441;2u", "57447;2u", "57441;2:3u", "57447;1:3u"]) == [shift, shift, shift, none])
        #expect(decodeInTurn(["57441;2u", "57447;2u", "57441;1:3u"]).last == shift)
    }

    @Test("A key report whose modifiers disagree with the last state reports the state first")
    func keyReportResyncs() {
        // Shift's release was missed: the next key says it is up.
        #expect(
            decodeInTurn(["57441;2u", "97;1;97u"]).last
                == [.modifierKeys(ModifierKeyState()), .key(KeyEvent(key: .character("a")))])
        // Control's press was missed: the chord says it is down.
        #expect(
            decodeInTurn(["97;5u"])
                == [[.modifierKeys(ModifierKeyState(control: true)), .key(KeyEvent(key: .character("a"), ctrl: true))]])
        // Agreeing, nothing more.
        #expect(
            decodeInTurn(["57441;2u", "97:65;2;65u"]).last
                == [.key(KeyEvent(key: .character("A"), shift: true))])
        // A missed release is forgotten as a key held, so the other Shift's
        // release is the last.
        #expect(
            decodeInTurn(["57441;2u", "97;1;97u", "57447;2u", "57447;1:3u"]).last
                == [.modifierKeys(ModifierKeyState())])
    }

    @Test("Losing the focus forgets what is held and reports it released, Caps Lock kept")
    func focusLost() {
        var memory = KittyKeyMemory()
        _ = KittyKeyDecoder.decode(Array("\u{1B}[57441;66u".utf8), memory: &memory)
        #expect(
            KittyKeyDecoder.focusLost(memory: &memory) == .modifierKeys(ModifierKeyState(capsLock: true)))
        #expect(KittyKeyDecoder.focusLost(memory: &memory) == nil, "nothing more to release")
        #expect(
            KittyKeyDecoder.decode(Array("\u{1B}[97;65;65u".utf8), memory: &memory)
                == key(KeyEvent(key: .character("A"), shift: true, capsLock: true)))
    }

    @Test("An unknown event type is dropped as malformed")
    func unknownEventType() {
        #expect(decode("97;1:4u") == nil)
    }

    // MARK: Functional keys

    @Test("Escape, Return, Tab and Backspace by their C0 numbers")
    func controlKeys() {
        #expect(decode("27u") == key(KeyEvent(key: .escape)))
        #expect(decode("13u") == key(KeyEvent(key: .enter)))
        #expect(decode("13;2u") == key(KeyEvent(key: .enter, shift: true)))
        #expect(decode("9;2u") == key(KeyEvent(key: .tab, shift: true)))
        #expect(decode("127u") == key(KeyEvent(key: .backspace)))
    }

    @Test("Arrows, Home, End and F1, F2, F4 in the letter form")
    func letterForm() {
        #expect(decode("A") == key(KeyEvent(key: .up)))
        #expect(decode("1;2D") == key(KeyEvent(key: .left, shift: true)))
        #expect(decode("1;5H") == key(KeyEvent(key: .home, ctrl: true)))
        #expect(decode("P") == key(KeyEvent(key: .f1)))
        #expect(decode("1;2S") == key(KeyEvent(key: .f4, shift: true)))
    }

    @Test("The tilde form, F3 included, and Insert dropped")
    func tildeForm() {
        #expect(decode("3~") == key(KeyEvent(key: .delete)))
        #expect(decode("13~") == key(KeyEvent(key: .f3)))
        #expect(decode("24;5~") == key(KeyEvent(key: .f12, ctrl: true)))
        #expect(decode("7~") == key(KeyEvent(key: .home)))
        #expect(decode("2~")?.isEmpty == true)
    }

    @Test("Keypad keys are reported as the keypad")
    func keypad() {
        #expect(decode("57404;129;53u") == key(KeyEvent(key: .character("5"), numericPad: true)))
        #expect(decode("57414u") == key(KeyEvent(key: .enter, numericPad: true)))
        #expect(decode("57419u") == key(KeyEvent(key: .up, numericPad: true)))
    }

    @Test("F13 to F20 and Menu by their private-use numbers; keys TUIkit has no key for are dropped")
    func privateUseKeys() {
        #expect(decode("57376u") == key(KeyEvent(key: .f13)))
        #expect(decode("57363u") == key(KeyEvent(key: .menu)))
        #expect(decode("57361u")?.isEmpty == true)  // Print Screen
        #expect(decode("57430u")?.isEmpty == true)  // Play/Pause
    }

    // MARK: Modifier keys

    @Test("A modifier key on its own reports the state it leaves")
    func modifierKeys() {
        #expect(decode("57441;2u") == [.modifierKeys(ModifierKeyState(shift: true))])
        #expect(decode("57441;1:3u") == [.modifierKeys(ModifierKeyState())])
        // Pressing Option with Shift held.
        #expect(
            decode("57443;4u") == [.modifierKeys(ModifierKeyState(shift: true, option: true))])
        // ⌘, as Super.
        #expect(decode("57444;9u") == [.modifierKeys(ModifierKeyState(command: true))])
    }

    @Test("A modifier key's own bit follows its event, whatever the terminal reported")
    func modifierKeyOwnBit() {
        // A terminal reporting the state from before the event.
        #expect(decode("57442;1u") == [.modifierKeys(ModifierKeyState(control: true))])
        #expect(decode("57442;5:3u") == [.modifierKeys(ModifierKeyState())])
    }

    @Test("Caps Lock's key reports the lock state as the terminal gives it")
    func capsLockKey() {
        #expect(decode("57358;65u") == [.modifierKeys(ModifierKeyState(capsLock: true))])
    }

    // MARK: Not keys

    @Test("Replies and mouse reports are not key reports")
    func repliesAreNotKeys() {
        #expect(decode("?31u") == nil)
        #expect(decode("<0;10;5M") == nil)
        #expect(decode(">1u") == nil)
        #expect(decode("?62;22c") == nil)
        #expect(decode("24;80R") == nil)
    }

    @Test("Malformed numbers are dropped")
    func malformed() {
        #expect(decode("-97u") == nil)
        #expect(decode("99999999999999999999999u") == nil)
        #expect(decode("97;999u") == nil)
        #expect(decode("1114112u") == nil)  // beyond U+10FFFF
    }
}
