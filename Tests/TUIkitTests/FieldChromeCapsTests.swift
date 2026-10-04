//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldChromeCapsTests.swift
//
//  A field's caps are spelled once per colour, depth and terminal report and
//  kept, not spelled twice per field per render. What is kept must be what
//  `colorize` would spell now — never the bytes of another depth or report.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("A field's caps are what colorize spells, however the depth and report move")
struct FieldChromeCapsTests {

    private static func spelled(_ chrome: FieldChrome) -> (open: String, close: String)? {
        guard let colour = chrome.capColor?.opaqueSpelling else { return nil }
        return (
            ANSIRenderer.colorize(String(TerminalSymbols.openCap), foreground: colour),
            ANSIRenderer.colorize(String(TerminalSymbols.closeCap), foreground: colour)
        )
    }

    /// Back and forth across depths, reports and hover, so a memo keyed on less
    /// than all three serves a stale pair somewhere along the walk: each step
    /// changes ONE of them — the hover within a report, the report at one depth
    /// (a resting field before and after), the depth between two resting fields
    /// on the same report.
    @Test("The caps match colorize across depths, terminal reports and hover, in any order")
    func capsMatchColorize() throws {
        let palette = SystemPalette(.green)
        let style = DefaultTextFieldStyle()
        // A report whose sixteen slots are all white but the last, which is exactly
        // the resting cap colour: at sixteen colours the cap then spells as slot 15
        // (97), where xterm's table puts a dark surface somewhere else entirely.
        let resting = try #require(
            FieldChrome(style: style, palette: palette, isHovered: false).capColor?.opaqueSpelling.rgbComponents)
        let white = TerminalColors.RGB(red: 255, green: 255, blue: 255)
        let cap = TerminalColors.RGB(red: resting.red, green: resting.green, blue: resting.blue)
        let skewed = TerminalColors(
            slots: TerminalColors.Slots(Array(repeating: white, count: 15) + [cap]))
        let terminals = [TerminalColors.unknown, skewed, TerminalColors.unknown]
        let depths: [ColorDepth] = [.truecolor, .basic16, .palette256, .noColor, .basic16, .truecolor]

        var sixteenColourOpens: Set<String> = []
        for depth in depths {
            for terminal in terminals {
                for hovered in [false, true, false] {
                    TerminalColors.withCurrent(terminal) {
                        ColorDepth.withCurrent(depth) {
                            let chrome = FieldChrome(style: style, palette: palette, isHovered: hovered)
                            let expected = Self.spelled(chrome)
                            #expect(chrome.open == expected?.open, "open @\(depth), hovered \(hovered)")
                            #expect(chrome.close == expected?.close, "close @\(depth), hovered \(hovered)")
                            if depth == .basic16, !hovered { sixteenColourOpens.insert(chrome.open) }
                        }
                    }
                }
            }
        }
        // The walk did cross a report that changes the bytes, so the key's report is tested.
        #expect(sixteenColourOpens.count == 2)
    }

    @Test("A plain field has no caps")
    func plainFieldHasNoCaps() {
        let chrome = FieldChrome(style: PlainTextFieldStyle(), palette: SystemPalette(.green), isHovered: false)
        #expect(chrome.open.isEmpty)
        #expect(chrome.close.isEmpty)
        #expect(chrome.width == 0)
    }
}
