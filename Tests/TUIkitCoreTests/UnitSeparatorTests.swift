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

    @Test("The rest of the range above Ctrl-Z stays undelivered")
    func otherSeparatorsStayDropped() {
        for byte: UInt8 in [0x1C, 0x1D, 0x1E] {
            #expect(KeyEvent.parse([byte]) == nil, "\(byte)")
        }
    }
}
