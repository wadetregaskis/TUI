//  🖥️ TUI — A Terminal UI framework for Swift
//  ShadowTests.swift
//
//  Shadows in cells (refusal review O6, ruled 2026-10-12: option (b), cells
//  as-is): what a drop shadow darkens, where it is drawn in the stacking order,
//  what clips it, and what an inner shadow darkens.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Shadows")
struct ShadowTests {

    /// The page every test draws on (``ShadowScreen/page``).
    nonisolated private static let page = ShadowScreen.page

    /// A blue two-cell box: a view that paints a field of its own.
    private var box: some View { Text("ab").background(Color.rgb(0, 0, 255)) }

    /// The view drawn as the screen root draws it (``ShadowScreen``).
    private func screen(_ view: some View, width: Int = 12, height: Int = 8) -> ShadowScreen {
        ShadowScreen(view, width: width, height: height)
    }

    /// `level` darkened by a shadow of black at `alpha`.
    private func darkened(_ alpha: Double, from level: Int = page) -> Int {
        ShadowScreen.darkened(alpha, from: level)
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

    /// Each overflow layer is one draw at the screen root, and every draw there
    /// costs a pass over the screen. Laid row by row, a shadow's rows each start
    /// at their own column round its corners, and the overflow was cut into one
    /// layer a row there: sixteen for a radius of ten.
    @Test("A drop shadow past its view is at most four layers, one a side, whatever its radius")
    func overflowLayerCount() {
        for radius in [1, 3, 10, 40] {
            let buffer = renderToBuffer(
                box.shadow(radius: radius, x: 1, y: 2),
                context: makeRenderContext(width: 12, height: 8).isolatingRenderCache())
            let overflow = buffer.overlays.filter(\.isOverflow)
            #expect(!overflow.isEmpty && overflow.count <= 4, "radius \(radius): \(overflow.count) layers")
        }
    }

    @Test("Where a shadow's rectangle lays nothing, what is behind it is left exactly as it was")
    func cornersKeepWhatIsBehind() {
        func view(shadowed: Bool) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    Text("abcdefghijklmn").foregroundStyle(.red).background(Color.rgb(0, 0, 200)).bold().underline()
                }
                Group {
                    if shadowed { box.shadow(radius: 3) } else { box }
                }
                .padding(.leading, 6)
            }
        }
        let plain = screen(view(shadowed: false), width: 16)
        let shadowed = screen(view(shadowed: true), width: 16)
        // The box is at columns 6…7 of row 3, its shadow's rectangle columns 3…10
        // of rows 0…6. Three rows up, the cells two and three columns out are past
        // the third ring (3.6 and 4.2 cells); two rows up, three columns out (3.6).
        let corners = [(3, 0), (4, 0), (9, 0), (10, 0), (3, 1), (10, 1)]
        for (column, row) in corners {
            #expect(
                shadowed.cell(column, row) == plain.cell(column, row),
                "(\(column), \(row)): \(String(describing: shadowed.cell(column, row)))")
        }
        #expect(shadowed.field(5, 0) != plain.field(5, 0), "the third ring, beside them, is shadowed")
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

    // MARK: - Animation

    /// `before` drawn and settled, then `after` drawn `millis` into a
    /// one-second linear animation to it.
    private func animated<V: View>(from before: V, to after: V, atMillis millis: Int) -> FrameBuffer {
        var context = makeRenderContext(width: 30, height: 4)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
        func render(_ view: V, atMillis millis: Int) -> FrameBuffer {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
        }
        _ = render(before, atMillis: 0)
        _ = render(after, atMillis: 0)
        return render(after, atMillis: millis)
    }

    /// The radius and the offset are the modifier's animatable data, and the
    /// colour is animated beside them under the same key: on one slot each
    /// overwrote the other's record at every render, and none of them moved.
    @Test("A shadow's offset, radius and colour animate together")
    func animates() {
        // Past the label's frame, the shadow is one layer at x - radius, -radius.
        func place(_ buffer: FrameBuffer) -> (x: Int, y: Int)? {
            buffer.overlays.first(where: \.isOverflow).map { ($0.offsetX, $0.offsetY) }
        }
        let slid = animated(
            from: Text("ab").shadow(radius: 0, x: 4), to: Text("ab").shadow(radius: 4, x: 20), atMillis: 500)
        #expect(place(slid)?.x == 10 && place(slid)?.y == -2, "x 12 and radius 2, half way")

        let red = Color.rgb(255, 0, 0)
        let blue = Color.rgb(0, 0, 255)
        let faded = animated(
            from: Text("ab").shadow(color: red, radius: 0, x: 4), to: Text("ab").shadow(color: blue, radius: 0, x: 4),
            atMillis: 500)
        let layer = faded.overlays.first(where: \.isOverflow)
        let field = layer.flatMap { paintedCells($0.content.lines[0]).first?.state.backgroundColour }
        guard case .rgb(let r, let g, let b) = field else {
            Issue.record("no RGB shadow cell: \(String(describing: field))")
            return
        }
        #expect((120...135).contains(r) && g == 0 && (120...135).contains(b), "half way from red to blue")
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
