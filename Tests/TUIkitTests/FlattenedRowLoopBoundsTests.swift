//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FlattenedRowLoopBoundsTests.swift
//
//  A loop whose rows make a number of views only each row knows — `Text(n); if
//  n == 2 { Text("two") }` — is placed on its container's keyed children by
//  its elements' keys (decisions B15). A key names a row only up to its
//  spelling, so a second loop over ids spelled the same met the first: its
//  first row carried the key of the first loop's last element, and was taken
//  as that element's. The second loop then came up short, the placement
//  failed, and every looped row in the container lost its selection value —
//  numbered by position under an `Int` selection, unselectable under a
//  `String` one. A loop placed by its keys now stops at its own loop's end.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("A loop placed by its keys stops at its own loop's end")
struct FlattenedRowLoopBoundsTests {

    /// Each row's selection value in a live `List` of `content`.
    private func ids<ID: Hashable & Sendable>(
        _: ID.Type, @ViewBuilder _ content: () -> some View
    ) -> [ID?] {
        let fixture = ListSectionEditingFixture()
        fixture.render(List(selection: .constant(ID?.none), content: content).frame(height: 12))
        guard let handler = fixture.handler(ID.self) else {
            Issue.record("the list took focus")
            return []
        }
        return (0..<handler.itemCount).map { handler.id(at: $0) }
    }

    @Test("Two loops over overlapping Int ids, the first with rows that vary, each keep their elements' values")
    func overlappingIntLoops() {
        let drawn = ids(Int.self) {
            ForEach([1, 2, 3], id: \.self) { n in
                Text("\(n)")
                if n == 2 { Text("two") }
            }
            ForEach([3, 4], id: \.self) { Text("x\($0)") }
        }
        #expect(drawn == [1, 2, 2, 3, 3, 4], "\(drawn)")
    }

    @Test("The same under a String selection, where an unplaced row cannot be selected at all")
    func overlappingStringLoops() {
        let drawn = ids(String.self) {
            ForEach(["a", "b", "c"], id: \.self) { name in
                Text(name)
                if name == "b" { Text("detail") }
            }
            ForEach(["c", "d"], id: \.self) { Text("x\($0)") }
        }
        #expect(drawn == ["a", "b", "b", "c", "c", "d"], "\(drawn)")
    }

    @Test("Two such loops in one Group beside a hand-written row keep their elements' values")
    func overlappingLoopsInOneGroup() {
        let drawn = ids(Int.self) {
            Text("all").tag(99)
            Group {
                ForEach([1, 2, 3], id: \.self) { n in
                    Text("\(n)")
                    if n == 2 { Text("two") }
                }
                ForEach([3, 4], id: \.self) { Text("x\($0)") }
            }
        }
        #expect(drawn == [99, 1, 2, 2, 3, 3, 4], "\(drawn)")
    }

    // The loop in the middle is counted, and a run that cannot be counted
    // comes after it — a third loop placed by its keys, or a view of the app's
    // own holding a loop of its own — so neither end of the Group's runs is a
    // counted loop to place first. The first loop must still stop where the
    // counted one starts.

    @Test("Between a loop placed by its keys and another, a counted loop keeps its rows, under Int ids")
    func countedLoopBetweenTwoPlacedByKeys() {
        let drawn = ids(Int.self) {
            Text("All").tag(99)
            Group {
                ForEach([1, 2, 3], id: \.self) { n in
                    Text("\(n)")
                    if n == 2 { Text("two") }
                }
                ForEach([3, 4], id: \.self) { Text("x\($0)") }
                ForEach([5, 6], id: \.self) { n in
                    Text("\(n)")
                    if n == 5 { Text("five") }
                }
            }
        }
        #expect(drawn == [99, 1, 2, 2, 3, 3, 4, 5, 5, 6], "\(drawn)")
    }

    @Test("And under String ids, where an unplaced row cannot be selected at all")
    func countedLoopBetweenTwoPlacedByKeysStrings() {
        let drawn = ids(String.self) {
            Text("All").tag("all")
            Group {
                ForEach(["a", "b", "c"], id: \.self) { name in
                    Text(name)
                    if name == "b" { Text("detail") }
                }
                ForEach(["c", "d"], id: \.self) { Text("x\($0)") }
                ForEach(["e", "f"], id: \.self) { name in
                    Text(name)
                    if name == "e" { Text("detail") }
                }
            }
        }
        #expect(drawn == ["all", "a", "b", "b", "c", "c", "d", "e", "e", "f"], "\(drawn)")
    }

    @Test("And with a view of the app's own holding a loop after the counted loop")
    func countedLoopBeforeAViewHoldingALoop() {
        let drawn = ids(String.self) {
            Text("All").tag("all")
            Group {
                ForEach(["a", "b", "c"], id: \.self) { name in
                    Text(name)
                    if name == "b" { Text("detail") }
                }
                ForEach(["c", "d"], id: \.self) { Text("x\($0)") }
                MoreRows(names: ["e"])
            }
        }
        // The view's own loop keeps the hand-written rule (decisions D1S,
        // B-D1S-6): no tag, so no `String` value.
        #expect(drawn == ["all", "a", "b", "b", "c", "c", "d", nil], "\(drawn)")
    }

    @Test("A placement that fits is found when the counted loops after a loop placed by its keys share its spellings")
    func countedLoopsSpelledAlike() {
        // Placed as far as it reaches, the first loop took every "3"; stopped
        // at the last place the next loop alone fits, it would leave no room
        // for the loop after that. The only placement that fits gives each
        // of the three one "3".
        let drawn = ids(Int.self) {
            Text("All").tag(99)
            Group {
                ForEach([1, 3], id: \.self) { n in
                    Text("\(n)")
                    if n == 1 { Text("one") }
                }
                ForEach([3], id: \.self) { Text("x\($0)") }
                ForEach([3], id: \.self) { Text("y\($0)") }
                ForEach([5, 6], id: \.self) { n in
                    Text("\(n)")
                    if n == 5 { Text("five") }
                }
            }
        }
        #expect(drawn == [99, 1, 1, 3, 3, 3, 5, 5, 6], "\(drawn)")
    }
}

/// A view whose body is a loop of its own.
private struct MoreRows: View {
    let names: [String]
    var body: some View { ForEach(names, id: \.self) { Text($0) } }
}
