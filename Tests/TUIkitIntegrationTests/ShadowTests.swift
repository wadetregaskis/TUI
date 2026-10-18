//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowTests.swift
//
//  Shadows in cells (refusal review O6, ruled 2026-10-12: option (b), cells
//  as-is): what a drop shadow darkens, where it is drawn in the stacking order,
//  what clips it, and what an inner shadow darkens.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("Shadows")
struct ShadowTests {

    /// The page every test draws on: a light grey, so that a shadow has
    /// something to darken.
    nonisolated private static let page = 200

    /// A blue two-cell box: a view that paints a field of its own.
    private var box: some View { Text("ab").background(Color.rgb(0, 0, 255)) }

    /// A screen: the view rendered on a palette whose page is ``page`` and
    /// composited as the screen root composites it, in 24-bit colour.
    private func screen(_ view: some View, width: Int = 12, height: Int = 8) -> Screen {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        var palette = ThemeProbePalette()
        palette.background = .rgb(UInt8(Self.page), UInt8(Self.page), UInt8(Self.page))
        environment.palette = palette
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.horizontalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui
        ).isolatingRenderCache()
        return ColorDepth.withCurrent(.truecolor) {
            Screen(
                buffer: renderToBuffer(view, context: context)
                    .compositingOverlays(maxWidth: width, maxHeight: height, palette: palette))
        }
    }

    /// What a screen shows, cell by cell.
    private struct Screen {
        let buffer: FrameBuffer

        /// The brightest channel of the field at `column`, `row`; `nil` where
        /// the cell states none (the page shows).
        func field(_ column: Int, _ row: Int) -> Int? {
            Self.level(cell(column, row)?.state.backgroundColour)
        }

        /// The brightest channel of the ink at `column`, `row`.
        func ink(_ column: Int, _ row: Int) -> Int? { Self.level(cell(column, row)?.ink) }

        /// The glyph at `column`, `row`.
        func glyph(_ column: Int, _ row: Int) -> Character? { cell(column, row)?.glyph }

        /// The fields of row `row`, from `columns`, the page reading as its own level.
        func fields(row: Int, _ columns: Range<Int>) -> [Int] {
            columns.map { field($0, row) ?? ShadowTests.page }
        }

        private func cell(_ column: Int, _ row: Int) -> PaintedCell? {
            guard buffer.lines.indices.contains(row) else { return nil }
            let cells = paintedCells(buffer.lines[row])
            return cells.indices.contains(column) ? cells[column] : nil
        }

        private static func level(_ colour: SGRState.Colour?) -> Int? {
            guard case .rgb(let red, let green, let blue) = colour else { return nil }
            return max(red, green, blue)
        }
    }

    /// `level` darkened by a shadow of black at `alpha`.
    private func darkened(_ alpha: Double, from level: Int = page) -> Int {
        Int((Double(level) * (1 - alpha)).rounded())
    }

    // MARK: - Drop shadows

    @Test("A drop shadow darkens what is behind the view, offset by whole cells, at the colour's alpha")
    func dropShadowOffset() {
        let screen = screen(box.shadow(radius: 0, x: 1, y: 1).padding(2))
        // The box is at columns 2…3 of row 2; its shadow one column right and one
        // row down, at a third (the default colour), and nowhere else.
        let shadow = darkened(84.0 / 255)
        #expect(screen.fields(row: 3, 1..<6) == [Self.page, Self.page, shadow, shadow, Self.page])
        #expect(screen.fields(row: 2, 1..<6) == [Self.page, 255, 255, Self.page, Self.page])
        #expect(screen.fields(row: 1, 0..<6).allSatisfy { $0 == Self.page })
        #expect(screen.fields(row: 4, 0..<6).allSatisfy { $0 == Self.page })
    }

    @Test("The radius is an alpha falloff across that many cells, round at the corners")
    func radiusFallsOff() {
        let screen = screen(Text("abcd").background(Color.rgb(0, 0, 255)).shadow(radius: 2).padding(3))
        let alpha = 84.0 / 255
        let first = darkened(alpha * 2 / 3)
        let second = darkened(alpha / 3)
        let page = Self.page
        // Across the box's row: two rings either side, then the page.
        #expect(screen.fields(row: 3, 0..<10) == [page, second, first, 255, 255, 255, 255, first, second, page])
        // Above it: the first ring over the box, the second beside it, and the
        // corner cell two out each way, 2.8 cells off, past the second ring.
        #expect(screen.fields(row: 2, 0..<10) == [page, second, first, first, first, first, first, first, second, page])
        #expect(screen.fields(row: 1, 0..<10) == [page, page] + Array(repeating: second, count: 6) + [page, page])
        #expect(screen.fields(row: 0, 0..<10).allSatisfy { $0 == page })
    }

    @Test("Where the view paints its own field the shadow is hidden; where it leaves the field clear it shows")
    func ownFieldHidesTheShadow() {
        // A label with no background casts the shape of its letters: "a b" one
        // column right darkens the space between them and the cell past the
        // "b", and nothing under the "b", which no letter casts onto.
        let screen = screen(Text("a b").shadow(color: .black.opacity(0.5), radius: 0, x: 1).padding(2))
        let half = darkened(128.0 / 255)
        #expect(screen.fields(row: 2, 2..<6) == [Self.page, half, Self.page, half])
        #expect(screen.glyph(2, 2) == "a" && screen.glyph(4, 2) == "b")
        #expect(screen.ink(2, 2) == 220 && screen.ink(4, 2) == 220, "the view's own glyphs are drawn over its shadow")
    }

    @Test("A shadow darkens the glyphs it falls on and keeps them")
    func darkensGlyphsBehind() {
        let screen = screen(
            VStack(alignment: .leading, spacing: 0) {
                Text("xxxxx")
                box.shadow(radius: 1, x: 1).padding(.leading, 1)
            }
            .padding(1))
        let ring = 84.0 / 255 / 2
        // The row above the box is in the shadow's first ring from column 2 to 5.
        #expect((1...5).map { screen.glyph($0, 1) } == Array(repeating: "x", count: 5))
        #expect(screen.ink(1, 1) == 220)
        #expect((2...5).map { screen.ink($0, 1) } == Array(repeating: darkened(ring, from: 220), count: 4))
        #expect(screen.fields(row: 1, 1..<7) == [Self.page] + Array(repeating: darkened(ring), count: 4) + [Self.page])
    }

    @Test("A shadow is over the views before its view and under the views after it")
    func stackingOrder() {
        let screen = screen(
            VStack(alignment: .leading, spacing: 0) {
                Text("xxxx").background(Color.rgb(255, 255, 255))
                box.shadow(radius: 1).padding(.leading, 1)
                Text("yy").background(Color.rgb(255, 255, 255))
            })
        let ring = darkened(84.0 / 255 / 2, from: 255)
        #expect(screen.fields(row: 0, 0..<4) == [ring, ring, ring, ring], "over the view before")
        // Under the view after, and past what it paints, over the page.
        let onThePage = darkened(84.0 / 255 / 2)
        #expect(screen.fields(row: 2, 0..<4) == [255, 255, onThePage, onThePage], "under the view after")
    }

    @Test("A scroll view cuts a shadow at its edge, and lets it out when it does not clip")
    func scrollViewClips() {
        func shadowed() -> some View { box.shadow(radius: 1).padding(.leading, 2) }
        let clipped = screen(ScrollView { shadowed() }.frame(height: 1).padding(2))
        let ring = darkened(84.0 / 255 / 2)
        #expect(clipped.fields(row: 2, 3..<7) == [ring, 255, 255, ring])
        #expect(clipped.fields(row: 1, 0..<8).allSatisfy { $0 == Self.page })
        #expect(clipped.fields(row: 3, 0..<8).allSatisfy { $0 == Self.page })
        let unclipped = screen(ScrollView { shadowed() }.scrollClipDisabled().frame(height: 1).padding(2))
        #expect(unclipped.fields(row: 1, 3..<7) == [ring, ring, ring, ring])
        #expect(unclipped.fields(row: 3, 3..<7) == [ring, ring, ring, ring])
    }

    @Test("A shadow changes no size and moves nothing")
    func layoutUnchanged() {
        func row(_ shadowed: Bool) -> [String] {
            let middle = Text("ab").background(Color.rgb(0, 0, 255))
            let view = VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("<")
                    if shadowed { middle.shadow(radius: 2, x: 3, y: 1) } else { middle }
                    Text(">")
                }
                Text("below")
            }
            // The text alone: the root composite draws the shadow past the
            // view's frame, which grows the screen's lines to reach it.
            let lines = screen(view).buffer.lines.map { line in
                var text = line.stripped
                while text.last == " " { text.removeLast() }
                return text
            }
            return Array(lines.reversed().drop { $0.isEmpty }.reversed())
        }
        #expect(row(true) == row(false))
    }

    @Test("Fading the view fades its shadow with it")
    func fadedWithItsView() {
        let screen = screen(box.shadow(radius: 0, x: 1, y: 1).opacity(0.5).padding(2))
        #expect(screen.fields(row: 3, 3..<5) == Array(repeating: darkened(84.0 / 255 / 2), count: 2))
    }

    @Test("Over a painted backdrop the shadow darkens that")
    func overAPaintedBackdrop() {
        let screen = screen(
            box.shadow(radius: 0, x: 1, y: 1).padding(1).background(Color.rgb(255, 0, 0)).padding(1))
        let shadowed = darkened(84.0 / 255, from: 255)
        #expect(screen.fields(row: 3, 2..<5) == [255, shadowed, shadowed])
    }

    @Test("A clear shadow draws nothing at all")
    func clearShadow() {
        let plain = screen(box.padding(2)).buffer
        let clear = screen(box.shadow(color: .clear, radius: 2, x: 1, y: 1).padding(2)).buffer
        #expect(clear.lines == plain.lines)
    }

    @Test("A shadowed view's value hash reads the shadow, so the render memo can keep the view")
    func memoReadsTheShadow() {
        let plans = ValueHashPlans()
        let type = type(of: Text("ab").shadow(radius: 1, x: 1, y: 1))
        let plan = plans.plan(for: type).pointee
        #expect(plan.shape != .bypass, "\(plan.bypassReason ?? "")")
    }

    // MARK: - Inner shadows

    @Test("An inner shadow darkens the cells the view paints toward its edges, ink and field alike")
    func innerShadow() {
        let block = Text("abcd\nefgh\nijkl").background(Color.rgb(0, 0, 255))
        let screen = screen(block.modifier(ShadowModifier(style: .inner(radius: 1))).padding(1))
        let edge = darkened(140.0 / 255 / 2, from: 255)
        #expect(screen.fields(row: 1, 1..<5) == [edge, edge, edge, edge])
        #expect(screen.fields(row: 2, 1..<5) == [edge, 255, 255, edge], "the middle is out of reach of an edge")
        #expect(screen.glyph(1, 1) == "a")
        #expect(screen.ink(1, 1) == darkened(140.0 / 255 / 2, from: 220))
        #expect(screen.fields(row: 0, 0..<6).allSatisfy { $0 == Self.page }, "nothing outside the view")
    }

    @Test("An inner shadow's offset darkens the edges it points away from")
    func innerShadowOffset() {
        let block = Text("abcd\nefgh\nijkl").background(Color.rgb(0, 0, 255))
        let screen = screen(block.modifier(ShadowModifier(style: .inner(radius: 0, x: 1, y: 1))).padding(1))
        let full = darkened(140.0 / 255, from: 255)
        #expect(screen.fields(row: 1, 1..<5) == [full, full, full, full])
        #expect(screen.fields(row: 2, 1..<5) == [full, 255, 255, 255])
        #expect(screen.fields(row: 3, 1..<5) == [full, 255, 255, 255])
    }
}
