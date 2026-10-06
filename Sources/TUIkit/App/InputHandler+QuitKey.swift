//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputHandler+QuitKey.swift
//
//  The user's quit key in the input chain: which Control chord a legacy
//  encoding sends as which C0 byte, so the chain can tell the quit key's
//  chord when it reaches it.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The quit key

extension KeyEvent {
    /// The C0 byte a legacy encoding sends for this Control chord — Ctrl with
    /// `@`, a letter, `[`, `\`, `]`, `^` or `_` — or `nil` for any other
    /// event. Option does not change it (a legacy encoding sends the byte
    /// after an ESC, and the driver acts on the byte); Shift does.
    var legacyControlByte: UInt8? {
        guard ctrl, !shift, case .character(let character) = key, let ascii = character.asciiValue else {
            return nil
        }
        switch ascii {
        case 0x61...0x7A: return ascii - 0x60  // a–z: 0x01–0x1A
        case 0x40, 0x5B...0x5F: return ascii - 0x40  // @ [ \ ] ^ _: 0x00, 0x1B–0x1F
        default: return nil
        }
    }
}
