//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyKeyboardProtocol.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Flags

/// The kitty keyboard protocol's progressive enhancements, as the bits an
/// application pushes with `CSI > flags u` and a terminal reports with
/// `CSI ? flags u`.
///
/// See <https://sw.kovidgoyal.net/kitty/keyboard-protocol/>. Each flag widens
/// what the terminal reports, and each has a reason TUIkit asks for it:
///
/// | Flag | Enhancement | What TUIkit needs it for |
/// |---|---|---|
/// | 1 | disambiguate escape codes | Escape, and Ctrl-H/I/J/M/[ as themselves rather than Backspace, Tab, Return and Escape |
/// | 2 | report event types | a held key's repeats, and releases |
/// | 4 | report alternate keys | the shifted key of a Control or Option chord (Ctrl-Shift-Z as `Z`), and a non-Latin layout's key by its Latin position |
/// | 8 | report all keys as escape codes | a modifier key pressed alone, Caps Lock on every key, the keypad's digits |
/// | 16 | report associated text | the text a key typed, which flag 8 would otherwise take away |
///
/// Flag 16 is what keeps typing byte-identical under flag 8: with 8 on, every
/// key, a plain letter included, arrives as an escape code rather than as the
/// text it typed, and only 16 puts that text back into the report. So a
/// shifted character, a dead key's accented letter, a non-US layout's letters
/// and an input method's composed text all arrive as the terminal composed
/// them, as they do in a legacy encoding. Without 16, 8 is not asked for (see
/// the negotiation in `Terminal`).
package struct KittyKeyboardFlags: OptionSet, Hashable, Sendable {
    package let rawValue: Int
    package init(rawValue: Int) { self.rawValue = rawValue }

    /// Flag 1: Escape, and every Control, Option and Control-Option chord on a
    /// key that types ASCII, arrive as `CSI u` reports rather than as the
    /// legacy bytes that collide with other keys.
    package static let disambiguateEscapeCodes = Self(rawValue: 1)
    /// Flag 2: a repeat and a release are reported, as event types 2 and 3.
    package static let reportEventTypes = Self(rawValue: 2)
    /// Flag 4: the shifted key and the base-layout key are reported beside the
    /// key itself.
    package static let reportAlternateKeys = Self(rawValue: 4)
    /// Flag 8: every key is an escape code, the modifier keys included, and
    /// the lock states are reported on every key.
    package static let reportAllKeysAsEscapeCodes = Self(rawValue: 8)
    /// Flag 16: a key that typed text carries that text in its report.
    package static let reportAssociatedText = Self(rawValue: 16)

    /// What TUIkit asks a terminal for: all five.
    package static let requested: Self = [
        .disambiguateEscapeCodes, .reportEventTypes, .reportAlternateKeys,
        .reportAllKeysAsEscapeCodes, .reportAssociatedText,
    ]
}

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
    /// character, as the legacy encoding sends it. Shift is kept as reported,
    /// so `!` is Shift and `!`. Control and Option are dropped, because the
    /// text already includes what they did: Option-E then E arrives as `é`, and
    /// a terminal not treating Option as Alt reports Option on a key that typed
    /// `å`. Either way, a legacy terminal sends the text alone, and a text
    /// field has to insert it rather than read a chord.
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
    package static func decode(_ bytes: [UInt8]) -> [TerminalInput]? {
        guard bytes.count >= 3, bytes[0] == 0x1B, bytes[1] == 0x5B,
            let final = bytes.last
        else { return nil }
        let body = bytes[2..<(bytes.count - 1)]
        // A private marker (`?`, `<`, `=`, `>`) makes it a reply or a mouse
        // report, never a key.
        if let first = body.first, (0x3C...0x3F).contains(first) { return nil }
        guard let fields = Self.fields(body) else { return nil }

        switch final {
        case 0x75:  // 'u'
            return decodeCodePointReport(fields)
        case 0x7E:  // '~'
            guard let number = value(fields, 0, 0) else { return nil }
            guard let key = Self.tildeKey(number) else { return nil }
            return decodeFunctionalKey(key, fields: fields)
        default:
            guard let key = Self.letterKey(final) else { return nil }
            // `CSI 1 ; mods A`, or the bare `CSI A`: the number is always 1.
            if let number = value(fields, 0, 0), number != 1 { return nil }
            return decodeFunctionalKey(key, fields: fields)
        }
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

    /// A `CSI … u` report.
    private static func decodeCodePointReport(_ fields: [[Int?]]) -> [TerminalInput]? {
        guard let (bits, phase) = modifiers(fields) else { return nil }
        let code = value(fields, 0, 0) ?? 0
        let shifted = value(fields, 0, 1)
        let base = value(fields, 0, 2)

        // The modifier and lock keys themselves: the state they leave.
        if let held = modifierKey(code) {
            var state = state(bits)
            // The spec has the key's own bit include its own event, which not
            // every terminal has always done; setting it from the event itself
            // is right either way for the keys that are held rather than
            // toggled. Caps Lock toggles, so its bit is taken as reported.
            let isDown = phase != .release
            switch held {
            case .shift: state.shift = isDown
            case .control: state.control = isDown
            case .option: state.option = isDown
            case .command: state.command = isDown
            case .other: break
            }
            return [.modifierKeys(state)]
        }

        // Text the key typed: the keystroke is that text.
        if phase != .release, fields.count > 2, let text = Self.text(fields[2]), !text.isEmpty {
            return textEvents(text, bits: bits, phase: phase, numericPad: isKeypad(code))
        }

        guard code != 0 else { return nil }  // key 0 is text-only, and there was none
        if holdsUndeliverableModifier(bits) { return [.modifierKeys(state(bits))] }
        if let functional = functionalKey(code) {
            guard let key = functional.key else { return [] }
            return [.key(event(key, bits: bits, phase: phase, numericPad: functional.isKeypad))]
        }

        // A key that typed no text: a Control or Option chord, a release, or a
        // report from a terminal that sends no text. The shifted key when
        // Shift is held, so Ctrl-Shift-Z is `Z`; the base-layout key for a
        // chord on a non-Latin layout, so Ctrl-С is Ctrl-C as its bytes are.
        var chosen = code
        if bits & shiftBit != 0, let shifted {
            chosen = shifted
        } else if bits & (ctrlBit | altBit) != 0, code > 0x7F, let base {
            chosen = base
        }
        guard let key = Self.textKey(chosen) else { return nil }
        return [.key(event(key, bits: bits, phase: phase))]
    }

    /// One key event per character of `text`, carrying Shift and the lock and
    /// keypad state but not the Control and Option the text consumed.
    private static func textEvents(
        _ text: String, bits: Int, phase: KeyEvent.Phase, numericPad: Bool
    ) -> [TerminalInput] {
        let kept = bits & (shiftBit | capsLockBit)
        return text.map { character in
            let key: Key = character == " " ? .space : .character(character)
            return .key(event(key, bits: kept, phase: phase, numericPad: numericPad))
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
