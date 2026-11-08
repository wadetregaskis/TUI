//  🖥️ TUI — A Terminal UI framework for Swift
//  DividerWideGlyphTests.swift
//
//  `Divider(character:)` takes any `Character`, and a character is not one
//  cell: a CJK ideograph or an emoji takes two, a combining mark none. The rule
//  repeated the glyph once per CELL of width, so a two-cell glyph drew a rule
//  twice the width it was offered, and in a row a vertical rule two cells wide
//  where the divider had said it was one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Divider with a glyph that is not one cell")
struct DividerWideGlyphTests {

    private func context(width: Int, height: Int = 4) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    @Test("A two-cell glyph fills the width it is offered, not twice it")
    func wideGlyphHorizontal() {
        let buffer = renderToBuffer(Divider(character: "世"), context: context(width: 10))
        #expect(buffer.width == 10, "a 10-cell rule, got \(buffer.width)")
        #expect(buffer.lines[0].stripped == String(repeating: "世", count: 5))
    }

    @Test("An odd width leaves the cell a two-cell glyph cannot fill blank")
    func wideGlyphOddWidth() {
        let buffer = renderToBuffer(Divider(character: "世"), context: context(width: 7))
        #expect(buffer.width == 7, "got \(buffer.width)")
        #expect(buffer.lines[0].stripped == String(repeating: "世", count: 3) + " ")
    }

    @Test("In a row, a two-cell glyph's rule is as wide as the divider says it is")
    func wideGlyphVertical() {
        let view = HStack(spacing: 0) {
            Text("a")
            Divider(character: "世")
            Text("b")
        }
        let lines = renderToBuffer(view, context: context(width: 20, height: 1)).lines.map(\.stripped)
        #expect(lines == ["a世b"], "\(lines)")
        #expect(lines.allSatisfy { $0.strippedLength == 4 })
    }

    @Test("A glyph that takes no cell falls back to the axis's own rule")
    func zeroWidthGlyph() {
        let buffer = renderToBuffer(Divider(character: "\u{0301}"), context: context(width: 5))
        #expect(buffer.width == 5, "got \(buffer.width)")
        #expect(buffer.lines[0].stripped == "─────")
    }
}
