//  🖥️ TUI — A Terminal UI framework for Swift
//  MaskModifierTests.swift
//
//  `mask(alignment:_:)`: a view's cells kept where another view draws, at
//  the alpha it draws them with (decisions A27).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// `view` rendered in a `width` × `height` frame, resolved as the screen shows it.
@MainActor
private func screen(_ view: some View, width: Int, height: Int) -> FrameBuffer {
    renderToScreen(view, context: makeRenderContext(width: width, height: height))
}

@MainActor
@Suite("Masking a view by another")
struct MaskModifierTests {

    @Test("A shape mask keeps the cells a clip to the shape keeps")
    func shapeMaskIsClip() {
        let masked = screen(Color.green.mask { Circle() }, width: 10, height: 5)
        let clipped = screen(Color.green.clipShape(Circle()), width: 10, height: 5)
        #expect(masked.lines == clipped.lines)
    }

    @Test("A view mask keeps the cells it draws a glyph in, centred by default")
    func glyphsKeep() {
        let masked = Text("abcdef").mask { Text("xx") }
        #expect(screen(masked, width: 6, height: 1).lines[0].stripped == "  cd  ")
    }

    @Test("The alignment places the mask in the frame")
    func alignment() {
        let leading = Text("abcdef").mask(alignment: .leading) { Text("xx") }
        #expect(screen(leading, width: 6, height: 1).lines[0].stripped.trimmingTrailingSpaces == "ab")
        let trailing = Text("abcdef").mask(alignment: .trailing) { Text("xx") }
        #expect(screen(trailing, width: 6, height: 1).lines[0].stripped == "    ef")
    }

    @Test("A space the mask leaves without a field masks the cell out")
    func spacesMaskOut() {
        let masked = Text("abcdef").mask(alignment: .leading) { Text("x y") }
        #expect(screen(masked, width: 6, height: 1).lines[0].stripped.trimmingTrailingSpaces == "a c")
    }

    @Test("A field keeps the cells it fills, whatever their glyph")
    func fieldsKeep() {
        let masked = Text("abcdef").mask { Color.black.frame(width: 2) }
        #expect(screen(masked, width: 6, height: 1).lines[0].stripped == "  cd  ")
    }

    @Test("A fill masked by text is the text in the fill's colour, with no field")
    func fillMaskedByText() {
        let masked = Color.green.frame(width: 6, height: 1).mask { Text("Hi") }
        let inGreen = Text("  Hi  ").foregroundStyle(.green)
        let painted = paintedCells(screen(masked, width: 6, height: 1).lines[0])
        let expected = paintedCells(screen(inGreen, width: 6, height: 1).lines[0])
        #expect(painted.map(\.glyph) == expected.map(\.glyph))
        // The letters; the cells around them are cleared to the page, as a clip
        // clears them.
        #expect(painted[2...3].map(\.visibleState) == expected[2...3].map(\.visibleState))
    }

    @Test("Where both draw a glyph, the view keeps its own")
    func glyphOverGlyph() {
        let masked = Text("ab").foregroundStyle(.red).mask { Text("xy").foregroundStyle(.blue) }
        let line = screen(masked, width: 2, height: 1).lines[0]
        #expect(line == screen(Text("ab").foregroundStyle(.red), width: 2, height: 1).lines[0])
    }

    @Test("An empty mask masks everything out")
    func emptyMask() {
        let masked = Text("abcdef").mask { EmptyView() }
        #expect(screen(masked, width: 6, height: 1).lines[0].stripped.trimmingTrailingSpaces.isEmpty)
    }

    @Test("A translucent mask keeps the view at its alpha, as an opacity does")
    func translucentMask() {
        let colourMask = Color.green.mask { Color.black.opacity(0.5) }
        // `.opacity(_:)` the view modifier, not `Color.opacity(_:)`, which
        // makes a translucent colour rather than fading a view.
        let faded = Color.green.frame(width: 4, height: 2).opacity(0.5)
        #expect(screen(colourMask, width: 4, height: 2).lines == screen(faded, width: 4, height: 2).lines)
        let viewMask = Text("ab").mask { Text("xx").opacity(0.5) }
        #expect(screen(viewMask, width: 2, height: 1).lines == screen(Text("ab").opacity(0.5), width: 2, height: 1).lines)
    }

    @Test("A mask fading part of a translucent view multiplies the two alphas there")
    func nestedAlphas() {
        let masked = Color.green.frame(width: 4).opacity(0.5).mask(alignment: .leading) {
            HStack(spacing: 0) {
                Color.black.opacity(0.5).frame(width: 2)
                Color.black.frame(width: 2)
            }
        }
        let expected = HStack(spacing: 0) {
            Color.green.frame(width: 2).opacity(0.25)
            Color.green.frame(width: 2).opacity(0.5)
        }
        #expect(screen(masked, width: 4, height: 1).lines == screen(expected, width: 4, height: 1).lines)
    }

    @Test("Masking leaves the frame as it was")
    func frameUnchanged() {
        let context = makeRenderContext(width: 20, height: 4)
        let text = Text("Hello")
        let masked = text.mask { Text("x") }
        #expect(measureChild(masked, proposal: .unspecified, context: context) == measureChild(text, proposal: .unspecified, context: context))
        #expect(renderToBuffer(masked, context: context).width == renderToBuffer(text, context: context).width)
    }
}

private extension String {
    /// The string without the spaces at its end.
    var trimmingTrailingSpaces: Substring {
        self[..<(lastIndex { $0 != " " }.map(index(after:)) ?? startIndex)]
    }
}
