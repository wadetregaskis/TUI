//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeMembersTests.swift
//
//  A view of the app's own whose `body` is several views is, to the container
//  laying it out, those views — as SwiftUI's is (measured on macOS 15.8,
//  `Tools/SwiftUIProbes/Sections and subview counting/composite.swift`): beside
//  a view it is three subviews of a `Layout`,
//  an `HStack` lays all three along its row, `Group(subviews:)` counts two, a
//  `List` draws three rows; so is one inside another, a body that is a loop,
//  and one that is an `if` (none while false); a loop of them is each one's
//  views. It was one child everywhere, its body stacked in a column. So is a
//  body that is an `if`/`else` with an arm of several views, or a modifier on
//  several (`composite-bodies.swift` beside it). Decisions D1S, B-D1S-6.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitListsTestSupport
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Two views, as a body.
private struct Pair: View {
    let tag: String
    var body: some View {
        Text("\(tag)a")
        Text("\(tag)b")
    }
}

/// A view whose body is another of the app's own.
private struct Nested: View {
    var body: some View { Pair(tag: "n") }
}

/// A view whose body is a loop.
private struct Loop: View {
    var body: some View { ForEach(0..<3, id: \.self) { Text("l\($0)") } }
}

/// A view whose body is an `if`.
private struct Shown: View {
    let show: Bool
    var body: some View { if show { Text("i") } }
}

/// A body of one view: kept the one child it always was.
private struct Single: View {
    var body: some View { HStack { Text("s1"); Text("s2") } }
}

/// A view with `@State` of its own, and a button that changes it.
private struct Tally: View {
    @State private var count = 0
    var body: some View {
        Text("count \(count)")
        Button("add") { count += 1 }
    }
}

/// A section of the app's own, deletable by its rows' elements.
private struct ItemsSection: View {
    let items: [String]
    let deleted: (IndexSet) -> Void
    var body: some View {
        Section("Items") {
            ForEach(items, id: \.self) { Text($0) }
                .onDelete(perform: deleted)
        }
    }
}

/// A row whose body holds its own type in both arms of an `if`/`else` —
/// never drawn here, only counted: a count that descended both arms at every
/// level made 2³² calls before its depth bound stopped it.
private struct SelfNested: View {
    let flag: Bool
    var body: some View {
        Text("x")
        if flag { Self(flag: false) } else { Self(flag: true) }
    }
}

/// A body that is an `if`/`else` with an arm of several views.
private struct Branch: View {
    let flag: Bool
    var body: some View {
        if flag {
            Text("a")
            Text("b")
        } else {
            Text("c")
        }
    }
}

/// A body that is a modifier on several views.
private struct FramedPair: View {
    var body: some View {
        Group {
            Text("a")
            Text("b")
        }
        .frame(width: 3, alignment: .leading)
    }
}

/// A body that is a padding on several views.
private struct PaddedPair: View {
    var body: some View {
        Group {
            Text("a")
            Text("b")
        }
        .padding(.leading, 1)
    }
}

/// A body that is an effect on several views.
private struct AppearingPair: View {
    let appeared: () -> Void
    var body: some View {
        Group {
            Text("a")
            Text("b")
        }
        .onAppear(perform: appeared)
    }
}

/// A view whose body holds its own type, padded, in one arm of an
/// `if`/`else`: asked whether it hands over children, it would ask itself for
/// ever through the arm and the padding, were the answer not kept per type.
private struct Tree: View {
    let depth: Int
    var body: some View {
        if depth == 0 { Text("leaf") } else { Self(depth: depth - 1).padding(.leading, 1) }
    }
}

/// What a layout was handed.
@MainActor
private final class Count {
    var subviews = -1
}

private struct Counting: Layout {
    let count: Count

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        count.subviews = subviews.count
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

@MainActor
@Suite("A view whose body is several views is several children")
struct CompositeMembersTests {

    private func lines(_ view: some View, width: Int = 30, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped).map { $0.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
    }

    private func layoutCount(@ViewBuilder _ content: () -> some View) -> Int {
        let count = Count()
        _ = lines(Counting(count: count)(content))
        return count.subviews
    }

    private func subviewCount(_ view: some View) -> Int {
        var count = -1
        _ = lines(
            Group(subviews: view) { subviews -> EmptyView in
                count = subviews.count
                return EmptyView()
            })
        return count
    }

    @Test("A Layout and the subview APIs count a body's views, as SwiftUI does")
    func counts() {
        #expect(layoutCount { Pair(tag: "r"); Text("c") } == 3)
        #expect(layoutCount { Nested() } == 2)
        #expect(layoutCount { Loop() } == 3)
        #expect(layoutCount { Shown(show: false); Text("c") } == 1)
        #expect(layoutCount { Shown(show: true); Text("c") } == 2)
        #expect(layoutCount { ForEach(0..<2, id: \.self) { Pair(tag: "f\($0)") } } == 4)
        #expect(subviewCount(Pair(tag: "s")) == 2)
        // A body of one view is the one child it always was.
        #expect(layoutCount { Single(); Text("c") } == 2)
    }

    @Test("An HStack lays a body's views along its row, and a VStack spaces each")
    func stacks() {
        #expect(lines(HStack(spacing: 1) { Pair(tag: "r"); Text("c") }).first == "ra rb c")
        #expect(lines(HStack(spacing: 1) { Loop() }).first == "l0 l1 l2")
        let stacked = VStack(alignment: .leading, spacing: 1) { Pair(tag: "r"); Text("c") }
        let stackedLines: [String] = Array(lines(stacked).prefix(5))
        #expect(stackedLines == ["ra", "", "rb", "", "c"])
    }

    @Test("A List draws each of a body's views as a row")
    func list() {
        let drawn = lines(List { Pair(tag: "r"); Text("c") }.frame(height: 6), height: 6)
        #expect(drawn.contains { $0.contains("ra") } && drawn.contains { $0.contains("rb") }, "\(drawn)")
        let alone = ListSectionEditingFixture()
        alone.render(List(selection: .constant(String?.none)) { Pair(tag: "r") }.frame(height: 6))
        #expect(alone.handler?.itemCount == 2)
    }

    @Test("A view taken apart keeps its @State: a change made through one of its views shows in another")
    func keepsState() throws {
        let context = makeRenderContext(width: 40, height: 6)
        let view = HStack(spacing: 1) { Tally() }
        #expect(renderToBuffer(view, context: context).lines.first?.stripped.hasPrefix("count 0") == true)
        let manager = try #require(context.environment.focusManager)
        let button = try #require(manager.registeredFocusIDsInActiveSection().first)
        manager.focus(id: button)
        _ = renderToBuffer(view, context: context)
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .enter)))
        let after = renderToBuffer(view, context: context).lines.first?.stripped ?? ""
        #expect(after.hasPrefix("count 1"), "\(after)")
    }

    @Test("A loop of rows whose body is several views is lazy over them in a lazy stack")
    func loopOfComposites() {
        let loop = ForEach(0..<100_000, id: \.self) { Pair(tag: "\($0)") }
        #expect(loop.rowShape(sectionWholeness: .apart) == .fixed(2))
        let drawn = lines(
            ScrollView { LazyVStack(alignment: .leading, spacing: 0) { loop } }.frame(height: 4), height: 4)
        let heads: [String] = drawn.prefix(3).map { String($0.prefix(2)) }
        #expect(heads == ["0a", "0b", "1a"], "\(drawn)")
    }

    @Test("Beside another section in a List, a section of the app's own is a section: its header drawn, its rows selected by element and deletable")
    func sectionOfTheAppsOwnInAList() {
        let fixture = ListSectionEditingFixture()
        var deleted: [IndexSet] = []
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Other") { Text("x").tag("x") }
                ItemsSection(items: ["alpha", "beta"]) { deleted.append($0) }
            }
            .frame(height: 10))
        let ids = (0..<(fixture.handler?.itemCount ?? 0)).map { fixture.handler?.id(at: $0) }
        #expect(ids == [nil, "x", nil, "alpha", "beta"], "\(ids)")
        #expect(fixture.pressDelete(onRow: 4, named: "beta"))
        #expect(deleted == [IndexSet(integer: 1)])
    }

    @Test("A body that is an if/else of several views is those views, as SwiftUI's is")
    func ifElseBody() {
        #expect(lines(HStack(spacing: 1) { Branch(flag: true) }).first == "a b")
        #expect(lines(HStack(spacing: 1) { Branch(flag: false); Text("d") }).first == "c d")
        #expect(layoutCount { Branch(flag: true); Text("c") } == 3)
    }

    @Test("A body that is a modifier on several views is each of them, modified, as SwiftUI's is")
    func modifiedBody() {
        #expect(lines(HStack(spacing: 0) { FramedPair() }).first == "a  b")
        #expect(lines(HStack(spacing: 0) { PaddedPair() }).first == " a b")
        #expect(layoutCount { FramedPair() } == 2)
    }

    /// SwiftUI fires an effect on several views once (semantic audit item
    /// 50), so the effect wrappers hand no members on, and a view whose body
    /// is one stays one view: its effect fires once, not once per member.
    @Test("A body that is an effect on several views fires its effect once")
    func effectBodyFiresOnce() {
        var appeared = 0
        _ = lines(HStack(spacing: 1) { AppearingPair { appeared += 1 } })
        #expect(appeared == 1)
    }

    @Test("A view whose body holds its own type in an arm is asked once whether it hands over children")
    func selfNestedBodyIsAskedOnce() {
        #expect(!Tree._handsOverChildren)
        #expect(lines(HStack { Tree(depth: 3) }).first == "   leaf")
    }

    @Test("Counting a row whose body holds its own type in both arms of an if/else descends each type once")
    func selfNestedCountIsBounded() {
        CompositeBodyDescent.bodiesCounted = 0
        #expect(staticRowMemberCount(SelfNested.self) == nil)
        #expect(ForEach(0..<2, id: \.self) { SelfNested(flag: $0 == 0) }.rowShape(sectionWholeness: .apart) == .varying)
        #expect(CompositeBodyDescent.bodiesCounted < 16, "descended \(CompositeBodyDescent.bodiesCounted) bodies")
    }
}
