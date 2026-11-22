//  🖥️ TUI — A Terminal UI framework for Swift
//  PaletteNamedRoleDerivationTests.swift
//
//  A palette's role may be a named colour (`Color.mint`) or an asset catalogue's
//  (light and dark values of its own). Everything the palette derives from such a
//  role — a control's faces, the focus breaths, the row fills, the stripe — has to
//  take the value the role draws as under the palette's scheme, not the light
//  value its components answer before it is resolved (STYLE-6).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIStyling

/// A dark palette whose accent is whatever it is given: a named colour, or the
/// colour that name resolves to, so the two can be compared derivation by
/// derivation.
private struct DarkPalette: Palette {
    let id = "named-role-dark"
    let name = "Named role, dark"
    let background = Color.rgb(24, 24, 28)
    let foreground = Color.rgb(230, 230, 230)
    let accent: Color
    let success = Color.rgb(0, 200, 0)
    let warning = Color.rgb(220, 180, 0)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(60, 120, 240)
    let border = Color.rgb(90, 90, 90)
}

@MainActor
@Suite("A palette role that names a colour derives at the palette's scheme")
struct PaletteNamedRoleDerivationTests {

    /// The derivations a role feeds, for one palette.
    private struct Derived: Equatable {
        let restingControlFace: Color
        let hoveredControlFace: Color
        let hoveredGlyph: Color
        let accentPulse: [Color]
        let accentFillPulse: [Color]
        let focusWashPulse: [Color]
        let focusBackground: Color
        let rowFills: [RowFills?]
        let selectedRowFill: HighlightFill
        let stripeFill: [Color?]

        init(_ palette: some Palette) {
            restingControlFace = palette.restingControlFace
            hoveredControlFace = palette.hoveredControlFace
            hoveredGlyph = palette.hoveredGlyph(resting: palette.foreground)
            let pulse = palette.accentPulse()
            accentPulse = [pulse.dim, pulse.bright]
            let fillPulse = palette.accentFillPulse()
            accentFillPulse = [fillPulse.dim, fillPulse.bright]
            let wash = palette.focusWashPulse()
            focusWashPulse = [wash.dim, wash.bright]
            focusBackground = palette.focusBackground
            rowFills = [palette.rowFills(at: .truecolor), palette.rowFills(at: .palette256)]
            selectedRowFill = palette.selectedRowFill()
            stripeFill = [.truecolor, .palette256].map { palette.stripeFill(over: palette.background, at: $0) }
        }
    }

    /// The same palette with its accent spelled as the colour it resolves to
    /// derives exactly the same: the name changes nothing but its spelling.
    private func expectDerivesAsResolved(_ accent: Color, sourceLocation: SourceLocation = #_sourceLocation) {
        let named = DarkPalette(accent: accent)
        #expect(named.colorScheme == .dark, "the premise", sourceLocation: sourceLocation)
        let resolved = DarkPalette(accent: accent.resolve(with: named))
        #expect(
            resolved.accent != accent, "the premise: the name resolves to another spelling",
            sourceLocation: sourceLocation)
        #expect(Derived(named) == Derived(resolved), sourceLocation: sourceLocation)
    }

    @Test("A named accent derives at its dark value")
    func namedAccent() {
        expectDerivesAsResolved(.mint)
        // The finding's own example, spelled out.
        let palette = DarkPalette(accent: .mint)
        #expect(
            palette.restingControlFace
                == Color.mint.resolve(with: palette).opacity(ViewConstants.focusBorderDim, over: palette.background))
    }

    @Test("A light-and-dark accent derives at its dark value")
    func lightDarkAccent() throws {
        expectDerivesAsResolved(
            try #require(Color.lightDark(light: .rgb(204, 102, 51), dark: .rgb(16, 128, 255))))
    }
}
