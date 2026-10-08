//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewSpacingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

// MARK: - Fixtures

/// Places its subviews left to right, each pair as far apart as their
/// spacing preferences ask — the way SwiftUI's own `ViewSpacing` documentation
/// writes a layout that honours them.
private struct SpacedRow: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return ViewSize(width: widths.reduce(0, +) + gaps(subviews).reduce(0, +), height: 1)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        let gaps = gaps(subviews)
        var x = bounds.x
        for (index, subview) in subviews.enumerated() {
            if index > 0 { x += gaps[index - 1] }
            subview.place(at: (x: x, y: bounds.y), proposal: .unspecified)
            x += subview.sizeThatFits(.unspecified).width
        }
    }

    private func gaps(_ subviews: Subviews) -> [Int] {
        subviews.indices.dropLast().map {
            subviews[$0].spacing.distance(to: subviews[$0 + 1].spacing, along: .horizontal)
        }
    }
}

/// A layout that asks for no space around itself at all.
private struct Tight: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +), height: 1)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.x
        for subview in subviews {
            subview.place(at: (x: x, y: bounds.y), proposal: .unspecified)
            x += subview.sizeThatFits(.unspecified).width
        }
    }

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing { .zero }
}

/// What the subviews of a layout said they prefer.
@MainActor
private final class Seen {
    var spacings: [ViewSpacing] = []
}

private struct ReadsSpacing: Layout {
    let seen: Seen

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        seen.spacings = subviews.map(\.spacing)
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {}
}

// MARK: - Suite

/// `ViewSpacing`, `Layout.spacing(subviews:cache:)` and `LayoutSubview.spacing`,
/// in cells: a view prefers one column beside it and no row above or below.
@MainActor
@Suite("View spacing")
struct ViewSpacingTests {

    @Test("A view prefers one column beside it and no row above or below")
    func defaults() {
        #expect(ViewSpacing().distance(to: ViewSpacing(), along: .horizontal) == 1)
        #expect(ViewSpacing().distance(to: ViewSpacing(), along: .vertical) == 0)
        #expect(ViewSpacing.zero.distance(to: .zero, along: .horizontal) == 0)
        // The larger of the two facing edges wins.
        #expect(ViewSpacing.zero.distance(to: ViewSpacing(), along: .horizontal) == 1)
        #expect(ViewSpacing().distance(to: .zero, along: .horizontal) == 1)
    }

    @Test("A union takes each edge's larger preference, on the edges named")
    func unions() {
        #expect(ViewSpacing.zero.union(ViewSpacing()) == ViewSpacing())
        let leadingOnly = ViewSpacing.zero.union(ViewSpacing(), edges: .leading)
        #expect(leadingOnly.distance(to: .zero, along: .horizontal) == 0)
        #expect(ViewSpacing.zero.distance(to: leadingOnly, along: .horizontal) == 1)
        var formed = ViewSpacing.zero
        formed.formUnion(ViewSpacing(), edges: .trailing)
        #expect(formed != leadingOnly)
        #expect(formed.distance(to: .zero, along: .horizontal) == 1)
    }

    @Test("A subview states the default, and a layout among them its own preference")
    func subviewSpacing() {
        let seen = Seen()
        let reader = ReadsSpacing(seen: seen)
        let erased = AnyLayout(Tight())
        _ = renderToBuffer(
            reader {
                Text("a")
                Tight { Text("b") }
                SpacedRow { Text("c") }
                erased { Text("d") }
            },
            context: makeRenderContext(width: 20, height: 4))
        // A layout that states nothing merges its subviews' preferences: a
        // Text's, the default.
        #expect(seen.spacings == [ViewSpacing(), .zero, ViewSpacing(), .zero])
    }

    @Test("A layout spacing by preference keeps a column beside a view and none between two that want none")
    func spacingByPreference() {
        let lines = renderToBuffer(
            SpacedRow {
                Text("a")
                Text("b")
                Tight { Text("c") }
                Tight { Text("d") }
            },
            context: makeRenderContext(width: 20, height: 2)
        ).lines.map(\.stripped)
        #expect(lines == ["a b cd"])
    }

    @Test("A stack's spacing defaults to nil, which is what views prefer")
    func stacksTakeNil() {
        let context = makeRenderContext(width: 20, height: 4)
        func lines(_ view: some View) -> [String] {
            renderToBuffer(view, context: context).lines.map(\.stripped)
        }
        #expect(lines(HStack(spacing: nil) { Text("a"); Text("b") }) == ["a b"])
        #expect(lines(HStack { Text("a"); Text("b") }) == ["a b"])
        #expect(lines(VStack(spacing: nil) { Text("a"); Text("b") }) == ["a", "b"])
        #expect(HStackLayout().spacing == nil)
        #expect(VStackLayout(spacing: 2).spacing == 2)
        let row = AnyLayout(HStackLayout())
        #expect(lines(row { Text("a"); Text("b") }) == ["a b"])
    }
}
