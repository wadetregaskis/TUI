//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeMembersRowIDsTests.swift
//
//  A view of the app's own whose `body` is several views is taken apart into
//  them (decisions D1S, B-D1S-6), and a container that places its loops'
//  rows by position (`FlattenedRowIDs`) counts every such view as a provider
//  it cannot see into. Two of them around a loop — a heading above a list's
//  rows and another below — left the loop between them unplaced, so under a
//  `String` selection every row of it was unselectable and under an `Int` one
//  each answered its place in the list rather than its element.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A heading: two views, no loop.
private struct Heading: View {
    var body: some View {
        Text("x").bold()
        Divider()
    }
}

/// What a layout was handed: each subview's implicit `String` tag.
@MainActor
private final class Seen {
    var tags: [String?] = []
}

private struct TagReading: Layout {
    let seen: Seen

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        seen.tags = subviews.map { $0.containerValues.tag(for: String.self) }
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

@MainActor
@Suite("A view of the app's own taken apart beside a loop leaves the loop its values")
struct CompositeMembersRowIDsTests {

    private static let fruits = ["apple", "banana"]

    /// Each row's selection value in a live `List` of `content`.
    private func ids<ID: Hashable & Sendable>(
        _: ID.Type, @ViewBuilder _ content: () -> some View
    ) -> [ID?] {
        let fixture = ListSectionEditingFixture()
        fixture.render(List(selection: .constant(ID?.none), content: content).frame(height: 14))
        guard let handler = fixture.handler(ID.self) else {
            Issue.record("the list took focus")
            return []
        }
        return (0..<handler.itemCount).map { handler.id(at: $0) }
    }

    @Test("A loop between two headings of the app's own is selected by its elements, under String ids")
    func stringSelection() {
        let drawn = ids(String.self) {
            Heading()
            ForEach(Self.fruits, id: \.self) { Text($0) }
            Heading()
        }
        #expect(drawn == [nil, nil, "apple", "banana", nil, nil], "\(drawn)")
    }

    @Test("And under Int ids, by its elements, the headings by their places")
    func intSelection() {
        let drawn = ids(Int.self) {
            Heading()
            ForEach([10, 20], id: \.self) { Text("\($0)") }
            Heading()
        }
        #expect(drawn == [0, 1, 10, 20, 4, 5], "\(drawn)")
    }

    @Test("In a Section, the loop's rows keep their elements' values")
    func inASection() {
        let section = Section {
            Heading()
            ForEach(Self.fruits, id: \.self) { Text($0) }
            Heading()
        }
        let extracted: SectionContentRows<String> = section.extractSectionContentRows(
            context: makeRenderContext(width: 30, height: 12))
        #expect(extracted.rows.map(\.id) == [nil, nil, "apple", "banana", nil, nil])
    }

    @Test("A Layout and Group(subviews:) read the loop's rows' implicit tags")
    func implicitTags() {
        let seen = Seen()
        _ = renderToBuffer(
            TagReading(seen: seen) {
                Heading()
                ForEach(Self.fruits, id: \.self) { Text($0) }
                Heading()
            },
            context: makeRenderContext(width: 20, height: 6))
        #expect(seen.tags == [nil, nil, "apple", "banana", nil, nil], "\(seen.tags)")

        var tags: [String?] = []
        _ = renderToBuffer(
            Group(
                subviews: Group {
                    Heading()
                    ForEach(Self.fruits, id: \.self) { Text($0) }
                    Heading()
                }
            ) { subviews -> EmptyView in
                tags = subviews.map { $0.containerValues.tag(for: String.self) }
                return EmptyView()
            },
            context: makeRenderContext(width: 20, height: 6))
        #expect(tags == [nil, nil, "apple", "banana", nil, nil], "\(tags)")
    }
}
