//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewSpacingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitGrid
@testable import TUIkitTestSupport

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
    }

    /// SwiftUI's arithmetic, measured on macOS 15
    /// (`Tools/SwiftUIProbes/Stack spacing per pair/distances.out`, the
    /// `values` rows): `.zero` against `ViewSpacing()` is 0 apart either way
    /// round, where `ViewSpacing()` against itself is 8 points.
    @Test("A stated edge outweighs a default one it faces")
    func statedOutweighsDefault() {
        #expect(ViewSpacing.zero.distance(to: ViewSpacing(), along: .horizontal) == 0)
        #expect(ViewSpacing().distance(to: .zero, along: .horizontal) == 0)
        #expect(ViewSpacing().distance(to: .zero, along: .vertical) == 0)
    }

    /// Measured likewise: `.zero` merged with `ViewSpacing()` is still 0 from
    /// `ViewSpacing()`, either way round.
    @Test("A union keeps a stated edge over a default one, on the edges named")
    func unions() {
        #expect(ViewSpacing.zero.union(ViewSpacing()) == .zero)
        #expect(ViewSpacing().union(.zero) == .zero)
        #expect(ViewSpacing().union(ViewSpacing()) == ViewSpacing())
        let leadingTight = ViewSpacing().union(.zero, edges: .leading)
        #expect(ViewSpacing().distance(to: leadingTight, along: .horizontal) == 0, "its leading edge faces")
        #expect(leadingTight.distance(to: ViewSpacing(), along: .horizontal) == 1, "its trailing edge is the default")
        var trailingTight = ViewSpacing()
        trailingTight.formUnion(.zero, edges: .trailing)
        #expect(trailingTight != leadingTight)
        #expect(trailingTight.distance(to: ViewSpacing(), along: .horizontal) == 0)
        #expect(trailingTight.distance(to: leadingTight, along: .horizontal) == 0)
        #expect(leadingTight.distance(to: trailingTight, along: .horizontal) == 1)
    }

    @Test("A layout's default preference is its subviews', merged, and none for a layout with none")
    func defaultLayoutPreference() {
        let seen = Seen()
        let reader = ReadsSpacing(seen: seen)
        _ = renderToBuffer(
            reader {
                SpacedRow { Text("a"); Text("b") }
                SpacedRow { Text("c"); Tight { Text("d") } }
                SpacedRow {}
                GridLayout { Text("e"); Tight { Text("f") } }
            },
            context: makeRenderContext(width: 20, height: 4))
        #expect(seen.spacings == [ViewSpacing(), .zero, .zero, .zero])
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

    /// SwiftUI's: two boxes are 8 points apart, a box and a layout that
    /// states `.zero` are not apart at all (`distances.out`, `zero|box`).
    @Test("A layout spacing by preference keeps a column between two views and none beside one that wants none")
    func spacingByPreference() {
        let lines = renderToBuffer(
            SpacedRow {
                Text("a")
                Text("b")
                Tight { Text("c") }
                Text("d")
                Text("e")
            },
            context: makeRenderContext(width: 20, height: 2)
        ).lines.map(\.stripped)
        #expect(lines == ["a bcd e"])
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
