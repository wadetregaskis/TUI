//  🖥️ TUI — A Terminal UI framework for Swift
//  FieldSurfaceMemoTests.swift
//
//  `Palette.derivedFieldBackground()` keeps what it derived, keyed on everything
//  the derivation reads. What it serves must be what the derivation answers now:
//  never another palette's surface, another depth's or another terminal report's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIStyling

/// A palette whose page and text are the terminal's own, so its field surface is
/// a function of what the terminal reported for them.
private struct TerminalPagePalette: Palette {
    let id = "terminal-page"
    let name = "Terminal page"
    let background = Color.terminalBackground
    let foreground = Color.terminalForeground
    let accent = Color.cyan
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.gray
}

@Suite("A palette's kept field surface is the one it derives now")
struct FieldSurfaceMemoTests {

    /// The derivation, written out without the memo.
    private static func derived<P: Palette>(_ palette: P) -> Color {
        let base = palette.background.resolve(with: palette)
        let stated = palette.appHeaderBackground.resolve(with: palette)
        return P.isVisiblySeparate(stated, from: base, separation: P.wellSeparation)
            ? stated : palette.surface(steppedFrom: base, separation: P.wellSeparation)
    }

    private static func check<P: Palette>(_ palette: P, _ what: String) -> Color {
        let served = palette.derivedFieldBackground()
        #expect(served == derived(palette), "\(what)")
        return served
    }

    /// Back and forth across depths and reports, every palette twice at each, so
    /// the second is served — and a key missing the depth or the report would
    /// serve the first answer it stored where the derivation now says another.
    @Test("Across palettes, depths and terminal reports, the served surface is the derived one")
    func servedIsDerived() {
        let reported = TerminalColors(
            foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
            background: TerminalColors.RGB(red: 40, green: 44, blue: 52))
        let depths: [ColorDepth] = [.truecolor, .palette256, .basic16, .truecolor]
        let terminals = [(false, TerminalColors.unknown), (true, reported), (false, .unknown)]
        var redByDepth: [ColorDepth: Color] = [:]
        var terminalPageByReport: [Bool: Color] = [:]
        for depth in depths {
            for (isReported, terminal) in terminals {
                TerminalColors.withCurrent(terminal) {
                    ColorDepth.withCurrent(depth) {
                        for _ in 0..<2 {
                            for preset in SystemPalette.Preset.allCases {
                                let surface = Self.check(SystemPalette(preset), "\(preset) @\(depth)")
                                if preset == .red { redByDepth[depth] = surface }
                            }
                            let page = Self.check(
                                TerminalPagePalette(), "terminal page @\(depth), reported \(isReported)")
                            if depth == .truecolor { terminalPageByReport[isReported] = page }
                        }
                    }
                }
            }
        }
        // The walk crossed inputs that change the answer — Red's field is a
        // neutral on the cube and its own hue at truecolour; a terminal page has
        // nothing to walk until the terminal reports it — so the key's depth and
        // report are both tested by it.
        #expect(redByDepth[.truecolor] != redByDepth[.palette256])
        #expect(terminalPageByReport[false] != terminalPageByReport[true])
    }
}
