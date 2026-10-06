//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnitSeparatorTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// Ctrl-minus, TUIkit's undo key, in the legacy encodings: the C0 unit
/// separator, which most terminals also send for Ctrl-_ and Ctrl-/.
@Suite("Ctrl-minus in the legacy encodings")
struct UnitSeparatorTests {
    @Test("0x1F, which Ctrl-minus, Ctrl-_ and Ctrl-/ all send, is Ctrl-minus")
    func unitSeparatorIsControlMinus() {
        #expect(KeyEvent.parse([0x1F]) == KeyEvent(key: .character("-"), ctrl: true))
    }

    @Test("Behind ESC it is Option-Ctrl-minus, as every Control byte is")
    func metaUnitSeparator() {
        #expect(KeyEvent.parse([0x1B, 0x1F]) == KeyEvent(key: .character("-"), ctrl: true, alt: true))
    }

    /// 0x1C reaches the parser only where the driver lets it — the user's
    /// quit key turned off or moved — and then it is a chord an app can
    /// bind. Until 2026-10-06 it was dropped, so a ⌃\ binding could never
    /// fire.
    @Test("0x1C, the quit key's byte, is Ctrl-\\; behind ESC, Option-Ctrl-\\")
    func fileSeparatorIsControlBackslash() {
        #expect(KeyEvent.parse([0x1C]) == KeyEvent(key: .character("\\"), ctrl: true))
        #expect(KeyEvent.parse([0x1B, 0x1C]) == KeyEvent(key: .character("\\"), ctrl: true, alt: true))
    }

    @Test("0x1D and 0x1E stay undelivered")
    func otherSeparatorsStayDropped() {
        for byte: UInt8 in [0x1D, 0x1E] {
            #expect(KeyEvent.parse([byte]) == nil, "\(byte)")
        }
    }
}
