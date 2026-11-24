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
