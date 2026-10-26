//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutDefaultGuidesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Fixtures

/// How many times a layout was placed: once per layout pass, whether a
/// render's or a guide query's.
private final class Placements {
    var count = 0
}

/// Lays its subviews out left to right, one cell apart, counting each pass,
/// and states nothing about guides: the default `explicitAlignment` answers
/// for it, along both axes.
private struct CountedRow: Layout {
    let placements: Placements

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return ViewSize(
            width: sizes.map(\.width).reduce(0, +) + max(0, sizes.count - 1),
            height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        placements.count += 1
        var x = bounds.x
        for subview in subviews {
            subview.place(at: (x: x, y: bounds.y), proposal: .unspecified)
            x += subview.sizeThatFits(.unspecified).width + 1
        }
    }
}

/// `CountedRow`, with a top guide of its own one row down, and the default
/// for every horizontal guide.
private struct LoweredTop: Layout {
    let placements: Placements

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        CountedRow(placements: placements).sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        CountedRow(placements: placements).placeSubviews(
            in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout ()
    ) -> Double? {
        guide == .top ? Double(bounds.y + 1) : nil
    }
}

// MARK: - Suite

/// A layout of the app's own that keeps the default `explicitAlignment` is
/// found out the first time the default answers for it, and is not laid out
/// again to be asked for an edge or centre guide it cannot give a value
/// (`LayoutDefaultGuides`). The answers are the ones the pass gave.
@MainActor
@Suite("Layout default guides")
struct LayoutDefaultGuidesTests {

    private let dimensions = ViewDimensions(width: 10, height: 3)

    /// How many passes `child` is laid out in to answer `query`, asked twice:
    /// the second time's count, and both answers.
    private func passesAskedTwice(
        _ child: ChildView, _ query: AlignmentGuideQuery, placements: Placements
    ) -> (second: Int, answers: [Double?]) {
        let context = makeRenderContext(width: 30, height: 6)
        let first = child.explicitGuide(query, at: dimensions, context: context)
        placements.count = 0
        let second = child.explicitGuide(query, at: dimensions, context: context)
        return (placements.count, [first, second])
    }

    @Test("A layout that keeps the default is laid out once to be asked for an edge guide, not on every query")
    func edgeGuideAskedOnce() {
        let placements = Placements()
        let child = ChildView(CountedRow(placements: placements) { Text("ab"); Text("cd") }, childIndex: 0)
        let asked = passesAskedTwice(child, .horizontal(.leading), placements: placements)
        #expect(asked.second == 0)
        #expect(asked.answers == [nil, nil])
    }

    @Test("Erased by AnyLayout and inside a border, as a stack meets it, the same")
    func throughAnyLayoutAndBorder() {
        let placements = Placements()
        let layout = AnyLayout(CountedRow(placements: placements))
        let child = ChildView(layout { Text("ab"); Text("cd") }.border(), childIndex: 0)
        let asked = passesAskedTwice(child, .horizontal(.leading), placements: placements)
        #expect(asked.second == 0)
        #expect(asked.answers == [nil, nil])
    }

    @Test("A layout found keeping the horizontal default still gives its own vertical guide")
    func perAxis() {
        let placements = Placements()
        let child = ChildView(LoweredTop(placements: placements) { Text("ab"); Text("cd") }, childIndex: 0)
        #expect(passesAskedTwice(child, .horizontal(.leading), placements: placements).second == 0)
        let lowered = passesAskedTwice(child, .vertical(.top), placements: placements)
        #expect(lowered.second == 1)
        #expect(lowered.answers == [1, 1])
    }

    @Test("A stack aligning on an edge places the layout as before, once its type is known")
    func stillAligned() {
        let placements = Placements()
        let view = VStack(alignment: .trailing) {
            Text("a much wider line")
            CountedRow(placements: placements) { Text("ab"); Text("cd") }.border()
        }
        let first = renderToBuffer(view, context: makeRenderContext(width: 20, height: 6)).lines.map(\.stripped)
        let second = renderToBuffer(view, context: makeRenderContext(width: 20, height: 6)).lines.map(\.stripped)
        #expect(first == second)
        #expect(first == ["a much wider line", "        ╭───────╮", "        │ ab cd │", "        ╰───────╯"])
    }
}
