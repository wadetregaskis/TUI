//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutExplicitAlignmentTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Fixtures

private enum PinID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    fileprivate static let pin = Self(PinID.self)
}

/// Lays its subviews out left to right, one cell apart, and states nothing
/// about guides: the default `explicitAlignment` answers for it.
private struct Row: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return ViewSize(
            width: sizes.map(\.width).reduce(0, +) + max(0, sizes.count - 1),
            height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.x
        for subview in subviews {
            subview.place(at: (x: x, y: bounds.y), proposal: .unspecified)
            x += subview.sizeThatFits(.unspecified).width + 1
        }
    }
}

/// `Row`, with its leading guide moved three cells in — SwiftUI's own
/// `explicitAlignment` documentation example, in cells.
private struct Indented: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        Row().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        Row().placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout ()
    ) -> Double? {
        guide == .leading ? Double(bounds.x + 3) : nil
    }
}

// MARK: - Suite

/// `Layout.explicitAlignment`, against W05 probe r: a custom guide inside a
/// layout that does not override it propagates, merged; a built-in one does
/// not; an override is used.
@MainActor
@Suite("Layout explicit alignment")
struct LayoutExplicitAlignmentTests {

    private func indents(_ view: some View) -> [Int] {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 6)).lines.map { line in
            let stripped = line.stripped
            return stripped.count - stripped.drop(while: { $0 == " " }).count
        }
    }

    @Test("A custom guide set inside a layout reaches the stack aligning on it")
    func customGuidePropagates() {
        // "cd" is placed at x 3, so the row's own pin guide is 3, and "x"
        // moves to meet it.
        #expect(
            indents(
                VStack(alignment: .pin) {
                    Row {
                        Text("ab")
                        Text("cd").alignmentGuide(.pin) { _ in 0 }
                    }
                    Text("x").alignmentGuide(.pin) { _ in 0 }
                }) == [0, 3])
    }

    @Test("Through a framework layout, erased or not, the default merge still reports it")
    func customGuideThroughStackLayouts() {
        let erased = AnyLayout(HStackLayout(spacing: 1))
        #expect(
            indents(
                VStack(alignment: .pin) {
                    erased {
                        Text("ab")
                        Text("cd").alignmentGuide(.pin) { _ in 0 }
                    }
                    Text("x").alignmentGuide(.pin) { _ in 0 }
                }) == [0, 3])
    }

    @Test("A built-in guide set inside a layout is not reported by the default")
    func builtInGuideDoesNot() {
        #expect(
            indents(
                VStack(alignment: .leading) {
                    Row { Text("ab").alignmentGuide(.leading) { _ in 2 } }
                    Text("x")
                }) == [0, 0])
    }

    @Test("A layout's own explicitAlignment places it, erased or not")
    func overrideIsUsed() {
        #expect(
            indents(
                VStack(alignment: .leading) {
                    Indented { Text("ab") }
                    Text("x")
                }) == [0, 3])
        let erased = AnyLayout(Indented())
        #expect(
            indents(
                VStack(alignment: .leading) {
                    erased { Text("ab") }
                    Text("x")
                }) == [0, 3])
    }

    @Test("The default answers nothing for a built-in guide and merges a custom one")
    func defaultImplementation() {
        let context = makeRenderContext(width: 30, height: 4)
        let children = [
            ChildView(Text("ab"), childIndex: 0),
            ChildView(Text("cd").alignmentGuide(.pin) { _ in 1 }, childIndex: 1),
        ]
        let subviews = LayoutSubviews(
            children: children, context: context, placements: LayoutPlacements(),
            rowIDs: FlattenedRowIDs(content: EmptyView(), children: children))
        var cache: Void = ()
        let bounds = CellRect(x: 0, y: 0, width: 5, height: 1)
        Row().placeSubviews(in: bounds, proposal: .unspecified, subviews: subviews, cache: &cache)
        #expect(
            Row().explicitAlignment(
                of: HorizontalAlignment.pin, in: bounds, proposal: .unspecified, subviews: subviews,
                cache: &cache) == 4)
        #expect(
            Row().explicitAlignment(
                of: HorizontalAlignment.leading, in: bounds, proposal: .unspecified,
                subviews: subviews, cache: &cache) == nil)
    }
}
