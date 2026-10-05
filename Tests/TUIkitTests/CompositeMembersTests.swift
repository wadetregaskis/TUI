//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeMembersTests.swift
//
//  A view of the app's own whose `body` is several views is, to the container
//  laying it out, those views — as SwiftUI's is (measured on macOS 15.8,
//  `D1S/probe2/composite`): beside a view it is three subviews of a `Layout`,
//  an `HStack` lays all three along its row, `Group(subviews:)` counts two, a
//  `List` draws three rows; so is one inside another, a body that is a loop,
//  and one that is an `if` (none while false); a loop of them is each one's
//  views. It was one child everywhere, its body stacked in a column. Decisions
//  D1S, B-D1S-6.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
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
        #expect(Array(lines(VStack(alignment: .leading, spacing: 1) { Pair(tag: "r"); Text("c") }).prefix(5))
            == ["ra", "", "rb", "", "c"])
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
        #expect(Array(drawn.prefix(3)).map { String($0.prefix(2)) } == ["0a", "0b", "1a"], "\(drawn)")
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
}
