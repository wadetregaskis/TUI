//  🖥️ TUI — A Terminal UI framework for Swift
//  NumberTextTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore

/// The package's spellings of the printf formats it used to call: each writes
/// what the format wrote, for the values the package hands it.
@Suite("Numbers written without a printf format")
struct NumberTextTests {
    @Test("digits(width:) pads as %0Nd, %0NX and %Nd do")
    func digitsPadLikePrintf() {
        #expect(7.digits(width: 2) == "07")
        #expect(2026.digits(width: 4) == "2026")
        #expect(12345.digits(width: 4) == "12345")
        #expect((-5).digits(width: 4) == "-005")
        #expect(UInt8(0x0A).digits(width: 2, radix: 16, uppercase: true) == "0A")
        #expect(UInt8(0xFF).digits(width: 2, radix: 16) == "ff")
        #expect(UInt32(0x1F600).digits(width: 4, radix: 16, uppercase: true) == "1F600")
        #expect(42.digits(width: 7, padding: " ") == "     42")
        #expect((-42).digits(width: 7, padding: " ") == "    -42")
    }

    @Test("fixed(_:) writes a full stop and no grouping, whatever the locale")
    func fixedIsTheSameEverywhere() {
        #expect(1234567.891.formatted(.fixed(1)) == "1234567.9")
        #expect(0.5.formatted(.fixed(2)) == "0.50")
        #expect(2.0.formatted(.fixed(0)) == "2")
        #expect((-3.25).formatted(.fixed(3)) == "-3.250")
    }
}
