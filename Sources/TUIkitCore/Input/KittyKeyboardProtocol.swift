//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyKeyboardProtocol.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Decoding

/// Decodes the kitty keyboard protocol's key reports.
///
/// Used only while the protocol is on — the run loop pushed flags, and the
/// terminal said it took them — because the protocol gives the shared legacy
/// forms a different meaning. In xterm's `CSI 1 ; 9 A`, the 8 bit is Meta,
/// which terminals send for Option, and `KeyEvent.parse` reads it as Option;
/// in the protocol's, the same bit is Super, the ⌘ key.
///
/// Every shape the protocol sends a key in arrives through here:
///
/// - `CSI code[:shifted[:base]] ; mods[:event] ; text u` — a key reported by
///   its Unicode code point, or by a private-use number for a key that types
///   nothing (the keypad, the lock keys, the modifier keys themselves).
/// - `CSI number ; mods[:event] ~` — the editing and function keys, in their
///   legacy numbering.
/// - `CSI 1 ; mods[:event] A…S` — the arrows, Home, End and F1, F2, F4.
///
/// A malformed report — a sign, an overflowing number, an unknown event type,
/// a code point that is not one — is dropped as a unit, the contract every
/// parser here keeps (see `ASCIIDecimal`).
package enum KittyKeyDecoder {

    /// The events one complete CSI sequence reports, or `nil` when it is not a
    /// key report in the protocol's grammar, so the legacy parser should have
    /// it.
    ///
    /// An empty array means a report this framework has no key for — Print
    /// Screen, a media key, F21 and up — or one it deliberately drops: a
    /// chord on ⌘ that types nothing (see ``decode(_:)``'s discussion).
    ///
    /// Usually one event. More than one only when a key typed more than one
    /// character — an input method committing a word through one key, a
    /// compose sequence — which arrive as one key event each, as their bytes
    /// would have in a legacy encoding.
    ///
    /// ## Text, and the modifiers it consumed
    ///
    /// A report that carries text is the text: its key is the text's
    /// character, as the legacy encoding sends it, and it carries the
    /// modifiers the legacy encoding's byte implies, not the ones the report
    /// says were held. Control and Option are dropped, because the text
    /// already includes what they did: Option-E then E arrives as `é`, and a
    /// terminal not treating Option as Alt reports Option on a key that typed
    /// `å`. Shift is the text's case — `true` on an uppercase letter, `false`
    /// on everything else, `!` and `+` included — which is what
    /// `KeyEvent(character:)` makes of a legacy byte. The text already says
    /// what Shift did, and a handler written against a legacy terminal (a
    /// `Stepper` whose Shift-arrow steps by five, say) must not find a Shift
    /// it never saw on the same key there. The same goes for a chord whose key
    /// is its shifted character (Ctrl-Shift-Z as `Z`, Option-Shift-minus as
    /// `_`): Shift is that character's case.
    ///
    /// ## ⌘, and the other modifiers a terminal never used to send
    ///
    /// Super (⌘ on the macOS hosts), Hyper and Meta never arrive in a legacy
    /// encoding: the terminal keeps ⌘ chords for itself or sends nothing. Under
    /// the protocol, a ⌘ chord the terminal does not claim reaches the app.
    /// Delivered as the bare key, ⌘K would type a `k` into a text field and
    /// fire every bare-`k` binding, so a chord on any of the three that types
    /// no text is dropped, as the legacy encodings drop it. It still reports
    /// the modifier state, so ``ModifierKeyState/command`` stays true while ⌘
    /// is held.
    ///
    /// ## A release is the key its press was
    ///
    /// A release carries no text, only the key's code, so decoded on its own
    /// it could disagree with the press: Caps Lock's `A` would come up as `a`,
    /// a dead key's `é` as `e`. A key's press is remembered in `memory`, and
    /// its release delivers the press's key events again, phase aside (see
    /// ``KittyKeyMemory``). A release of a key not seen going down is decoded
    /// from its code.
    package static func decode(_ bytes: [UInt8], memory: inout KittyKeyMemory) -> [TerminalInput]? {
        guard bytes.count >= 3, bytes[0] == 0x1B, bytes[1] == 0x5B,
            let final = bytes.last
        else { return nil }
        let body = bytes[2..<(bytes.count - 1)]
        // A private marker (`?`, `<`, `=`, `>`) makes it a reply or a mouse
        // report, never a key.
        if let first = body.first, (0x3C...0x3F).contains(first) { return nil }
        guard let fields = Self.fields(body) else { return nil }

        let decoded: [TerminalInput]?
        switch final {
        case 0x75:  // 'u'
            // A modifier key's own report is the state, and sets it itself.
            if modifierKey(value(fields, 0, 0) ?? 0) != nil {
                return decodeModifierKeyReport(fields, memory: &memory)
            }
            decoded = decodeCodePointReport(fields, memory: &memory)
        case 0x7E:  // '~'
            guard let number = value(fields, 0, 0) else { return nil }
            guard let key = Self.tildeKey(number) else { return nil }
            decoded = decodeFunctionalKey(key, fields: fields)
        default:
            guard let key = Self.letterKey(final) else { return nil }
            // `CSI 1 ; mods A`, or the bare `CSI A`: the number is always 1.
            if let number = value(fields, 0, 0), number != 1 { return nil }
            decoded = decodeFunctionalKey(key, fields: fields)
        }
        guard let decoded, let (bits, _) = modifiers(fields) else { return nil }
        return resynced(decoded, bits: bits, memory: &memory)
    }

    /// What the input parser reports when the terminal loses the focus: the
    /// modifier keys released, if any was held.
    ///
    /// A key or modifier let go while another window has the focus is not
    /// reported to this one, so a ⌘ held for ⌘-Tab would otherwise stay held
    /// here until ⌘ was pressed again. Everything down is forgotten, and Caps
    /// Lock, which is a state of the keyboard rather than a key held, is kept.
    /// The next key report after the focus comes back says what is held then.
    package static func focusLost(memory: inout KittyKeyMemory) -> TerminalInput? {
        memory.pressed.removeAll()
        memory.heldModifierKeys.removeAll()
        guard let reported = memory.reportedState else { return nil }
        let released = ModifierKeyState(capsLock: reported.capsLock)
        guard released != reported else { return nil }
        memory.reportedState = released
        return .modifierKeys(released)
    }

    /// What the input parser reports when the protocol is popped — on the way
    /// into a suspend, or out of the app: every modifier released, Caps Lock
    /// off, if the state last reported was anything else; and `memory` is
    /// forgotten.
    ///
    /// The state the app goes on with must be the one the forgotten memory
    /// starts from. Whatever is let go of while the shell has the terminal is
    /// not reported to the app, and a key report after the resume is compared
    /// with the fresh memory's "nothing held": a Ctrl held for the Ctrl-Z that
    /// suspended the app, and released in the shell, matched it, so nothing
    /// was reported and the app believed Ctrl held until it was pressed again.
    /// Caps Lock goes with the rest, unlike at a focus loss, because the fresh
    /// memory starts it off; the first key report after the resume says
    /// whether it is on.
    package static func protocolPopped(memory: inout KittyKeyMemory) -> TerminalInput? {
        let reported = memory.reportedState
        memory = KittyKeyMemory()
        guard let reported, let fresh = memory.reportedState, reported != fresh else { return nil }
        return .modifierKeys(fresh)
    }

    /// `decoded`, after a report of the modifier state when `bits` disagree
    /// with the one last reported.
    ///
    /// Every key report carries the modifiers held, and a modifier key's own
    /// press or release can go missing — let go while another window had the
    /// focus, held since before the app started. Without this the state stayed
    /// wrong until that modifier was pressed and released again. A modifier
    /// the bits say is up is also forgotten as a key held.
    private static func resynced(
        _ decoded: [TerminalInput], bits: Int, memory: inout KittyKeyMemory
    ) -> [TerminalInput] {
        let reported = state(bits)
        memory.heldModifierKeys = memory.heldModifierKeys.filter { code in
            switch modifierKey(code) {
            case .shift: reported.shift
            case .control: reported.control
            case .option: reported.option
            case .command: reported.command
            case .other, nil: true
            }
        }
        guard let last = memory.reportedState, reported != last else { return decoded }
        memory.reportedState = reported
        // A dropped ⌘ chord already is this report.
        if decoded == [.modifierKeys(reported)] { return decoded }
        return [.modifierKeys(reported)] + decoded
    }

    /// ``decode(_:memory:)`` for one report on its own, with nothing
    /// remembered before it or kept after.
    package static func decode(_ bytes: [UInt8]) -> [TerminalInput]? {
        var memory = KittyKeyMemory.oneReport
        return decode(bytes, memory: &memory)
    }

    // MARK: Grammar

    /// The report's `;`-separated fields, each a list of its `:`-separated
    /// sub-fields, an empty sub-field being `nil`; `nil` for a byte the grammar
    /// does not allow or a number that does not fit.
    private static func fields(_ body: ArraySlice<UInt8>) -> [[Int?]]? {
        var fields: [[Int?]] = [[]]
        var digits: [UInt8] = []
        func closeSubfield() -> Bool {
            if digits.isEmpty {
                fields[fields.count - 1].append(nil)
                return true
            }
            guard let value = ASCIIDecimal.value(of: digits) else { return false }
            fields[fields.count - 1].append(value)
            digits.removeAll(keepingCapacity: true)
            return true
        }
        for byte in body {
            switch byte {
            case 0x30...0x39: digits.append(byte)
            case 0x3A:  // ':'
                guard closeSubfield() else { return nil }
            case 0x3B:  // ';'
                guard closeSubfield() else { return nil }
                fields.append([])
            default: return nil
            }
        }
        guard closeSubfield() else { return nil }
        return fields
    }

    /// Sub-field `sub` of field `field`, or `nil` when the report leaves it
    /// out or empty.
    private static func value(_ fields: [[Int?]], _ field: Int, _ sub: Int) -> Int? {
        guard field < fields.count, sub < fields[field].count else { return nil }
        return fields[field][sub]
    }

    /// The modifier bits and the event type, read from the second field;
    /// `nil` for an out-of-range value.
    private static func modifiers(_ fields: [[Int?]]) -> (bits: Int, phase: KeyEvent.Phase)? {
        let encoded = value(fields, 1, 0) ?? 1
        guard encoded >= 1, encoded <= 256 else { return nil }
        let phase: KeyEvent.Phase
        switch value(fields, 1, 1) ?? 1 {
        case 1: phase = .press
        case 2: phase = .repeat
        case 3: phase = .release
        default: return nil
        }
        return (encoded - 1, phase)
    }

    // The protocol's modifier bits.
    private static let shiftBit = 1
    private static let altBit = 2
    private static let ctrlBit = 4
    private static let superBit = 8
    private static let hyperBit = 16
    private static let metaBit = 32
    private static let capsLockBit = 64

    /// The state the modifier bits describe.
    private static func state(_ bits: Int) -> ModifierKeyState {
        ModifierKeyState(
            shift: bits & shiftBit != 0, control: bits & ctrlBit != 0, option: bits & altBit != 0,
            command: bits & superBit != 0, capsLock: bits & capsLockBit != 0)
    }

    /// Whether the bits hold a modifier the legacy encodings never deliver a
    /// key with: Super, Hyper or Meta.
    private static func holdsUndeliverableModifier(_ bits: Int) -> Bool {
        bits & (superBit | hyperBit | metaBit) != 0
    }

    // MARK: Keys

    /// A key event for `key` with the report's modifiers and phase.
    private static func event(
        _ key: Key, bits: Int, phase: KeyEvent.Phase, numericPad: Bool = false
    ) -> KeyEvent {
        KeyEvent(
            key: key, ctrl: bits & ctrlBit != 0, alt: bits & altBit != 0, shift: bits & shiftBit != 0,
            phase: phase, capsLock: bits & capsLockBit != 0, numericPad: numericPad)
    }

    /// A key reported in the legacy `~` or letter form.
    private static func decodeFunctionalKey(_ key: Key?, fields: [[Int?]]) -> [TerminalInput]? {
        guard let (bits, phase) = modifiers(fields) else { return nil }
        if holdsUndeliverableModifier(bits) { return [.modifierKeys(state(bits))] }
        guard let key else { return [] }
        return [.key(event(key, bits: bits, phase: phase))]
    }

    /// A modifier or lock key's own report: the state it leaves.
    ///
    /// The specification has the key's own bit include its own event, which
    /// not every terminal has always done, and a report of one Shift says
    /// nothing of the other. So a modifier that is held rather than toggled is
    /// set from the keys of its kind known to be down, this one included or
    /// not by its event: with both Shift keys held, letting one go leaves
    /// Shift held. Caps Lock toggles, so its bit is taken as reported, and the
    /// other modifiers' as reported too.
    private static func decodeModifierKeyReport(
        _ fields: [[Int?]], memory: inout KittyKeyMemory
    ) -> [TerminalInput]? {
        guard let (bits, phase) = modifiers(fields), let code = value(fields, 0, 0),
            let held = modifierKey(code)
        else { return nil }
        var state = state(bits)
        if held != .other {
            if phase == .release {
                memory.heldModifierKeys.remove(code)
            } else {
                memory.heldModifierKeys.insert(code)
            }
            let isDown = memory.heldModifierKeys.contains { modifierKey($0) == held }
            switch held {
            case .shift: state.shift = isDown
            case .control: state.control = isDown
            case .option: state.option = isDown
            case .command: state.command = isDown
            case .other: break
            }
        }
        if memory.reportedState != nil { memory.reportedState = state }
        return [.modifierKeys(state)]
    }

    /// A `CSI … u` report.
    private static func decodeCodePointReport(_ fields: [[Int?]], memory: inout KittyKeyMemory) -> [TerminalInput]? {
        guard let (bits, phase) = modifiers(fields) else { return nil }
        let code = value(fields, 0, 0) ?? 0
        let shifted = value(fields, 0, 1)
        let base = value(fields, 0, 2)

        // A release is the key its press was, whatever its own report says.
        if phase == .release, let pressed = memory.release(code) {
            return pressed.map { .key($0) }
        }

        // Text the key typed: the keystroke is that text.
        if phase != .release, fields.count > 2, let text = Self.text(fields[2]), !text.isEmpty {
            let events = textEvents(text, bits: bits, phase: phase, numericPad: isKeypad(code))
            memory.press(code, delivered: events.compactMap(\.keyEvent))
            return events
        }

        guard code != 0 else { return nil }  // key 0 is text-only, and there was none
        if holdsUndeliverableModifier(bits) { return [.modifierKeys(state(bits))] }
        if let functional = functionalKey(code) {
            guard let key = functional.key else { return [] }
            return [.key(event(key, bits: bits, phase: phase, numericPad: functional.isKeypad))]
        }

        let chord = chordKey(code: code, shifted: shifted, base: base, bits: bits)
        guard let key = Self.textKey(chord.code) else { return nil }
        let chordEvent = event(key, bits: chord.bits, phase: phase)
        if phase != .release { memory.press(code, delivered: [chordEvent]) }
        return [.key(chordEvent)]
    }

    /// The key a report that typed no text stands for — a Control or Option
    /// chord, a release, or a report from a terminal that sends no text — and
    /// the modifier bits it carries.
    ///
    /// The shifted key when Shift is held, so Ctrl-Shift-Z is `Z`; the
    /// base-layout key for a chord on a non-Latin layout, so Ctrl-С is Ctrl-C
    /// as its bytes are.
    private static func chordKey(code: Int, shifted: Int?, base: Int?, bits: Int) -> (code: Int, bits: Int) {
        if bits & shiftBit != 0, let shifted {
            // The shifted character says what Shift did, so Shift is its
            // case, as on a key that typed text (see ``decode(_:)``).
            return (shifted, isUppercaseLetter(shifted) ? bits : bits & ~shiftBit)
        }
        if bits & shiftBit != 0, let upper = uppercaseLetter(code) {
            // No shifted key reported (flag 4 not taken): a letter is its
            // capital all the same, as the legacy byte for Shift and it is.
            // Anything else keeps the bit, the only way left to say it.
            return (upper, bits)
        }
        if bits & (ctrlBit | altBit) != 0, code > 0x7F, let base {
            return (base, bits)
        }
        return (code, bits)
    }

    /// Whether `code` is an uppercase letter.
    private static func isUppercaseLetter(_ code: Int) -> Bool {
        guard let scalar = Unicode.Scalar(UInt32(clamping: code)) else { return false }
        return Character(scalar).isUppercase
    }

    /// The capital of a lowercase ASCII letter, or `nil` for anything else.
    private static func uppercaseLetter(_ code: Int) -> Int? {
        (0x61...0x7A).contains(code) ? code - 0x20 : nil
    }

    /// One key event per character of `text`, carrying the lock and keypad
    /// state, Shift as the character's case, and not the Control and Option
    /// the text consumed — the event `KeyEvent(character:)` makes of the same
    /// character's legacy byte, plus what only the protocol reports.
    private static func textEvents(
        _ text: String, bits: Int, phase: KeyEvent.Phase, numericPad: Bool
    ) -> [TerminalInput] {
        let kept = bits & capsLockBit
        return text.map { character in
            let key: Key = character == " " ? .space : .character(character)
            let shift = character.isUppercase ? shiftBit : 0
            return .key(event(key, bits: kept | shift, phase: phase, numericPad: numericPad))
        }
    }

    /// The text a report's third field spells, or `nil` for a code point that
    /// is not a Unicode scalar, or a control character, which the protocol
    /// never sends as text.
    private static func text(_ field: [Int?]) -> String? {
        var scalars = String.UnicodeScalarView()
        for value in field {
            guard let value, let scalar = Unicode.Scalar(UInt32(clamping: value)),
                scalar.value >= 0x20, !(0x7F...0x9F).contains(scalar.value)
            else { return nil }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// The key a code point that typed no text stands for: the four control
    /// keys the protocol reports by their C0 numbers, Space, or the character.
    private static func textKey(_ code: Int) -> Key? {
        switch code {
        case 27: return .escape
        case 13: return .enter
        case 9: return .tab
        case 127, 8: return .backspace
        case 32: return .space
        default:
            guard code > 0x20, !(0x7F...0x9F).contains(code),
                let scalar = Unicode.Scalar(UInt32(clamping: code))
            else { return nil }
            return .character(Character(scalar))
        }
    }

    // MARK: Tables

    /// Where the protocol's numbers for keys that type nothing begin, and end:
    /// the Basic Multilingual Plane's private-use area.
    private static let privateUseStart = 57_344
    private static let privateUseEnd = 63_743

    /// Which modifier a modifier or lock key is.
    private enum HeldModifier { case shift, control, option, command, other }

    /// The modifier a modifier or lock key's code stands for, or `nil` for any
    /// other key.
    private static func modifierKey(_ code: Int) -> HeldModifier? {
        switch code {
        case 57_441, 57_447: return .shift  // LEFT_SHIFT, RIGHT_SHIFT
        case 57_442, 57_448: return .control
        case 57_443, 57_449: return .option
        case 57_444, 57_450: return .command  // LEFT_SUPER, RIGHT_SUPER
        // Hyper, Meta, ISO Level 3 and 5 Shift, and Caps, Scroll and Num Lock:
        // no SwiftUI modifier to set, but the state they report is current.
        case 57_445, 57_446, 57_451, 57_452, 57_453, 57_454, 57_358, 57_359, 57_360: return .other
        default: return nil
        }
    }

    /// Whether `code` is a keypad key.
    private static func isKeypad(_ code: Int) -> Bool {
        (57_399...57_427).contains(code)
    }

    /// The key a private-use code stands for, and whether it is on the keypad;
    /// `nil` for a code outside that table. A `nil` key is a key this framework
    /// has no `Key` for.
    private static func functionalKey(_ code: Int) -> (key: Key?, isKeypad: Bool)? {
        switch code {
        case 57_376...57_383:  // F13…F20
            let keys: [Key] = [.f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20]
            return (keys[code - 57_376], false)
        case 57_399...57_408:  // KP_0…KP_9
            return (.character(Character(Unicode.Scalar(UInt8(0x30 + code - 57_399)))), true)
        case 57_409...57_427:
            let keypad: [Key?] = [
                .character("."), .character("/"), .character("*"), .character("-"),
                .character("+"), .enter, .character("="), .character(","),
                .left, .right, .up, .down, .pageUp, .pageDown, .home, .end,
                nil, .delete, nil,  // KP_INSERT, KP_DELETE, KP_BEGIN
            ]
            return (keypad[code - 57_409], true)
        case privateUseStart...privateUseEnd:
            // The lock keys are modifier keys, above; the rest are keys this
            // framework has no `Key` for: Print Screen, Pause, Menu, F21 and
            // up, the media keys.
            return (nil, false)
        default:
            return nil
        }
    }

    /// The key a `CSI number ~` report stands for; `nil` for a number the
    /// protocol does not use there, and a `nil` key for Insert and the keypad's
    /// Begin, which this framework has no key for.
    private static func tildeKey(_ number: Int) -> Key?? {
        if number == 2 || number == 57_427 { return .some(nil) }
        return tildeKeys[number].map { .some($0) }
    }

    /// The `CSI number ~` keys this framework has a key for.
    private static let tildeKeys: [Int: Key] = [
        3: .delete, 5: .pageUp, 6: .pageDown, 7: .home, 8: .end,
        11: .f1, 12: .f2, 13: .f3, 14: .f4, 15: .f5,
        17: .f6, 18: .f7, 19: .f8, 20: .f9, 21: .f10, 23: .f11, 24: .f12,
    ]

    /// The key a `CSI 1 ; mods <letter>` report stands for; `nil` for a letter
    /// the protocol does not use, and a `nil` key for the keypad's Begin.
    private static func letterKey(_ final: UInt8) -> Key?? {
        switch final {
        case 0x41: return .up  // A
        case 0x42: return .down  // B
        case 0x43: return .right  // C
        case 0x44: return .left  // D
        case 0x45: return .some(nil)  // E: KP_BEGIN
        case 0x46: return .end  // F
        case 0x48: return .home  // H
        case 0x50: return .f1  // P
        case 0x51: return .f2  // Q
        case 0x53: return .f4  // S
        default: return nil
        }
    }
}
