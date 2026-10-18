//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeModifierTests.swift
//
//  A shape behind a view, over it, as its clip and as its hit area.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// `view` rendered in a `width` × `height` frame, resolved as the screen shows it.
@MainActor
private func screen(_ view: some View, width: Int, height: Int) -> FrameBuffer {
    renderToScreen(view, context: makeRenderContext(width: width, height: height))
}

@MainActor
@Suite("Shapes as backgrounds, overlays, clips and hit areas")
struct ShapeModifierTests {

    @Test("A capsule behind padded text keeps its caps, through the padding's blank cells")
    func capsuleBehindPadding() {
        let tag = Text("Tag").padding(.horizontal, 1).background(.purple, in: Capsule())
        let buffer = screen(tag, width: 5, height: 1)
        #expect(buffer.lines[0].stripped == "▐Tag▌")
        let cells = paintedCells(buffer.lines[0])
        #expect(cells[2].background == renderedBackground(of: .purple))
    }

    @Test("A rounded rectangle behind padded text keeps its quadrant corners")
    func roundedRectangleBehindPadding() {
        let card = Text("Flag here").padding(1).background(.teal, in: RoundedRectangle(cornerRadius: 2))
        let lines = screen(card, width: 11, height: 3).lines.map(\.stripped)
        #expect(lines[1] == " Flag here ")
        let corner = lines[0].first ?? " "
        #expect(TerminalSymbols.quadrants.contains(corner) && corner != " " && corner != "█")
    }

    /// Before, only a cell the path covered in part was claimed: a radius of a
    /// quarter column covers its corner cell whole, the fill still cuts the
    /// corner's quadrant, and the padding's blank cell hid the `▟`.
    @Test("A rounded corner shows through padding however small its radius")
    func smallRadiusBehindPadding() {
        let tag = Text("Tag").padding(1).background(.teal, in: RoundedRectangle(cornerRadius: 0.25))
        let lines = screen(tag, width: 5, height: 3).lines.map(\.stripped)
        #expect(lines[0].first == "▟" && lines[0].last == "▙", "\(lines)")
        #expect(lines[2].first == "▜" && lines[2].last == "▛", "\(lines)")
    }

    @Test("A rectangle behind a view paints what a background style paints")
    func rectangleBehind() {
        let shaped = screen(Text("x").frame(width: 3).background(.red, in: Rectangle()), width: 3, height: 1)
        let styled = screen(Text("x").frame(width: 3).background(.red), width: 3, height: 1)
        #expect(paintedCells(shaped.lines[0]).map(\.background) == paintedCells(styled.lines[0]).map(\.background))
        #expect(shaped.lines[0].stripped == styled.lines[0].stripped)
    }

    @Test("A shape over a view leaves the view showing where it does not reach")
    func overlayLeavesUncovered() {
        let view = Text("0123456789").frame(width: 10, height: 5).overlay(.red, in: Ellipse())
        let lines = screen(view, width: 10, height: 5).lines.map(\.stripped)
        #expect(lines[0].hasPrefix("0"))
        #expect(lines[0].hasSuffix("9"))
        #expect(paintedCells(screen(view, width: 10, height: 5).lines[2])[5].background == renderedBackground(of: .red))
    }

    @Test("A clip keeps the cells the shape covers at least half of, and clears the rest")
    func clipShape() {
        let clipped = screen(Color.green.clipShape(Circle()), width: 10, height: 5)
        let rows = clipped.lines.map(paintedCells)
        #expect(rows[2][5].background == renderedBackground(of: .green))
        #expect(rows[0][0].background != renderedBackground(of: .green))
        #expect(rows[4][9].background != renderedBackground(of: .green))
        // What is behind a cleared cell shows there.
        let stacked = ZStack {
            Text("abcdefghij")
            Color.green.clipShape(Circle())
        }
        #expect(screen(stacked, width: 10, height: 1).lines[0].stripped.hasPrefix("abc"))
    }

    @Test("A translucent view clipped keeps no claim over a cleared cell but the clearing one")
    func clipCutsClaims() {
        let buffer = renderToBuffer(Color.green.opacity(0.5).clipShape(Circle()), context: makeRenderContext(width: 10, height: 5))
        let atCorner = buffer.opacityRegions.filter { $0.offsetX == 0 && $0.offsetY == 0 }
        #expect(atCorner.allSatisfy { $0.fieldOpacity == 0 })
        #expect(!atCorner.isEmpty)
    }

    @Test("A rectangle clip is the frame, and a rectangle hit area is the view")
    func rectangles() {
        let context = makeRenderContext(width: 6, height: 2)
        let text = Text("Hello, world").frame(width: 6, height: 2)
        #expect(renderToBuffer(text.clipShape(Rectangle()), context: context).lines == renderToBuffer(text.clipped(), context: context).lines)
        #expect(renderToBuffer(text.contentShape(Rectangle()), context: context).lines == renderToBuffer(text, context: context).lines)
        #expect(renderToBuffer(text.contentShape(.rect), context: context).lines == renderToBuffer(text, context: context).lines)
    }

    @Test("The background style fills a shape given no style")
    func backgroundStyleShape() {
        let view = Text("a").frame(width: 4).background(in: Rectangle()).backgroundStyle(.blue)
        #expect(paintedCells(screen(view, width: 4, height: 1).lines[0])[3].background == renderedBackground(of: .blue))
    }
}
