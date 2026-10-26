//  🖥️ TUI — A Terminal UI framework for Swift
//  ContainerShapeTests.swift
//
//  A container's shape, and the shapes inside it that follow it: the
//  container-relative shape and the concentric rectangle, with the corner
//  vocabulary they are spelled in.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// The glyphs of `view` rendered in a `width` × `height` frame.
@MainActor
private func glyphs(_ view: some View, width: Int, height: Int) -> [String] {
    renderToScreen(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
}

@MainActor
@Suite("Container shapes, and the shapes that follow them")
struct ContainerShapeTests {

    @Test("With no container, a container-relative shape is a rectangle")
    func noContainer() {
        #expect(glyphs(ContainerRelativeShape().stroke(.red), width: 6, height: 3) == ["┌────┐", "│    │", "└────┘"])
        #expect(glyphs(ConcentricRectangle().stroke(.red), width: 6, height: 3) == ["┌────┐", "│    │", "└────┘"])
    }

    @Test("A container-relative shape is the container's, inset by how far inside it lies")
    func concentric() {
        let flush = ContainerRelativeShape().stroke(.red).containerShape(RoundedRectangle(cornerRadius: 3))
        #expect(glyphs(flush, width: 6, height: 3) == ["╭────╮", "│    │", "╰────╯"])
        // A cell in from the container: a radius of 3 keeps 2, rounded; a
        // radius of 1 is used up, square.
        let roomy = ContainerRelativeShape().stroke(.red).padding(1).containerShape(RoundedRectangle(cornerRadius: 3))
        #expect(glyphs(roomy, width: 8, height: 5)[1] == " ╭────╮ ")
        let tight = ContainerRelativeShape().stroke(.red).padding(1).containerShape(RoundedRectangle(cornerRadius: 1))
        #expect(glyphs(tight, width: 8, height: 5)[1] == " ┌────┐ ")
        // Its border, too.
        let border = ContainerRelativeShape().strokeBorder(.red).containerShape(Capsule())
        #expect(glyphs(border, width: 6, height: 3)[0] == "╭────╮")
    }

    @Test("A concentric rectangle's corners follow the container's, or keep a fixed radius")
    func concentricRectangle() {
        let inside = ConcentricRectangle().stroke(.red).padding(1).containerShape(RoundedRectangle(cornerRadius: 3))
        #expect(glyphs(inside, width: 8, height: 5)[1] == " ╭────╮ ")
        let fixed = ConcentricRectangle(corners: .fixed(0)).stroke(.red).containerShape(RoundedRectangle(cornerRadius: 3))
        #expect(glyphs(fixed, width: 6, height: 3)[0] == "┌────┐")
        let mixed = ConcentricRectangle(topLeadingCorner: .concentric, topTrailingCorner: 0, bottomLeadingCorner: 0)
            .stroke(.red).containerShape(RoundedRectangle(cornerRadius: 2))
        #expect(glyphs(mixed, width: 6, height: 3) == ["╭────┐", "│    │", "└────╯"])
        let minimum = ConcentricRectangle(corners: .concentric(minimum: 2)).stroke(.red)
        #expect(glyphs(minimum, width: 6, height: 3)[0] == "╭────╮")
    }

    /// A column of rows inside a rounded container: the top and bottom rows
    /// round their outer corners, the middle one — four columns in from the
    /// sides and six units from the top and bottom — is square.
    private func column(_ items: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                ZStack {
                    ContainerRelativeShape().stroke(.red)
                    Text(item)
                }
                .frame(width: 6, height: 3)
            }
        }
        .padding(.horizontal, 4)
        .containerShape(RoundedRectangle(cornerRadius: 2))
    }

    /// `ForEach` memoizes each row by its element, keyed by its identity, value
    /// and size — not by where it is. Before, a container-relative shape read
    /// its place without saying so, a row reordered under the same size was
    /// served the buffer drawn where it was, and kept that place's corners.
    @Test("A row that moves inside its container takes the corners of where it now is")
    func movedRowTakesItsNewCorners() {
        let context = makeRenderContext(width: 14, height: 9)
        let cache = context.renderCache!
        func frame(_ items: [String]) -> [String] {
            cache.beginRenderPass()
            defer { cache.removeInactive() }
            return renderToScreen(column(items), context: context).lines.map(\.stripped)
        }
        let first = frame(["a", "b", "c"])
        #expect(first[0] == "    ╭────╮    " && first[3] == "    ┌────┐    ", "\(first)")
        let moved = frame(["b", "a", "c"])
        #expect(moved[0] == "    ╭────╮    ", "the middle row, moved to the top, kept its square corners: \(moved)")
        #expect(moved[3] == "    ┌────┐    ", "the top row, moved to the middle, kept its round corners: \(moved)")
        #expect(moved[1].contains("b") && moved[4].contains("a"))
    }

    /// Before, two container shapes were compared by their paths in a 64-unit
    /// square, where radii of 35 and 40 both clamp to 32: the same, so a
    /// change from one to the other cleared nothing, though a view 37 units in
    /// is square inside the first and rounded inside the second.
    @Test("Container shapes that differ in any frame a terminal has compare unequal")
    func containerShapeComparison() {
        let small = ErasedInsettableShape(RoundedRectangle(cornerRadius: 35))
        #expect(small == ErasedInsettableShape(RoundedRectangle(cornerRadius: 35)))
        #expect(small != ErasedInsettableShape(RoundedRectangle(cornerRadius: 40)))
        #expect(small != ErasedInsettableShape(RoundedRectangle(cornerRadius: 35, style: .circular)))
        #expect(small != ErasedInsettableShape(Rectangle()))
    }

    @Test("The corner vocabulary: corners, sets of them, and styles")
    func corners() {
        #expect(Edge.Corner.Set.top.contains(.topLeading))
        #expect(!Edge.Corner.Set.top.contains(.bottomLeading))
        #expect(Edge.Corner.Set.all == [.leading, .trailing])
        #expect(Edge.Corner.allCases.count == 4)
        let literal: Edge.Corner.Style = 2
        #expect(literal == .fixed(2))
        let decimal: Edge.Corner.Style = 1.5
        #expect(decimal == .fixed(1.5))
        #expect(RoundedRectangularShapeCorners(all: 2)[.bottomTrailing] == .fixed(2))
        #expect(RectangleCornerRadii(topLeading: 1, bottomTrailing: 3)[.bottomTrailing] == 3)
    }

    @Test("The rounded rectangular shapes say their corners")
    func roundedRectangularCorners() {
        #expect(Rectangle().corners(in: nil) == .fixed(0))
        #expect(RoundedRectangle(cornerRadius: 2).corners(in: nil) == .fixed(2))
        #expect(RoundedRectangle(cornerRadius: 20).corners(in: CGSize(width: 10, height: 4)) == .fixed(2))
        #expect(UnevenRoundedRectangle(topLeadingRadius: 1).corners(in: nil)?.topLeading == .fixed(1))
        #expect(Capsule().corners(in: nil) == nil)
        #expect(Circle().corners(in: CGSize(width: 10, height: 4)) == .fixed(2))
    }
}
