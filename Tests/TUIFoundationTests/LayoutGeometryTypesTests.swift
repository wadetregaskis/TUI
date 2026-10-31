//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutGeometryTypesTests.swift
//
//  The geometry a custom `Layout` handles fits together: a position is a
//  `CellPoint` wherever it comes from, and a size can be proposed whichever type
//  it arrived as.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// Places its one subview where it is told, with the `CellPoint` overload.
private struct PlacedAt: Layout {
    let position: CellPoint
    var anchor: UnitPoint = .topLeading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(CellSize(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(
                at: CellPoint(x: bounds.origin.x + position.x, y: bounds.origin.y + position.y),
                anchor: anchor, proposal: ProposedViewSize(subview.sizeThatFits(.unspecified)))
        }
    }
}

/// Offers its subview the whole of its bounds, as a proposal of their size.
private struct FillsBounds: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedSize(bounds.size))
        }
    }
}

/// Answers nothing, and places nothing.
private struct Empty: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize { .zero }
    func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

@MainActor
@Suite("The geometry types of a custom Layout")
struct LayoutGeometryTypesTests {
    private func screen(_ view: some View, width: Int, height: Int) -> [String] {
        renderToScreen(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
    }

    @Test("Zero is nothing, fixed on both axes")
    func zero() {
        #expect(CellSize.zero == CellSize(width: 0, height: 0))
        #expect(ViewSize.zero == ViewSize.fixed(0, 0))
    }

    @Test("A proposal can be made of either kind of size")
    func proposals() {
        #expect(ProposedSize(ViewSize.fixed(3, 2)) == ProposedSize(width: 3, height: 2))
        #expect(ProposedSize(ViewSize.flexible(minWidth: 3, minHeight: 2)) == ProposedSize(width: 3, height: 2))
        #expect(ProposedSize(CellSize(width: 3, height: 2)) == ProposedSize(width: 3, height: 2))
    }

    @Test("ProposedViewSize is SwiftUI's name for ProposedSize")
    func typealiasIsTheSameType() {
        #expect(ProposedViewSize.self == ProposedSize.self)
        #expect(ProposedViewSize.zero == ProposedSize.zero)
    }

    @Test("The two sizes convert, a CellSize becoming fixed and a ViewSize losing its flexibility")
    func conversions() {
        #expect(ViewSize(CellSize(width: 3, height: 2)) == ViewSize.fixed(3, 2))
        #expect(CellSize(ViewSize.flexible(minWidth: 3, minHeight: 2)) == CellSize(width: 3, height: 2))
    }

    @Test("A subview placed at a CellPoint lands where the tuple's does")
    func placedAtCellPoint() {
        let lines = screen(PlacedAt(position: CellPoint(x: 2, y: 1)) { Text("x") }.frame(width: 4, height: 2), width: 4, height: 2)
        #expect(lines == ["    ", "  x "])
    }

    @Test("A CellPoint placement takes an anchor")
    func placedAtCellPointWithAnchor() {
        let lines = screen(
            PlacedAt(position: CellPoint(x: 4, y: 0), anchor: .topTrailing) { Text("ab") }.frame(width: 4, height: 1),
            width: 4, height: 1)
        #expect(lines == ["  ab"])
    }

    @Test("Bounds can be proposed as they are")
    func proposedBounds() {
        let lines = screen(
            FillsBounds { Color.red.frame(maxWidth: .infinity, maxHeight: .infinity).overlay { Text("x") } }
                .frame(width: 3, height: 3),
            width: 3, height: 3)
        #expect(lines == ["   ", " x ", "   "])
    }

    @Test("A layout can answer .zero")
    func answersZero() {
        let buffer = renderToBuffer(Empty { Text("gone") }, context: makeRenderContext(width: 4, height: 2))
        #expect(buffer.width == 0 && buffer.height == 0, "\(buffer.lines)")
    }
}
