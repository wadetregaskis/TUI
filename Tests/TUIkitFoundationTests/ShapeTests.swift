//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeTests.swift
//
//  The built-in shapes' paths against SwiftUI's (measured: the W1 lane's
//  `paths.swift` probe, session notes), and shapes drawn as views: which tier
//  draws them, what each cell is, and what they owe the compositor.
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

/// `view` rendered in a `width` × `height` frame, then resolved as the screen
/// would show it.
@MainActor
private func screen(_ view: some View, width: Int, height: Int) -> FrameBuffer {
    renderToScreen(view, context: makeRenderContext(width: width, height: height))
}

/// The glyphs of `buffer`, styling stripped.
private func text(_ buffer: FrameBuffer) -> [String] {
    buffer.lines.map(\.stripped)
}

@MainActor
@Suite("Shapes: their paths, and drawn as views")
struct ShapeTests {

    // MARK: Paths

    @Test("The built-in shapes' paths are SwiftUI's")
    func builtInPaths() {
        let wide = CGRect(x: 0, y: 0, width: 20, height: 10)
        #expect(Rectangle().path(in: CGRect(x: 0, y: 0, width: 4, height: 2)).description == "0 0 m 4 0 l 4 2 l 0 2 l h")
        expectPath(
            Circle().path(in: wide),
            matches: "15 5 m 15 7.76142 12.7614 10 10 10 c 7.23858 10 5 7.76142 5 5 c 5 2.23858 7.23858 0 10 0 c 12.7614 0 15 2.23858 15 5 c h")
        expectPath(
            Ellipse().path(in: wide),
            matches: "20 5 m 20 7.76142 15.5228 10 10 10 c 4.47715 10 0 7.76142 0 5 c 0 2.23858 4.47715 0 10 0 c 15.5228 0 20 2.23858 20 5 c h")
        expectPath(RoundedRectangle(cornerRadius: 3).path(in: wide), matches: Path(roundedRect: wide, cornerRadius: 3).description)
        expectPath(
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomTrailingRadius: 4).path(in: wide),
            matches: """
                20 3 m 20 3.88534 l 20 5.64604 20 6.52637 19.7004 7.47402 c 19.3238 8.5087 18.5087 9.32376 17.474 9.70035 c \
                16.5264 10 15.646 10 13.8853 10 c 0 10 l 0 10 0 10 0 10 c 0 10 0 10 0 10 c 0 10 0 10 0 10 c 0 3.05733 l \
                0 2.17698 0 1.73681 0.149823 1.26299 c 0.33812 0.745648 0.745648 0.33812 1.26299 0.149823 c 1.73681 0 2.17698 0 \
                3.05733 0 c 20 0 l 20 0 20 0 20 0 c 20 0 20 0 20 0 c 20 0 20 0 20 0 c h
                """)
        #expect(Capsule().path(in: wide).boundingRect == wide)
    }

    @Test("Insetting is path arithmetic: the rectangle shrinks, and a radius with it")
    func insets() {
        let square = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(Rectangle().inset(by: 2).path(in: square).description == "2 2 m 8 2 l 8 8 l 2 8 l h")
        #expect(Circle().inset(by: 2).path(in: square).boundingRect == CGRect(x: 2, y: 2, width: 6, height: 6))
        let rounded = RoundedRectangle(cornerRadius: 3).inset(by: 2).path(in: CGRect(x: 0, y: 0, width: 20, height: 10))
        expectPath(rounded, matches: Path(roundedRect: CGRect(x: 2, y: 2, width: 16, height: 6), cornerRadius: 1).description)
    }

    @Test("Moved, turned, scaled, resized and trimmed shapes are SwiftUI's arithmetic")
    func transforms() {
        let frame = CGRect(x: 0, y: 0, width: 4, height: 2)
        #expect(Rectangle().offset(x: 2, y: 3).path(in: frame).description == "2 3 m 6 3 l 6 5 l 2 5 l h")
        expectPath(Rectangle().rotation(.degrees(90)).path(in: frame), matches: "3 -1 m 3 3 l 1 3 l 1 -1 l h")
        #expect(Rectangle().scale(2).path(in: frame).description == "-2 -1 m 6 -1 l 6 3 l -2 3 l h")
        #expect(Rectangle().scale(x: 2, y: 1, anchor: .topLeading).path(in: frame).description == "0 0 m 8 0 l 8 2 l 0 2 l h")
        let offsetFrame = CGRect(x: 10, y: 10, width: 4, height: 4)
        #expect(Rectangle().size(width: 2, height: 2).path(in: offsetFrame).description == "10 10 m 12 10 l 12 12 l 10 12 l h")
        #expect(Rectangle().size(CGSize(width: 2, height: 2), anchor: .center).path(in: offsetFrame).description == "1 1 m 3 1 l 3 3 l 1 3 l h")
        #expect(Rectangle().trim(from: 0, to: 0.5).path(in: frame).description == "0 0 m 4 0 l 4 2 l")
        let sheared = Rectangle().transform(CGAffineTransform(a: 1, b: 0, c: 1, d: 1, tx: 0, ty: 0)).path(in: frame)
        #expect(sheared.description == "0 0 m 4 0 l 6 2 l 2 2 l h")
    }

    @Test("A shape's animatable data is SwiftUI's, and the views forward it")
    func animatableData() {
        #expect(RoundedRectangle(cornerRadius: 3).animatableData == AnimatablePair(3, 3))
        // The trim's own type: `trim(from:to:)` hides it behind `some Shape`.
        var trimmed = _TrimmedShape(shape: Circle(), startFraction: 0, endFraction: 0.5).fill(.red)
        #expect(trimmed.animatableData.second == AnimatablePair(0, 0.5))
        trimmed.animatableData.second = AnimatablePair(0, 0.75)
        let square = CGRect(x: 0, y: 0, width: 4, height: 4)
        #expect(trimmed.shape.path(in: square) == Circle().trim(from: 0, to: 0.75).path(in: square))
        let stroked = RoundedRectangle(cornerRadius: 1).stroke(.blue, lineWidth: 1)
        #expect(stroked.animatableData == AnimatablePair(1, 1))
    }

    @Test("A button border shape is the shape its family stands for; .buttonBorder defers to the environment")
    func buttonBorderShape() {
        let frame = CGRect(x: 0, y: 0, width: 20, height: 10)
        #expect(ButtonBorderShape.capsule.path(in: frame) == Capsule().path(in: frame))
        #expect(ButtonBorderShape.circle.path(in: frame) == Circle().path(in: frame))
        #expect(ButtonBorderShape.roundedRectangle(radius: 0).path(in: frame) == Rectangle().path(in: frame))
        #expect(ButtonBorderShape.capsule.inset(by: 2).path(in: frame) == Capsule().inset(by: 2).path(in: frame))
        let square = VStack { ButtonBorderShape.buttonBorder.stroke(.red) }
            .buttonBorderShape(.roundedRectangle(radius: 0))
        #expect(text(screen(square, width: 6, height: 3)) == ["┌────┐", "│    │", "└────┘"])
        #expect(text(screen(ButtonBorderShape.buttonBorder.stroke(.red), width: 6, height: 3)) == ["╭────╮", "│    │", "╰────╯"])
    }

    /// Before, only `BoxDrawnShape` passed through a wrapper: an erased or
    /// transformed shape that stands for another drew as its own path —
    /// `AnyShape(.buttonBorder)` a capsule under any button border shape, a
    /// container-relative shape a rectangle in any container — and
    /// `.buttonBorder.inset(by:)` was a capsule always.
    @Test("A shape that stands for another does so erased, inset or transformed")
    func wrappedStandIns() {
        func square(_ view: some View, width: Int = 6, height: Int = 3) -> [String] {
            text(screen(VStack { view }.buttonBorderShape(.roundedRectangle(radius: 0)), width: width, height: height))
        }
        #expect(square(AnyShape(.buttonBorder).stroke(.red)) == ["┌────┐", "│    │", "└────┘"])
        // Big enough for a capsule's rounding to show in glyphs.
        let inset = square(ButtonBorderShape.buttonBorder.inset(by: 1).fill(.red), width: 10, height: 5)
        #expect(inset == square(Rectangle().inset(by: 1).fill(.red), width: 10, height: 5))
        #expect(inset != square(Capsule().inset(by: 1).fill(.red), width: 10, height: 5))
        func contained(_ view: some View) -> [String] {
            text(screen(view.containerShape(RoundedRectangle(cornerRadius: 3)), width: 6, height: 3))
        }
        #expect(contained(AnyShape(ContainerRelativeShape()).stroke(.red)) == ["╭────╮", "│    │", "╰────╯"])
        let rounded = text(screen(RoundedRectangle(cornerRadius: 3).offset(x: 0, y: 0).fill(.red), width: 6, height: 3))
        #expect(contained(ContainerRelativeShape().offset(x: 0, y: 0).fill(.red)) == rounded)
        #expect(contained(AnyShape(ContainerRelativeShape()).offset(x: 0, y: 0).fill(.red)) == rounded)
    }

    // MARK: The box-drawing tier

    @Test("A rectangle-family stroke is a box of line glyphs, a corner per corner")
    func boxStrokes() {
        #expect(text(screen(Rectangle().stroke(.red), width: 6, height: 3)) == ["┌────┐", "│    │", "└────┘"])
        #expect(text(screen(RoundedRectangle(cornerRadius: 1).stroke(.red), width: 6, height: 3)) == ["╭────╮", "│    │", "╰────╯"])
        let uneven = UnevenRoundedRectangle(topLeadingRadius: 1, bottomTrailingRadius: 2)
        #expect(text(screen(uneven.stroke(.red), width: 6, height: 3)) == ["╭────┐", "│    │", "└────╯"])
        #expect(text(screen(Capsule().stroke(.red), width: 6, height: 1)) == ["(────)"])
        // The stroke as a shape, filled with the foreground: the same box.
        #expect(text(screen(Rectangle().stroke(lineWidth: 1), width: 6, height: 3)) == ["┌────┐", "│    │", "└────┘"])
        // strokeBorder draws the same box: it is already inside the frame.
        #expect(text(screen(Rectangle().strokeBorder(.red), width: 6, height: 3)) == ["┌────┐", "│    │", "└────┘"])
    }

    @Test("A dashed or wide stroke is rasterized, not lines")
    func rasterizedStrokes() {
        let dashed = text(screen(Rectangle().stroke(.red, style: StrokeStyle(lineWidth: 1, dash: [2, 2])), width: 8, height: 3))
        #expect(!dashed.joined().contains("─"))
        #expect(dashed.joined().contains { "▀▄".contains($0) })
        let wide = screen(Rectangle().strokeBorder(.red, lineWidth: 2), width: 8, height: 4)
        #expect(!text(wide).joined().contains("─"))
        // Two columns wide down the sides, and nothing in the middle.
        let row = paintedCells(wide.lines[1])
        #expect(row[0].background == renderedBackground(of: .red))
        #expect(row[1].background == renderedBackground(of: .red))
        #expect(row[4].background != renderedBackground(of: .red))
    }

    @Test("A rectangle filled is a colour as a view, byte for byte")
    func rectangleFillIsColor() {
        let context = makeRenderContext(width: 6, height: 2)
        #expect(renderToBuffer(Rectangle().fill(.red), context: context).lines == renderToBuffer(Color.red, context: context).lines)
    }

    @Test("A one-row capsule fill ends in the half-block caps; a rounded rectangle's corners are cut")
    func boxFills() {
        #expect(text(screen(Capsule().fill(.blue), width: 6, height: 1)) == ["▐    ▌"])
        #expect(text(screen(RoundedRectangle(cornerRadius: 1).fill(.blue), width: 6, height: 3)) == ["▟    ▙", "      ", "▜    ▛"])
        let lines = screen(Capsule().fill(.blue), width: 6, height: 1).lines[0]
        let cells = paintedCells(lines)
        #expect(cells[1].background == renderedBackground(of: .blue))
        #expect(cells[0].background != renderedBackground(of: .blue))
    }

    // MARK: The rasterizer

    @Test("A circle is rasterized: field inside, nothing at its frame's corners")
    func circleFill() {
        let buffer = screen(Circle().fill(.green), width: 10, height: 5)
        let cells = buffer.lines.map(paintedCells)
        #expect(cells[2][5].background == renderedBackground(of: .green))
        #expect(cells[0][0].glyph == " " && cells[0][0].background != renderedBackground(of: .green))
        #expect(text(buffer)[0].contains("▄"))
        // A ring is empty in the middle.
        let ring = screen(Circle().stroke(.green), width: 10, height: 5).lines.map(paintedCells)
        #expect(ring[2][5].glyph == " " && ring[2][5].background != renderedBackground(of: .green))
    }

    @Test("A shape used as a view is filled with the foreground style")
    func defaultFill() {
        let buffer = screen(VStack { Circle() }.foregroundStyle(.red), width: 10, height: 5)
        #expect(paintedCells(buffer.lines[2])[5].background == renderedBackground(of: .red))
    }

    @Test("A gradient fill is sampled across the shape")
    func gradientFill() {
        let fill = Circle().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
        let rows = renderToBuffer(fill, context: makeRenderContext(width: 10, height: 5)).lines.map(paintedCells)
        #expect(rows[1][5].background != rows[3][5].background)
    }

    @Test("Where the shape does not reach, what is beneath it shows")
    func transparentCells() {
        let stacked = ZStack {
            Text("abcdefghij")
            Circle().fill(.red)
        }
        let line = text(screen(stacked, width: 10, height: 1))[0]
        #expect(line.hasPrefix("abc"))
        #expect(line.hasSuffix("hij"))
    }

    @Test("A translucent fill claims its alpha rather than spelling it")
    func translucentFill() {
        let buffer = renderToBuffer(Circle().fill(Color.red.opacity(0.5)), context: makeRenderContext(width: 10, height: 5))
        #expect(buffer.opacityRegions.contains { $0.fieldOpacity > 0.45 && $0.fieldOpacity < 0.55 })
    }

    @Test("With no colour, a shape is drawn in glyphs alone")
    func monochrome() {
        withColorDepth(.noColor) {
            let lines = text(renderToBuffer(Circle().fill(.red), context: makeRenderContext(width: 10, height: 5)))
            #expect(lines[2].contains("█"))
            let box = text(renderToBuffer(RoundedRectangle(cornerRadius: 1).fill(.red), context: makeRenderContext(width: 6, height: 3)))
            #expect(box[1] == "██████")
        }
    }

    @Test("Shapes fill whatever they are offered")
    func flexible() {
        let size = Circle().sizeThatFits(ProposedSize(width: 30, height: 10))
        #expect(size.isWidthFlexible && size.isHeightFlexible)
        let stack = renderToBuffer(
            VStack(spacing: 0) {
                Rectangle().fill(.red)
                Text("x")
            }, context: makeRenderContext(width: 4, height: 5))
        #expect(stack.height == 5)
    }
}
