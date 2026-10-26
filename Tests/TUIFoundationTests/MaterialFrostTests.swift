//  🖥️ TUI — A Terminal UI framework for Swift
//  MaterialFrostTests.swift
//
//  A material frosts what is behind it (owner ruling O5-FROSTED (b)): the
//  glyphs beneath are dropped, each cell takes the average of a box of the
//  colours around it — larger the thicker the material — and the material's
//  tint is laid over that. `.materialFrost(_:)` sets the box for a subtree.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("A material's frost")
struct MaterialFrostTests {

    /// `view` as the screen shows it, `width` × `height`, truecolor.
    private func screen(_ view: some View, width: Int, height: Int) -> [[PaintedCell]] {
        var context = RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
            .isolatingRenderCache()
        context.environment.palette = SystemPalette.green
        return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines.map(paintedCells) }
    }

    private func glyphs(_ rows: [[PaintedCell]]) -> [String] {
        rows.map { String($0.map(\.glyph)) }
    }

    /// Three rows of text, and `cover` laid over them from the top-leading corner.
    private func overText(_ cover: some View) -> some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: "abcdef\nghijkl\nmnopqr")
            cover
        }
    }

    @Test("The glyphs behind a material are dropped; its own content stays")
    func glyphsBehindAreDropped() {
        let frosted = glyphs(screen(overText(Color.clear.frame(width: 4, height: 2).background(.thinMaterial)), width: 6, height: 3))
        #expect(frosted == ["    ef", "    kl", "mnopqr"])
        let labelled = glyphs(
            screen(overText(Text("hi").frame(width: 4, height: 2, alignment: .topLeading).background(.thinMaterial)), width: 6, height: 3))
        #expect(labelled == ["hi  ef", "    kl", "mnopqr"])
    }

    /// Two stripes, red then blue, each `half` columns wide and `height` rows
    /// tall, and `cover` laid over them from the top-leading corner.
    private func stripes(_ cover: some View, half: Int = 4, height: Int = 3) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.rgb(255, 0, 0).frame(width: half, height: height)
                Color.rgb(0, 0, 255).frame(width: half, height: height)
            }
            cover
        }
    }

    private func fields(_ rows: [[PaintedCell]]) -> [[String]] {
        rows.map { $0.map(\.background) }
    }

    @Test("A cell under a material takes its box's colours, averaged, then tinted")
    func coloursAreAveraged() {
        let rows = screen(stripes(Color.clear.frame(width: 8, height: 3).background(.ultraThinMaterial)), width: 8, height: 3)
        let bare = screen(
            stripes(Color.clear.frame(width: 8, height: 3).background(Color.palette.background.opacity(0.35))),
            width: 8, height: 3)
        // Far from the seam the box is one colour, as the tint alone draws it; at
        // the seam it is both, where the tint alone is one or the other.
        #expect(rows[1][0].background == bare[1][0].background)
        #expect(rows[1][3].background != bare[1][3].background)
        #expect(rows[1][4].background != bare[1][4].background)
        #expect(rows[1][3].background != rows[1][0].background)
    }

    @Test("The average is the mean of the encoded bytes of the box, tinted as any field is")
    func averageIsTheMeanOfTheBytes() {
        // Ultra-thin's box is three cells of one row: at column 3, two red and one blue.
        let rows = screen(stripes(Color.clear.frame(width: 8, height: 3).background(.ultraThinMaterial)), width: 8, height: 3)
        let expected = screen(
            ZStack(alignment: .topLeading) {
                Color.rgb(170, 0, 85).frame(width: 8, height: 3)
                Color.clear.frame(width: 8, height: 3).background(Color.palette.background.opacity(0.35))
            }, width: 8, height: 3)
        #expect(rows[1][3].background == expected[1][3].background)
    }

    @Test("A thicker material frosts a larger box")
    func thickerFrostsFarther() {
        // Column 2 of two six-wide stripes: ultra-thin's box (one column either
        // side) is all red, ultra-thick's (five) reaches the blue.
        func frosted(_ material: Material, opacity: Double) -> (frosted: String, tint: String) {
            let rows = screen(stripes(Color.clear.frame(width: 12, height: 3).background(material), half: 6), width: 12, height: 3)
            let bare = screen(
                stripes(Color.clear.frame(width: 12, height: 3).background(Color.palette.background.opacity(opacity)), half: 6),
                width: 12, height: 3)
            return (rows[1][2].background, bare[1][2].background)
        }
        let thin = frosted(.ultraThin, opacity: 0.35)
        #expect(thin.frosted == thin.tint)
        let thick = frosted(.ultraThick, opacity: 0.92)
        #expect(thick.frosted != thick.tint)
    }

    @Test("The boxes grow with thickness, each wider than tall; a bar's is a thick material's")
    func boxesByThickness() {
        let order: [Material] = [.ultraThin, .thin, .regular, .thick, .ultraThick]
        let reaches = order.map { material -> (columns: UInt8, rows: UInt8) in
            guard case .averaging(let columns, let rows) = material.frost else { return (0, 0) }
            return (columns, rows)
        }
        for (smaller, larger) in zip(reaches, reaches.dropFirst()) {
            #expect(larger.columns > smaller.columns && larger.rows >= smaller.rows)
        }
        for reach in reaches { #expect(reach.columns >= reach.rows * 2 && reach.columns > 0) }
        #expect(Material.bar.frost == Material.thick.frost)
    }

    @Test("materialFrost sets the box for a subtree, over the thickness's")
    func modifierSetsTheBox() {
        var environment = EnvironmentValues()
        environment.appearsActive = true
        #expect(Material.thin.paint(in: environment).frost == Material.thin.frost)
        environment.materialFrost = .radius(columns: 3, rows: 1)
        #expect(Material.thin.paint(in: environment).frost == OpacityRegion.Frost.averaging(columns: 3, rows: 1))
        environment.materialFrost = .none
        #expect(Material.ultraThick.paint(in: environment).frost == OpacityRegion.Frost.droppingGlyphs)
        #expect(MaterialFrost.radius(columns: -1, rows: 300) == .radius(columns: 0, rows: 255))
        // Thin's own box at column 3 of two six-wide stripes is all red; a wider one reaches the blue.
        let cover = Color.clear.frame(width: 12, height: 3).background(.thinMaterial)
        let automatic = screen(stripes(cover, half: 6), width: 12, height: 3)
        let wider = screen(stripes(cover, half: 6).materialFrost(.radius(columns: 4, rows: 0)), width: 12, height: 3)
        let bare = screen(
            stripes(Color.clear.frame(width: 12, height: 3).background(Color.palette.background.opacity(0.5)), half: 6),
            width: 12, height: 3)
        #expect(automatic[1][3].background == bare[1][3].background)
        #expect(wider[1][3].background != bare[1][3].background)
    }

    @Test("At .none nothing is averaged: each cell keeps its own field, tinted, and its glyph is still dropped")
    func noneDropsGlyphsOnly() {
        let cover = Color.clear.frame(width: 8, height: 3).background(.ultraThinMaterial)
        let rows = screen(stripes(cover).materialFrost(.none), width: 8, height: 3)
        let bare = screen(
            stripes(Color.clear.frame(width: 8, height: 3).background(Color.palette.background.opacity(0.35))),
            width: 8, height: 3)
        // At the red/blue seam too, each cell is its own colour tinted.
        #expect(fields(rows) == fields(bare))
        #expect(rows[1][3].background != rows[1][4].background)
        let behind = Text(verbatim: "abcd").foregroundStyle(Color.rgb(255, 255, 255)).background(Color.rgb(0, 128, 0))
        let text = screen(
            ZStack(alignment: .topLeading) {
                behind
                Color.clear.frame(width: 4, height: 1).background(.thinMaterial)
            }.materialFrost(.none), width: 4, height: 1)
        let field = screen(
            ZStack(alignment: .topLeading) {
                Color.rgb(0, 128, 0).frame(width: 4, height: 1)
                Color.clear.frame(width: 4, height: 1).background(.thinMaterial)
            }, width: 4, height: 1)
        #expect(glyphs(text) == ["    "])
        #expect(fields(text) == fields(field))
    }

    @Test("A frost that drops glyphs only makes no averages: .none is (c)'s path")
    func droppingGlyphsMakesNoAverages() {
        let behind = FrameBuffer(text: "abc")
        var claim = OpacityRegion(
            offsetX: 0, offsetY: 0, width: 3, height: 1, opacity: 1, fieldOpacity: 0.5, frost: .droppingGlyphs)
        let surface = Color.rgb(0, 0, 0)
        let ink = Color.rgb(255, 255, 255)
        #expect(behind.frostFields(under: [claim], at: (0, 0), surface: surface, defaultForeground: ink) == nil)
        claim.frost = .averaging(columns: 1, rows: 0)
        #expect(behind.frostFields(under: [claim], at: (0, 0), surface: surface, defaultForeground: ink) != nil)
    }

    @Test("A glyph's ink counts toward its cell's average")
    func inkCounts() {
        let behind = Text(verbatim: "abcd").foregroundStyle(Color.rgb(255, 255, 255)).background(Color.rgb(0, 128, 0))
        let text = screen(
            ZStack(alignment: .topLeading) {
                behind
                Color.clear.frame(width: 4, height: 1).background(.thinMaterial)
            }, width: 4, height: 1)
        let field = screen(
            ZStack(alignment: .topLeading) {
                Color.rgb(0, 128, 0).frame(width: 4, height: 1)
                Color.clear.frame(width: 4, height: 1).background(.thinMaterial)
            }, width: 4, height: 1)
        #expect(glyphs(text) == ["    "])
        #expect(fields(text) != fields(field), "white letters lighten the green they are on")
    }

    @Test("Over nothing, a material is its tint, as it was")
    func overNothingIsTheTint() {
        let material = screen(Text("ab").background(.thinMaterial), width: 4, height: 1)
        let tint = screen(Text("ab").background(Color.palette.background.opacity(0.5)), width: 4, height: 1)
        #expect(material.map { $0.map(\.background) } == tint.map { $0.map(\.background) })
    }

    @Test("A material that does not appear active is opaque, and frosts nothing it does not cover")
    func inactiveMaterial() {
        let paint = Material.thin.paint(in: {
            var environment = EnvironmentValues()
            environment.appearsActive = false
            return environment
        }())
        #expect(!paint.frosts)
        var active = EnvironmentValues()
        active.appearsActive = true
        #expect(Material.thin.paint(in: active).frosts)
        #expect(!Paint.color(.red.opacity(0.5)).frosts, "a translucent colour is a tint, not a material")
    }

    @Test("Glass frosts a box one thickness thinner than the material whose surface it takes")
    func glassBoxes() {
        var environment = EnvironmentValues()
        #expect(Glass.regular.frost(in: environment) == Material.thin.frost)
        #expect(Glass.clear.frost(in: environment) == Material.ultraThin.frost)
        environment.materialFrost = .none
        #expect(Glass.regular.frost(in: environment) == .droppingGlyphs)
    }

    @Test("Glass frosts what is behind it as a material does")
    func glassFrosts() {
        let frosted = glyphs(
            screen(overText(Color.clear.frame(width: 6, height: 3).glassEffect(.regular, in: Rectangle())), width: 6, height: 3))
        // The rim is drawn in the frame's outermost cells; inside it, the text is gone.
        #expect(!frosted[1].contains("h") && !frosted[1].contains("i") && !frosted[1].contains("j"))
    }

    @Test("Coverage: a space inks nothing, a full block everything, a letter some")
    func coverage() {
        #expect(FrameBuffer.frostCoverage(of: " ") == 0)
        #expect(FrameBuffer.frostCoverage(of: "█") == 1)
        #expect(FrameBuffer.frostCoverage(of: "▄") == 0.5)
        #expect(FrameBuffer.frostCoverage(of: "▁") == 0.125)
        let letter = FrameBuffer.frostCoverage(of: "a")
        #expect(letter > 0.1 && letter < 0.5)
        #expect(FrameBuffer.frostCoverage(of: "─") < letter)
        #expect(FrameBuffer.frostCoverage(of: "Ä") == FrameBuffer.frostCoverage(of: "A"))
    }
}
