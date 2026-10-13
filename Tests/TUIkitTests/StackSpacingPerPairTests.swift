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

/// A view of the app's own that holds itself: the static witness must not
/// follow it round (a stack overflow, review of the fix for be3ee7385).
private struct Tree: View {
    let depth: Int
    var body: some View {
        if depth > 0 { Self(depth: depth - 1) }
    }
}

/// A view of the app's own whose body is two views, a tight row and a text —
/// `composite.swift`'s `Pair`, which a container takes apart into the two.
private struct Pair: View {
    var body: some View {
        Row { Text("a") }
        Text("b")
    }
}

/// Lays its subviews out as a `Row` does, and keeps `Layout`'s own
/// `spacing(subviews:cache:)`: its subviews' preferences, merged.
private struct Merging: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        Row().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        Row().placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

/// What a `GapsReader` or a `SpacingReader` read while it was measured.
@MainActor
private final class Read {
    var uniform: [Bool] = []
    var distances: [Int] = []
}

/// An `HStackLayout` that notes, each time it is measured, whether the gaps it
/// resolved for its subviews are all one value.
private struct GapsReader: Layout {
    let read: Read

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        read.uniform.append(HStackLayout().gaps(between: subviews).isUniform)
        return HStackLayout().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        HStackLayout().placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

/// A `Row` that notes, when it is measured, how far each subview's
/// `LayoutSubview.spacing` asks to be from a plain view after it.
private struct SpacingReader: Layout {
    let read: Read

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        read.distances = subviews.map { $0.spacing.distance(to: ViewSpacing(), along: .horizontal) }
        return Row().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        Row().placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
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

    @Test("An EmptyView member states nothing: a layout's merged preference is its other subviews' (SwiftUI counts no EmptyView)")
    func emptyMemberStatesNothing() {
        #expect(lines(HStack { Text("Name:"); Merging { Text("x"); EmptyView() } }) == ["Name: x"])
        let shows = false
        #expect(lines(HStack { Text("a"); Merging { Text("b"); if shows { Text("c") } else { EmptyView() } } }) == ["a b"])
        let read = Read()
        _ = lines(SpacingReader(read: read) { Text("a"); EmptyView(); Row { Text("b") } })
        #expect(read.distances == [1, 1, 0], "an EmptyView member's own preference is the default")
    }

    @Test("A stack layout puts its gaps only between subviews that take room, and measures what it draws")
    func layoutGapsSkipEmptyMembers() {
        let row = HStackLayout()
        #expect(lines(row { Text("a"); EmptyView(); Text("b") }) == ["a b"])
        #expect(lines(HStack { Text("Name:"); row { Text("x"); EmptyView() } }) == ["Name: x"])
        let hides = false
        let erased = AnyLayout(HStackLayout())
        #expect(lines(erased { Text("a"); if hides { Text("x") } else { EmptyView() }; Text("b") }) == ["a b"])
        let tight = row { Text("a"); EmptyView(); Row { Text("b") } }
        #expect(lines(tight) == ["ab"], "the gap is the one between a and b, not a's to the empty view")
        #expect(TUIkitView.measureChild(tight, proposal: .unspecified, context: context).width == 2)
        let spaced = HStackLayout(spacing: 1)
        let spacedRow = spaced { Text("a"); EmptyView(); Text("b") }
        #expect(TUIkitView.measureChild(spacedRow, proposal: .unspecified, context: context).width == 3)
        let column = VStackLayout(spacing: 1)
        let stacked = column { Text("a"); EmptyView(); Text("b") }
        #expect(TUIkitView.measureChild(stacked, proposal: .unspecified, context: context).height == 3)
    }

    @Test("HStackLayout asks no subview its preference where its content's type holds no layout")
    func layoutAsksNothingOnTheCommonPath() {
        let read = Read()
        // Padding is a provider at run time, so only the static gate keeps it unasked.
        _ = lines(GapsReader(read: read) { Text("a").padding(0); Text("b") })
        #expect(!read.uniform.isEmpty && read.uniform.allSatisfy { $0 }, "gaps by pair for a row of texts")
        let asked = Read()
        _ = lines(GapsReader(read: asked) { Row { Text("a") }; Text("b") })
        #expect(asked.uniform.contains(false), "a layout in the content is asked")
    }

    @Test("Through the modifiers that keep the content's edges (SwiftUI: foregroundStyle, background, offset, frame(height:) +0)")
    func throughEdgeKeepingModifiers() {
        #expect(lines(HStack { Row { Text("a") }.foregroundStyle(.red); Text("b") }) == ["ab"])
        #expect(lines(HStack { Row { Text("a") }.background(Color.red); Text("b") }) == ["ab"])
        #expect(lines(HStack { Row { Text("a") }.frame(height: 1); Text("b") }) == ["ab"])
        // An offset view's drawing is displaced into a layer of its own, so its
        // preference is read rather than drawn.
        let read = Read()
        _ = lines(SpacingReader(read: read) { Row { Text("a") }.offset(x: 1) })
        #expect(read.distances == [0])
    }

    @Test("Not through a frame that sets a width, nor .position (SwiftUI: frame(width: 40) +8, frame(maxWidth:) +8, position +8)")
    func notThroughMovedEdges() {
        // A fixed frame's content sits at its leading edge here (compatibility
        // guide §2.7), so the frame's own two blank columns, then the gap.
        #expect(lines(HStack { Row { Text("a") }.frame(width: 3); Text("b") }) == ["a   b"])
        let read = Read()
        _ = lines(
            SpacingReader(read: read) {
                Row { Text("a") }.frame(width: 3)
                Row { Text("a") }.frame(maxWidth: .fixed(5), alignment: .leading)
                Row { Text("a") }.position(x: 0, y: 0)
                Row { Text("a") }.frame(height: 1)
            })
        #expect(read.distances == [1, 1, 1, 0], "a frame that sets no width keeps the side edges")
    }

    /// Each of these is taken apart into its members, a tight `Row` among them,
    /// so the row has to ask; a static gate that stopped at the outer type drew
    /// `a b` for every one (review of be3ee7385).
    @Test("A view of the app's own of several views, a Section, a GridRow and a subview collection are asked (SwiftUI: composite +0)")
    func takenApartContentIsAsked() {
        #expect(lines(HStackLayout { Pair() }) == ["ab"])
        #expect(lines(HStack { Pair() }) == ["ab"])
        #expect(lines(HStackLayout { Section { Row { Text("a") }; Text("b") } }) == ["ab"])
        #expect(lines(HStackLayout { GridRow { Row { Text("a") }; Text("b") } }) == ["ab"])
        #expect(lines(Group(subviews: Group { Row { Text("a") }; Text("b") }) { subviews in HStackLayout { subviews } }) == ["ab"])
    }

    @Test("A recursive view of the app's own in a row is asked about once, not for ever")
    func recursiveViewTerminates() {
        func statesSpacing<V: View>(_: V) -> Bool { V._statesSpacingPreference }
        #expect(statesSpacing(Group { Tree(depth: 1); Text("b") }), "a view of several views MAY state one")
        #expect(lines(HStack { Tree(depth: 3); Text("b") }) == ["b"])
        #expect(lines(HStackLayout { Tree(depth: 2); Row { Text("a") }; Text("b") }) == ["ab"])
    }

    @Test("Not yet: an AnyView states the default, where SwiftUI's states what it erases (SwiftUI: anyview(all)|box +0)")
    func anyViewDoesNotForward() {
        #expect(lines(HStack { AnyView(Row { Text("a") }); Text("b") }) == ["a b"])
    }

    @Test("Not yet: a view of the app's own whose body is a tight layout states the default (SwiftUI: wrapped +0)")
    func appViewsDoNotForward() {
        #expect(lines(HStack { Wrapped(text: "a"); Text("b") }) == ["a b"])
    }
}
