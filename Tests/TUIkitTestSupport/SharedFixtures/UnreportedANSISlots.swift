//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnreportedANSISlots.swift
//
//  Cut from UnreportedANSISlotTests.swift: suites of several test targets read Apple Terminal's reported slots.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import TUIkit
@testable import TUIkitStyling

enum UnreportedANSISlots {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Terminal-compatibility.md, "Apple Terminal.app 455.1, Basic"), in slot
    /// order. Only slot 0 is xterm's value.
    static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    /// Apple Terminal "Basic" as it reports itself: black on white, and its sixteen.
    static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255), slots: TerminalColors.Slots(appleBasic))
}

#endif
