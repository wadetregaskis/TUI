//  🖥️ TUI — A Terminal UI framework for Swift
//  KittyKeyDecoderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

/// The kitty keyboard protocol's key reports, decoded.
///
/// The shapes are the specification's
/// (<https://sw.kovidgoyal.net/kitty/keyboard-protocol/>), as a terminal with
/// flags 1, 2, 4, 8 and 16 pushed sends them; Ghostty's Option chords and
/// Windows Terminal's whole run of keys are as captured (see
/// `Documentation/Terminals/Terminal compatibility survey.md`).
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

    @Test("Text the key typed with Option is the text, without Option, noting the key Option composed it from")
    func optionComposedText() {
        // Option-S on a Mac layout types ß; a legacy terminal sends ß alone.
        let decoded = decode("115;3;223u")
        #expect(decoded == key(composed("ß", from: "s")))
        if case .key(let event)? = decoded?.first {
            #expect(event.key == .character("ß") && !event.alt)
            #expect(event.optionChord == KeyEvent(key: .character("s"), alt: true))
        }
    }

    /// Ghostty 1.4.0 with its default Option setting, measured by the owner
    /// (2026-10-28, `keyboard_events_probe.py`): ⌥F, ⌥⇧F, ⌥/ and ⌥⇧/.
    @Test("Ghostty's Option chords that composed text carry the key and Shift they were made with")
    func ghosttyOptionChords() {
        #expect(decode("102;3;402u") == key(composed("ƒ", from: "f")))
        #expect(decode("102:207;4;207u") == key(composed("Ï", from: "F")))
        #expect(decode("47;3;247u") == key(composed("÷", from: "/")))
        #expect(decode("47:191;4;191u") == key(composed("¿", from: "?")))
        // Control as well is no composition; nor a key that typed itself.
        #expect(KittyKeyDecoder.optionComposedKey(code: 102, bits: 2 | 4, text: "f") == nil)
        #expect(KittyKeyDecoder.optionComposedKey(code: 102, bits: 2, text: "f") == nil)
        // ⌘, Hyper or Meta held too make another chord, not ⌥ alone.
        for other in [8, 16, 32] {
            #expect(KittyKeyDecoder.optionComposedKey(code: 102, bits: 2 | other, text: "ƒ") == nil)
        }
        // The key's own character under Caps Lock (64) or Shift (1): nothing
        // composed, as without them.
        #expect(KittyKeyDecoder.optionComposedKey(code: 102, bits: 2 | 64, text: "F") == nil)
        #expect(KittyKeyDecoder.optionComposedKey(code: 102, bits: 2 | 1, text: "F") == nil)
        #expect(KittyKeyDecoder.optionComposedKey(code: 47, bits: 2 | 1, text: "?") == nil)
    }

    /// The event a text report decodes to where Option composed `text` from
    /// `base`.
    private func composed(_ text: Character, from base: Character) -> KeyEvent {
        KeyEvent(
            key: .character(text), shift: text.isUppercase, pasteAttachments: [],
            optionComposedKey: .character(base))
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

    @Test("A chord on ⌘ is delivered with Command (B-D1K-1)")
    func commandChordDelivered() {
        #expect(decode("107;9u") == key(KeyEvent(key: .character("k"), command: true)))
        #expect(decode("1;9A") == key(KeyEvent(key: .up, command: true)))
        #expect(decode("3;9~") == key(KeyEvent(key: .delete, command: true)))
        // ⌘⇧K is K, its Shift the letter's case, as for a Control chord.
        #expect(decode("107:75;10u") == key(KeyEvent(key: .character("K"), shift: true, command: true)))
        // ⌘С on a Russian layout is ⌘C, as macOS matches a key equivalent.
        #expect(decode("1089::99;9u") == key(KeyEvent(key: .character("c"), command: true)))
    }

    @Test("A chord on Hyper or Meta is still dropped, reporting only the modifier state")
    func hyperAndMetaChordsDropped() {
        #expect(decode("107;17u") == [.modifierKeys(ModifierKeyState())])
        #expect(decode("107;33u") == [.modifierKeys(ModifierKeyState())])
        #expect(decode("107;25u") == [.modifierKeys(ModifierKeyState(command: true))], "⌘ with Hyper")
    }

    @Test("A ⌘ chord's release is its press, Command and all")
    func commandChordRelease() {
        var memory = KittyKeyMemory()
        _ = KittyKeyDecoder.decode(Array("\u{1B}[107;9u".utf8), memory: &memory)
        #expect(
            KittyKeyDecoder.decode(Array("\u{1B}[107;9:3u".utf8), memory: &memory)
                == key(KeyEvent(key: .character("k"), command: true, phase: .release)))
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

    /// Windows Terminal 1.25.3131.0 with all 31 flags, measured by the owner
    /// (2026-11-19, `keyboard_events_probe.py`, a Mac keyboard into a Windows
    /// 11 VM), report by report, the paste's text left out. Its own bindings
    /// took three chords' presses: ⌃- (its font size) and ⌃⇧V (its paste)
    /// arrive as their releases alone, and ⌃, (its settings) and ⌥⇧- (a
    /// split pane) as their modifiers alone. The terminal's ⌃ press before F1
    /// is the one ⌃, left behind, its release taken by the settings tab.
    @Test("Windows Terminal's keys, as it sent them")
    func windowsTerminalCapture() {
        let a = KeyEvent(key: .character("a"))
        let capitalA = KeyEvent(key: .character("A"), shift: true)
        let bang = KeyEvent(character: "!")
        let capsA = KeyEvent(key: .character("A"), shift: true, capsLock: true)
        let z = KeyEvent(key: .character("Z"), ctrl: true, shift: true)
        let underscore = KeyEvent(key: .character("_"), ctrl: true)
        let v = KeyEvent(key: .character("V"), ctrl: true, shift: true)
        func ctrl(_ letter: Character) -> KeyEvent { KeyEvent(key: .character(letter), ctrl: true) }
        func up(_ event: KeyEvent) -> KeyEvent {
            KeyEvent(
                key: event.key, ctrl: event.ctrl, alt: event.alt, shift: event.shift, phase: .release,
                capsLock: event.capsLock)
        }
        let control = (press: "57442;5u", release: "57442;1:3u")
        var reports: [(String, KeyEvent?)] = [
            ("97;;97u", a), ("97;1:3u", up(a)),
            ("57447;2u", nil), ("97:65;2;65u", capitalA), ("97:65;2:3u", up(capitalA)), ("57447;1:3u", nil),
            ("57447;2u", nil), ("49:33;2;33u", bang), ("49:33;2:3u", up(bang)), ("57447;1:3u", nil),
            ("57358;65u", nil), ("57358;65:3u", nil), ("97;65;65u", capsA), ("97;65:3u", up(capsA)),
            ("57358u", nil), ("57358;1:3u", nil),
        ]
        for letter: Character in ["h", "i", "m", "[", "q", "\\"] {
            let code = Int(letter.unicodeScalars.first!.value)
            reports += [
                (control.press, nil), ("\(code);5u", ctrl(letter)), ("\(code);5:3u", up(ctrl(letter))),
                (control.release, nil),
            ]
        }
        reports += [
            ("27u", KeyEvent(key: .escape)), ("27;1:3u", KeyEvent(key: .escape, phase: .release)),
            (control.press, nil), ("57441;6u", nil), ("122:90;6u", z), ("122:90;6:3u", up(z)),
            ("57442;2:3u", nil), ("57441;1:3u", nil),
            // ⌃-: the font size's.
            (control.press, nil), ("45;5:3u", up(ctrl("-"))), (control.release, nil),
            (control.press, nil), ("57441;6u", nil), ("45:95;6u", underscore), ("45:95;6:3u", up(underscore)),
            ("57441;5:3u", nil), (control.release, nil),
            // ⌥⇧-: a split pane's.
            ("57443;3u", nil), ("57441;4u", nil), ("57441;1:3u", nil), ("57443;3u", nil), ("57443;1:3u", nil),
            // ⌃,: the settings'.
            (control.press, nil), (control.release, nil), (control.press, nil),
        ]
        for (press, key) in [("P", Key.f1), ("Q", .f2), ("H", .home), ("F", .end)] {
            reports += [(press, KeyEvent(key: key)), ("1;1:3\(press)", KeyEvent(key: key, phase: .release))]
        }
        for (number, key) in [(21, Key.f10), (5, .pageUp)] {
            reports += [("\(number)~", KeyEvent(key: key)), ("\(number);1:3~", KeyEvent(key: key, phase: .release))]
        }
        for (number, key) in [(9, Key.tab), (13, .enter), (127, .backspace)] {
            reports += [("\(number)u", KeyEvent(key: key)), ("\(number);1:3u", KeyEvent(key: key, phase: .release))]
        }
        reports += [(control.press, nil), (control.release, nil), ("B", KeyEvent(key: .down))]
        reports += Array(repeating: ("1;1:2B", KeyEvent(key: .down, phase: .repeat)), count: 18)
        reports += [
            ("1;1:3B", KeyEvent(key: .down, phase: .release)),
            // ⌃⇧V: the paste's, its text between the presses and the release.
            (control.press, nil), ("57441;6u", nil), ("118:86;6:3u", up(v)), ("57441;5:3u", nil),
            (control.release, nil),
            (control.press, nil), ("99;5u", ctrl("c")),
        ]
        let decoded = decodeInTurn(reports.map(\.0))
        for ((body, expected), inputs) in zip(reports, decoded) {
            #expect(inputs != nil, "\(body) is a key report")
            #expect(
                (inputs ?? []).compactMap(\.keyEvent) == (expected.map { [$0] } ?? []), "\(body)")
        }
        // ⌃C's report leaves Control held, as it is, and nothing else.
        var memory = KittyKeyMemory()
        var last: ModifierKeyState?
        for body in reports.map(\.0) {
            for input in KittyKeyDecoder.decode(Array("\u{1B}[\(body)".utf8), memory: &memory) ?? [] {
                if case .modifierKeys(let state) = input { last = state }
            }
        }
        #expect(last == ModifierKeyState(control: true))
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

    @Test("F13 to F20 and Menu by their private-use numbers; keys TUI has no key for are dropped")
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
