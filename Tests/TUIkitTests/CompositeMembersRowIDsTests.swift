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

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitView

/// A heading: two views, no loop.
private struct Heading: View {
    var body: some View {
        Text("x").bold()
        Divider()
    }
}

/// A view whose body is a loop of its own.
private struct Extras: View {
    let names: [String]
    var body: some View { ForEach(names, id: \.self) { Text($0) } }
}

/// A section of the app's own holding a loop: to a `List`, one section, which
/// hands the list no keyed row of the list's own.
private struct FruitSection: View {
    var body: some View {
        Section("F") { ForEach(["apple", "banana"], id: \.self) { Text($0) } }
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

    @Test("In one slot with the loop — a Group beside a hand-written row — the headings still leave it its values")
    func inOneSlotWithTheLoop() {
        let drawn = ids(String.self) {
            Text("All").tag("all")
            Group {
                Heading()
                ForEach(Self.fruits, id: \.self) { Text($0) }
                Heading()
            }
        }
        #expect(drawn == ["all", nil, nil, "apple", "banana", nil, nil], "\(drawn)")
    }

    @Test("A loop between two views of the app's own that hold loops of their own keeps its values")
    func besideViewsHoldingLoops() {
        let drawn = ids(String.self) {
            Extras(names: ["e1", "e2"])
            ForEach(Self.fruits, id: \.self) { Text($0) }
            Extras(names: ["e3"])
        }
        // The views' own loops keep the hand-written rule (decisions D1S,
        // B-D1S-6): no tag, so no `String` value. The loop between them is
        // placed.
        #expect(drawn == [nil, nil, "apple", "banana", nil], "\(drawn)")
    }

    @Test("In one slot with the loop, two sections of the app's own around it leave it its values")
    func sectionsOfTheAppsOwnInOneSlot() {
        let drawn = ids(String.self) {
            Text("All").tag("all")
            Group {
                FruitSection()
                ForEach(["x", "y"], id: \.self) { Text($0) }
                FruitSection()
            }
        }
        // Each section's header, then its rows by their own ids; the loop
        // between them by its elements.
        #expect(drawn == ["all", nil, "apple", "banana", "x", "y", nil, "apple", "banana"], "\(drawn)")
    }
}
