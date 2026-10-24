//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MaterialFrostTests.swift
//
//  A material frosts what is behind it (owner ruling O5-FROSTED, shipped as
//  (c)): the glyphs beneath are dropped, and the fields beneath are tinted by
//  the material as before, each its own, with no averaging.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

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

    @Test("A cell under a material keeps its own field, tinted as the tint alone tints it: nothing is averaged")
    func fieldsAreTintedNotAveraged() {
        func stripes(_ cover: some View) -> some View {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Color.rgb(255, 0, 0).frame(width: 4, height: 3)
                    Color.rgb(0, 0, 255).frame(width: 4, height: 3)
                }
                cover
            }
        }
        let rows = screen(
            stripes(Color.clear.frame(width: 8, height: 3).background(.ultraThinMaterial)), width: 8, height: 3)
        let bare = screen(
            stripes(Color.clear.frame(width: 8, height: 3).background(Color.palette.background.opacity(0.35))),
            width: 8, height: 3)
        // At the red/blue seam too, each cell is its own colour tinted, as the
        // translucent colour alone draws it.
        #expect(rows.map { $0.map(\.background) } == bare.map { $0.map(\.background) })
        #expect(rows[1][3].background != rows[1][4].background)
    }

    @Test("A coloured field behind a material keeps its tinted colour where its glyph is dropped")
    func glyphOnAFieldKeepsTheField() {
        let behind = Text(verbatim: "abcd").foregroundStyle(Color.rgb(255, 255, 255)).background(Color.rgb(0, 128, 0))
        let rows = screen(
            ZStack(alignment: .topLeading) {
                behind
                Color.clear.frame(width: 4, height: 1).background(.thinMaterial)
            }, width: 4, height: 1)
        let field = screen(
            ZStack(alignment: .topLeading) {
                Color.rgb(0, 128, 0).frame(width: 4, height: 1)
                Color.clear.frame(width: 4, height: 1).background(.thinMaterial)
            }, width: 4, height: 1)
        #expect(glyphs(rows) == ["    "])
        #expect(rows.map { $0.map(\.background) } == field.map { $0.map(\.background) })
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

    @Test("Glass frosts what is behind it as a material does")
    func glassFrosts() {
        let frosted = glyphs(
            screen(overText(Color.clear.frame(width: 6, height: 3).glassEffect(.regular, in: Rectangle())), width: 6, height: 3))
        // The rim is drawn in the frame's outermost cells; inside it, the text is gone.
        #expect(!frosted[1].contains("h") && !frosted[1].contains("i") && !frosted[1].contains("j"))
    }
}
