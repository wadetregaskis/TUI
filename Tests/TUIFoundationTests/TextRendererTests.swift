//  🖥️ TUI — A Terminal UI framework for Swift
//  TextRendererTests.swift
//
//  `TextRenderer`, `Text.Layout`, `customAttribute` and the `GraphicsContext`
//  a renderer draws with (the owner's TEXT-EFFECTS ruling, 2026-10-28).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Hands back the layout it was given, and draws it as it is.
private final class LayoutProbe: @unchecked Sendable {
    var layout: Text.Layout?
}

private struct Recording: TextRenderer {
    let probe: LayoutProbe
    var animatableData = EmptyAnimatableData()

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        probe.layout = layout
        for line in layout { ctx.draw(line) }
    }
}

/// Draws each glyph through `body`.
private struct PerGlyph: TextRenderer {
    let body: @Sendable (Int, Text.Layout.RunSlice, inout GraphicsContext) -> Void
    var animatableData = EmptyAnimatableData()

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    var copy = ctx
                    body(index, glyph, &copy)
                    index += 1
                }
            }
        }
    }
}

private struct Emphasis: TextAttribute {}

@MainActor
@Suite("Text renderers", .rendersEnglishUI)
struct TextRendererTests {
    private func rendered(_ view: some View, width: Int = 20, height: Int = 4) -> FrameBuffer {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
    }

    private func screen(_ view: some View, width: Int = 20, height: Int = 4) -> String {
        rendered(view, width: width, height: height).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("A renderer that draws every line draws the text as it was")
    func identity() {
        let probe = LayoutProbe()
        let plain = screen(Text(verbatim: "Hello world"))
        let drawn = screen(Text(verbatim: "Hello world").textRenderer(Recording(probe: probe)))
        #expect(drawn == plain)
        #expect(probe.layout?.count == 1)
    }

    @Test("Lines, runs and glyphs: wrapped lines, a run per style, a glyph per grapheme")
    func layoutShape() throws {
        let probe = LayoutProbe()
        let text = Text("\(Text(verbatim: "abc "))\(Text(verbatim: "def").bold())\(Text(verbatim: " ghij klm"))")
        _ = rendered(text.textRenderer(Recording(probe: probe)), width: 10)
        let layout = try #require(probe.layout)
        #expect(layout.count == 2, "\(layout.map { $0.map { $0.glyphs.map(\.character).joined() } })")
        let first = layout[0]
        #expect(first.count == 2, "plain, then bold: the wrap drops the space after it")
        #expect(first[1].glyphs.map(\.character).joined() == "def")
        #expect(first[1].typographicBounds.rect == CGRect(x: 4, y: 0, width: 3, height: 1))
        #expect(layout[1].origin == CGPoint(x: 0, y: 1))
        #expect(!layout.isTruncated)
    }

    @Test("A wide character is one glyph two cells wide")
    func wideGlyph() throws {
        let probe = LayoutProbe()
        _ = rendered(Text(verbatim: "a漢b").textRenderer(Recording(probe: probe)))
        let run = try #require(probe.layout?.first?.first)
        #expect(run.count == 3)
        #expect(run[1].typographicBounds.width == 2)
        #expect(run[2].typographicBounds.origin.x == 3)
    }

    @Test("A custom attribute is found on its span's runs, and only there")
    func customAttribute() throws {
        let probe = LayoutProbe()
        let text = Text("\(Text(verbatim: "plain "))\(Text(verbatim: "loud").customAttribute(Emphasis()))")
        _ = rendered(text.textRenderer(Recording(probe: probe)))
        let runs = Array(try #require(probe.layout?.first))
        #expect(runs.count == 2)
        #expect(runs[0][Emphasis.self] == nil)
        #expect(runs[1][Emphasis.self] != nil)
        #expect(runs[1].glyphs.map(\.character).joined() == "loud")
    }

    @Test("A truncated text says so")
    func truncated() throws {
        let probe = LayoutProbe()
        _ = rendered(Text(verbatim: "a long line of text").lineLimit(1).textRenderer(Recording(probe: probe)), width: 8)
        #expect(probe.layout?.isTruncated == true)
    }

    @Test("A glyph drawn as another character keeps its place")
    func replacedGlyph() {
        let drawn = screen(
            Text(verbatim: "abc").textRenderer(PerGlyph { index, glyph, ctx in
                if index == 1 { ctx.drawSubstituting("▓", for: glyph) } else { ctx.draw(glyph) }
            }))
        #expect(drawn.hasPrefix("a▓c"), "\(drawn)")
    }

    @Test("A glyph not drawn leaves its cell blank")
    func skippedGlyph() {
        let drawn = screen(Text(verbatim: "abc").textRenderer(PerGlyph { index, glyph, ctx in
            if index != 1 { ctx.draw(glyph) }
        }))
        #expect(drawn.hasPrefix("a c"), "\(drawn)")
    }

    @Test("A translation moves a glyph by whole cells, rounded")
    func translation() {
        // `a` moved 1.4 cells right lands on `b`'s cell, which is not drawn.
        let drawn = screen(
            Text(verbatim: "abc").textRenderer(PerGlyph { index, glyph, ctx in
                if index == 0 { ctx.translateBy(x: 1.4, y: 0) }
                if index != 1 { ctx.draw(glyph) }
            }))
        #expect(drawn.hasPrefix(" ac"), "\(drawn)")
    }

    @Test("A glyph drawn above the frame floats over what is there, and the text's size is its own")
    func outsideTheFrame() {
        let buffer = rendered(
            Text(verbatim: "abc").textRenderer(PerGlyph { index, glyph, ctx in
                if index == 1 { ctx.translateBy(x: 0, y: -1) }
                ctx.draw(glyph)
            }))
        #expect(buffer.width == 3 && buffer.height == 1)
        #expect(!buffer.overlays.isEmpty, "drawn past its frame, the text floats")
    }

    @Test("Opacity claims the cell's fade for the compositor")
    func opacityClaims() {
        let buffer = rendered(
            Text(verbatim: "abc").textRenderer(PerGlyph { index, glyph, ctx in
                if index == 0 { ctx.opacity = 0.5 }
                ctx.draw(glyph)
            }))
        #expect(buffer.opacityRegions.count == 1)
        #expect(buffer.opacityRegions.first?.offsetX == 0 && buffer.opacityRegions.first?.opacity == 0.5)
    }

    @Test("A filter changes a glyph's colours as the colour effect would")
    func filter() {
        let buffer = rendered(
            Text(verbatim: "a").foregroundStyle(Color.rgb(200, 100, 50)).textRenderer(PerGlyph { _, glyph, ctx in
                ctx.addFilter(.colorInvert())
                ctx.draw(glyph)
            }))
        #expect(buffer.lines[0].contains("38;2;55;155;205"), "\(buffer.lines[0].debugDescription)")
    }

    @Test("Cell attributes are stated over a run's own")
    func cellAttributes() {
        let buffer = rendered(
            Text(verbatim: "ab").textRenderer(PerGlyph { index, glyph, ctx in
                if index == 1 { ctx.textAttributes.underline = true }
                ctx.draw(glyph)
            }))
        let line = buffer.lines[0]
        let a = line.range(of: "a")!, b = line.range(of: "b")!
        #expect(line[a.upperBound..<b.lowerBound].contains("4"), "underline turned on before b: \(line.debugDescription)")
    }

    /// A live text draws its reading at this frame, not its own words; its
    /// layout is built from what it draws, or every glyph is unmatched and the
    /// text reads as cut short (2026-10-29 review).
    @Test("A live text's layout is built from the words it draws")
    func liveTextLayout() throws {
        let probe = LayoutProbe()
        let base = Date(timeIntervalSinceNow: -3_725)
        let text = Text("Ran \(Text(base, style: .relative))")
        let shown = screen(text).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = rendered(text.textRenderer(Recording(probe: probe)))
        let layout = try #require(probe.layout)
        let glyphs = layout.flatMap { line in line.flatMap { run in run.glyphs.map(\.character) } }.joined()
        #expect(glyphs == shown)
        #expect(!layout.isTruncated)
    }

    @Test("A glyph moved far past the text's frame is not drawn, and a huge move does not trap")
    func farGlyphsDropped() {
        for distance: CGFloat in [1e7, 1e300, .infinity, .nan] {
            let buffer = rendered(
                Text(verbatim: "ab").textRenderer(PerGlyph { index, glyph, ctx in
                    if index == 1 { ctx.translateBy(x: distance, y: distance) }
                    ctx.draw(glyph)
                }))
            #expect(buffer.width == 2 && buffer.height == 1, "\(distance): \(buffer.width)×\(buffer.height)")
        }
    }
}
