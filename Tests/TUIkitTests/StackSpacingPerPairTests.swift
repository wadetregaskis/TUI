//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackSpacingPerPairTests.swift
//
//  A row's `spacing: nil` resolved per pair of neighbours (decisions B20): the
//  distance two children's `ViewSpacing`s ask for, where a child states one —
//  a custom `Layout` through its `spacing(subviews:cache:)`. The SwiftUI side
//  of each expectation is `Tools/SwiftUIProbes/Stack spacing per pair/spacing.out`,
//  in points: 8 there is a column here, 0 is none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

// MARK: - Fixtures

/// Which edges a `Row` asks to be left without space.
private enum Tightness { case all, leading, trailing }

/// Lays its subviews in a row with no space between them, and asks for none
/// on the edges `tight` names — `spacing.swift`'s `Row`.
private struct Row: Layout {
    var tight = Tightness.all
    var asked: Asked?

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(
            width: subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +),
            height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.x
        for subview in subviews {
            subview.place(at: (x: x, y: bounds.y), proposal: .unspecified)
            x += subview.sizeThatFits(.unspecified).width
        }
    }

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
        asked?.times += 1
        var stated = ViewSpacing()
        switch tight {
        case .all: stated.formUnion(.zero)
        case .leading: stated.formUnion(.zero, edges: .leading)
        case .trailing: stated.formUnion(.zero, edges: .trailing)
        }
        return stated
    }
}

/// How many times a `Row` was asked its spacing.
@MainActor
private final class Asked {
    var times = 0
}

/// A view of the app's own whose body is a tight row.
private struct Wrapped: View {
    let text: String
    var body: some View { Row { Text(text) } }
}

// MARK: - Suite

@MainActor
@Suite("A row's spacing: nil, per pair of neighbours")
struct StackSpacingPerPairTests {
    private let context = makeRenderContext(width: 30, height: 4)

    private func lines(_ view: some View) -> [String] {
        renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @Test("Two layouts that ask for no space between them get none (B20's example; SwiftUI: all|all +0)")
    func twoTightLayouts() {
        #expect(lines(HStack { Row { Text("a") }; Row { Text("b") } }) == ["ab"])
        #expect(lines(HStack { Text("a"); Text("b") }) == ["a b"], "two plain views keep their column")
    }

    @Test("One neighbour asking for none is enough (SwiftUI: all|box +0, box|all +0)")
    func oneTightNeighbour() {
        #expect(lines(HStack { Row { Text("a") }; Text("b") }) == ["ab"])
        #expect(lines(HStack { Text("a"); Row { Text("b") }; Text("c") }) == ["abc"])
    }

    @Test("Only the facing edges count (SwiftUI: box|leading|box +0 +8, box|trailing|box +8 +0)")
    func facingEdges() {
        #expect(lines(HStack { Text("a"); Row(tight: .leading) { Text("b") }; Text("c") }) == ["ab c"])
        #expect(lines(HStack { Text("a"); Row(tight: .trailing) { Text("b") }; Text("c") }) == ["a bc"])
        #expect(lines(HStack { Row(tight: .leading) { Text("a") }; Row(tight: .trailing) { Text("b") } }) == ["a b"])
    }

    @Test("A stated spacing is every gap (SwiftUI: hstack(spacing: 5) +5 +5)")
    func statedSpacingWins() {
        #expect(lines(HStack(spacing: 2) { Row { Text("a") }; Row { Text("b") } }) == ["a  b"])
        #expect(lines(HStack(spacing: 1) { Text("a"); Row { Text("b") }; Text("c") }) == ["a b c"])
    }

    @Test("Through a loop, a group, an if and an empty view (SwiftUI: +0 for each)")
    func throughProviders() {
        #expect(lines(HStack { ForEach(["a", "b", "c"], id: \.self) { letter in Row { Text(letter) } } }) == ["abc"])
        #expect(lines(HStack { Group { Row { Text("a") }; Row { Text("b") } } }) == ["ab"])
        let shows = true
        #expect(lines(HStack { if shows { Row { Text("a") } }; Row { Text("b") } }) == ["ab"])
        #expect(lines(HStack { Row { Text("a") }; EmptyView(); Row { Text("b") } }) == ["ab"])
        let erased = AnyLayout(Row())
        #expect(lines(HStack { erased { Text("a") }; Text("b") }) == ["ab"])
    }

    @Test("Through a wrapper that changes nothing at the edges, and not through padding (SwiftUI: .id +0, .padding(4) +8)")
    func throughWrappers() {
        #expect(lines(HStack { Row { Text("a") }.id(1); Text("b") }) == ["ab"])
        #expect(lines(HStack { Row { Text("a") }.onAppear {}; Text("b") }) == ["ab"])
        #expect(
            lines(HStack { Row { Text("a") }.padding(.horizontal, 1); Text("b") }) == [" a  b"],
            "a padded edge is the default again")
        #expect(
            lines(HStack { Row { Text("a") }.padding(.leading, 1); Text("b") }) == [" ab"],
            "an edge the padding leaves alone keeps the layout's preference")
    }

    @Test("A lazy row and HStackLayout resolve per pair too; a column never had a gap to lose")
    func otherStacks() {
        #expect(lines(LazyHStack { Row { Text("a") }; Text("b") }) == ["ab"])
        let row = HStackLayout()
        #expect(lines(row { Row { Text("a") }; Row { Text("b") }; Text("c") }) == ["abc"])
        #expect(lines(row { Text("a"); Text("b") }) == ["a b"])
        let spaced = HStackLayout(spacing: 1)
        #expect(lines(spaced { Row { Text("a") }; Text("b") }) == ["a b"])
        #expect(lines(VStack { Row { Text("a") }; Row { Text("b") } }) == ["a", "b"])
    }

    @Test("A row is measured as it draws")
    func measuredAsDrawn() {
        let row = HStack { Text("a"); Row { Text("b") }; Text("c"); Text("d") }
        #expect(TUIkitView.measureChild(row, proposal: .unspecified, context: context).width == 5)
        #expect(lines(row) == ["abc d"])
    }

    @Test("A row with a stated spacing, or no child that states one, never asks")
    func commonPathAsksNothing() {
        let asked = Asked()
        _ = lines(HStack(spacing: 1) { Row(asked: asked) { Text("a") }; Row(asked: asked) { Text("b") } })
        #expect(asked.times == 0, "a stated spacing is every gap")
        _ = lines(HStack { Row(asked: asked) { Text("a") }; Row(asked: asked) { Text("b") } })
        #expect(asked.times > 0, "and nil asks the layouts")
    }

    @Test("Not yet: a view of the app's own whose body is a tight layout states the default (SwiftUI: wrapped +0)")
    func appViewsDoNotForward() {
        #expect(lines(HStack { Wrapped(text: "a"); Text("b") }) == ["a b"])
    }
}
