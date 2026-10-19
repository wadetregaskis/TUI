//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlyphFill.swift
//
//  A view that fills whatever it is offered with one glyph, so where it is
//  drawn, and at what size, can be read off the screen — and a reader that
//  finds that rectangle.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitView

/// Fills whatever it is offered with one glyph: a flexible view whose drawn
/// rectangle ``rect(of:in:)`` reads off a screen.
struct GlyphFill: View, Renderable, Layoutable {
    let glyph: Character

    init(_ glyph: Character) {
        self.glyph = glyph
    }

    var body: Never { fatalError("GlyphFill renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: proposal.width ?? context.availableWidth, height: proposal.height ?? context.availableHeight,
            isWidthFlexible: true, isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let line = String(repeating: glyph, count: max(0, context.availableWidth))
        return FrameBuffer(lines: Array(repeating: line, count: max(0, context.availableHeight)))
    }
}

/// The rectangle `glyph` covers on `screen` — the smallest one holding every
/// cell it is drawn in — or `nil` where it is not drawn.
func rect(of glyph: Character, in screen: [String]) -> CellRect? {
    var cells: [(x: Int, y: Int)] = []
    for (y, line) in screen.enumerated() {
        for (x, character) in line.enumerated() where character == glyph { cells.append((x, y)) }
    }
    guard let minX = cells.map(\.x).min(), let maxX = cells.map(\.x).max(),
        let minY = cells.map(\.y).min(), let maxY = cells.map(\.y).max()
    else { return nil }
    return CellRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

#endif
