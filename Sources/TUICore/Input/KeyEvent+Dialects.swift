//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyEvent+Dialects.swift
//
//  Keys in spellings beside the xterm family's legacy ones, which
//  `KeyEvent.parse` reads too.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Keys re-coded by a scheme the app never asked for

extension KeyEvent {
    /// A modified key as xterm's `modifyOtherKeys` re-codes it, in either of
    /// its two spellings, or `nil` for any other shape:
    ///
    /// - `CSI 27 ; mods ; code ~`, xterm's (`formatOtherKeys: 0`, tmux's
    ///   `extended-keys-format xterm`);
    /// - `CSI code ; mods u`, or `CSI code u` (`formatOtherKeys: 1`, tmux's
    ///   `csi-u`).
    ///
    /// TUI asks no terminal for this scheme, but a key can arrive in it all
    /// the same: tmux re-codes keys for every pane under `extended-keys
    /// always`, an option many people set for their editor, and an xterm
    /// whose resources set `modifyOtherKeys` does it for every program. tmux
    /// 3.7c sends Shift-Return, Ctrl-Return, Ctrl-Tab and Shift-Space this
    /// way (measured; `Documentation/Terminals/Terminal compatibility
    /// survey.md`, "Modified keys an app did not ask for"), and xterm's level
    /// 2 every Control chord too, ⌃Q included. They were dropped whole, so
    /// those keys did nothing.
    ///
    /// `code` is the key's code point and `mods` xterm's modifier code, 1 to
    /// 16, read as every legacy CSI key's is (``decodeModifierCode(_:)``:
    /// Meta is Option). The key is the one the kitty keyboard protocol's
    /// decoder makes of the same code and modifiers in a report with no text
    /// (`KittyKeyDecoder.chordKey` and `textKey`), so a chord is one key
    /// whichever encoding brought it: Shift-Return is Return with Shift,
    /// Ctrl-Q the `q` with Control, Ctrl-Shift-A an `A` with both. What the
    /// input chain does with a chord nothing binds is what it does under
    /// that protocol: Ctrl-Return goes round as Return, and Ctrl-H, I, J, M
    /// and [ as the keys their bytes are (``legacyControlEquivalent``);
    /// Shift-Return and Shift-Space reach every handler that reads the key
    /// and not its modifiers as Return and Space.
    ///
    /// A code point the protocol keeps for its keys that type nothing (the
    /// Basic Multilingual Plane's private-use area) is no character here, and
    /// a C0 or C1 control other than the four keys' is none either: dropped,
    /// as any malformed sequence is.
    static func parseModifiedOtherKey(_ params: [UInt8]) -> KeyEvent? {
        guard let final = params.last else { return nil }
        let fields = params.dropLast().split(separator: 0x3B, omittingEmptySubsequences: false)
        let code: Int?
        let modifier: Int?
        switch final {
        case 0x7E:  // '~'
            guard fields.count == 3, ASCIIDecimal.value(of: fields[0]) == 27 else { return nil }
            code = ASCIIDecimal.value(of: fields[2])
            modifier = ASCIIDecimal.value(of: fields[1])
        case 0x75:  // 'u'
            guard fields.count <= 2, let first = fields.first else { return nil }
            code = ASCIIDecimal.value(of: first)
            modifier = fields.count == 2 ? ASCIIDecimal.value(of: fields[1]) : 1
        default:
            return nil
        }
        guard let code, let modifier, (1...16).contains(modifier),
            !(privateUseStart...privateUseEnd).contains(code)
        else { return nil }
        let modifiers = decodeModifierCode(modifier)
        // The kitty protocol's bits for Shift, Option and Control, which its
        // decoder's helpers read.
        let bits = (modifiers.shift ? 1 : 0) | (modifiers.alt ? 2 : 0) | (modifiers.ctrl ? 4 : 0)
        let chord = KittyKeyDecoder.chordKey(code: code, shifted: nil, base: nil, bits: bits)
        guard let key = KittyKeyDecoder.textKey(chord.code) else { return nil }
        return KeyEvent(key: key, ctrl: chord.bits & 4 != 0, alt: chord.bits & 2 != 0, shift: chord.bits & 1 != 0)
    }

    /// The private-use area, where the kitty protocol numbers its keys that
    /// type nothing.
    private static let privateUseStart = 0xE000
    private static let privateUseEnd = 0xF8FF
}

// MARK: - The Linux console's F1 to F5

extension KeyEvent {
    /// The Linux console's F1 to F5, `ESC [ [ A` to `ESC [ [ E` (terminfo
    /// `linux`, `kf1`…`kf5`), from the body after `ESC [`; `nil` for any
    /// other byte after the second `[`. Its F6 and up, Home, End and arrows
    /// are xterm's. Until 2026-11-23 the input parser took `ESC [ [` for a
    /// whole CSI, dropped it, and typed the letter: F1 was a Shift-A.
    static func parseLinuxConsoleFunctionKey(_ params: [UInt8]) -> KeyEvent? {
        guard params.count == 2, params[0] == 0x5B, (0x41...0x45).contains(params[1]) else { return nil }
        let keys: [Key] = [.f1, .f2, .f3, .f4, .f5]
        return KeyEvent(key: keys[Int(params[1] - 0x41)])
    }
}

// MARK: - rxvt's modified arrows

extension KeyEvent {
    /// rxvt's and urxvt's arrows with Shift or Control (terminfo `rxvt`):
    /// Shift-Up to Shift-Left are `ESC [ a` to `ESC [ d` (`kUP` `kDN` `kRIT`
    /// `kLFT`), Control-Up to Control-Left `ESC O a` to `ESC O d` (`kUP5`…),
    /// the arrows' own final bytes in lower case. `nil` for any other byte.
    ///
    /// Its Home and End, `ESC [ 7 ~` and `ESC [ 8 ~`, are read with the other
    /// `~` keys (`parseExtendedKey`). Read since 2026-11-23: until then the
    /// Shift arrows were dropped, and a Control arrow was Alt-Shift-O and
    /// then a letter typed. Either spelling is also what a meta-sending
    /// terminal sends for an Option chord and a lowercase letter typed at
    /// once (Option-[ then `a`; Alt-Shift-O then `a`), as `ESC O A` is for
    /// Up: no parser can tell those apart, and the key is the likelier.
    static func rxvtArrow(_ byte: UInt8, ctrl: Bool, shift: Bool) -> KeyEvent? {
        let key: Key
        switch byte {
        case 0x61: key = .up  // a
        case 0x62: key = .down  // b
        case 0x63: key = .right  // c
        case 0x64: key = .left  // d
        default: return nil
        }
        return KeyEvent(key: key, ctrl: ctrl, shift: shift)
    }
}
