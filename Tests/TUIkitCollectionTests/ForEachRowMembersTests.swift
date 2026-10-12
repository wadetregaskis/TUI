//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForEachRowMembersTests.swift
//
//  A `ForEach` row of several views hands its container each of them, as
//  SwiftUI's does (measured on macOS 15.8, probe
//  `Tools/SwiftUIProbes/Sections and subview counting/b15.swift`):
//  `ForEach(0..<2) { _ in Group { a; b } }` is four subviews,
//  and so is the same row as a tuple; a row of sections is their parts; a
//  loop in a row is its rows; an `EmptyView` row is none. Decisions B15.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What a transform or a layout was handed.
@MainActor
private final class Seen {
    var count = -1
    var tags: [Int?] = []
    var built = 0
}

/// Reports its subviews' count and implicit `Int` tags.
private struct Counting: Layout {
    let seen: Seen

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        seen.count = subviews.count
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

@MainActor
@Suite("A ForEach row of several views is several children")
struct ForEachRowMembersTests {

    private func render(_ view: some View, width: Int = 30, height: Int = 12) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    /// How many subviews `content` has.
    private func count(@ViewBuilder _ content: () -> some View) -> Int {
        let seen = Seen()
        _ = render(
            Group(subviews: content()) { subviews -> EmptyView in
                seen.count = subviews.count
                return EmptyView()
            })
        return seen.count
    }

    @Test("Rows of a Group, a tuple, a loop, a section and an if are taken apart, as SwiftUI counts them")
    func counts() {
        #expect(count { ForEach(0..<2, id: \.self) { _ in Group { Text("a"); Text("b") } } } == 4)
        #expect(count { ForEach(0..<2, id: \.self) { _ in Text("a"); Text("b") } } == 4)
        #expect(count { ForEach(0..<2, id: \.self) { _ in ForEach(0..<3, id: \.self) { Text("\($0)") } } } == 6)
        #expect(count { ForEach(0..<2, id: \.self) { _ in Section { Text("a") } header: { Text("h") } } } == 4)
        #expect(count { ForEach(0..<3, id: \.self) { i in if i != 1 { Text("a"); Text("b") } } } == 4)
        #expect(count { ForEach(0..<2, id: \.self) { _ in Group { Text("a"); Text("b") }.padding(1) } } == 4)
        #expect(count { ForEach(0..<2, id: \.self) { _ in EmptyView() } } == 0)
    }

    @Test("A Layout sees each of a row's views as a subview")
    func layoutSubviews() {
        let seen = Seen()
        _ = render(Counting(seen: seen) { ForEach(0..<3, id: \.self) { _ in Text("a"); Text("b") } })
        #expect(seen.count == 6)
    }

    @Test("Each of a row's views is tagged with its element, as SwiftUI tags them")
    func implicitTags() {
        let seen = Seen()
        _ = render(
            Group(subviews: ForEach(0..<2, id: \.self) { _ in Group { Text("a"); Text("b") } }) { subviews -> EmptyView in
                seen.tags = subviews.map { $0.containerValues.tag(for: Int.self) }
                return EmptyView()
            })
        #expect(seen.tags == [0, 0, 1, 1])
    }

    @Test("An HStack lays a row's views along the row")
    func row() {
        let drawn = render(HStack(spacing: 1) { ForEach(0..<2, id: \.self) { i in Group { Text("a\(i)"); Text("b\(i)") } } })
        #expect(drawn.first == "a0 b0 a1 b1")
    }

    @Test("A VStack spaces every one of a row's views")
    func column() {
        let drawn = render(
            VStack(alignment: .leading, spacing: 1) { ForEach(0..<2, id: \.self) { i in Text("a\(i)"); Text("b\(i)") } })
        #expect(drawn == ["a0", "", "b0", "", "a1", "", "b1"])
    }

    @Test("A row's views each draw at an identity of their own, below the row's")
    func identities() {
        let children = resolveChildViews(
            from: ForEach(["x", "y"], id: \.self) { name in Text(name); Text(name) },
            context: makeRenderContext(width: 10, height: 4))
        let paths = children.compactMap(\.pinnedIdentity).map(\.path)
        #expect(paths.count == 4)
        #expect(Set(paths).count == 4)
        #expect(children.map(\.identityChildKey) == [identityKey("x"), identityKey("x"), identityKey("y"), identityKey("y")])
    }

    @Test("A lazy stack over rows of two views builds only the rows it draws")
    func lazyStaysWindowed() {
        let seen = Seen()
        /// Element `i`'s row of two, counted as it is built.
        func pair(_ i: Int) -> some View {
            seen.built += 1
            return Group {
                Text("a\(i)")
                Text("b\(i)")
            }
        }
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<100_000, id: \.self) { pair($0) }
            }
        }
        .frame(height: 6)
        let drawn = render(view, height: 6)
        let heads: [String] = drawn.prefix(4).map { String($0.prefix(2)) }
        #expect(heads == ["a0", "b0", "a1", "b1"])
        #expect(seen.built < 1_000, "built \(seen.built) rows")
    }

    @Test("A List draws each of a row's views as a row of its own, selected by its element")
    func listRows() {
        var selection: Int? = 1
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let drawn = render(
            List(selection: binding) { ForEach(0..<2, id: \.self) { i in Text("a\(i)"); Text("b\(i)") } },
            height: 8)
        let rows = drawn.filter { $0.contains("a0") || $0.contains("b0") || $0.contains("a1") || $0.contains("b1") }
        #expect(rows.count == 4, "\(drawn)")
        // Four rows, not two rows of two lines: a section reads them as its
        // list does.
        let section = Section { ForEach(0..<2, id: \.self) { i in Text("a\(i)"); Text("b\(i)") } }
        let extracted: SectionContentRows<Int> = section.extractSectionContentRows(
            context: makeRenderContext(width: 30, height: 8))
        #expect(extracted.rows.map(\.id) == [0, 0, 1, 1])
    }
}
