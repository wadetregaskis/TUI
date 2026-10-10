//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListMultiViewRowEditingTests.swift
//
//  A `ForEach` whose rows are several views each draws several list rows per
//  element (decisions B15), and its `.onDelete` still addresses ELEMENTS: a
//  Delete on any of an element's rows removes that element, every one of its
//  rows with it, as SwiftUI's does (measured on macOS 15.8,
//  `D1S/probe2/listdel`: the second view of an element selected, `delete:`
//  hands `.onDelete` that element's offset). The list refused both gestures
//  over such a loop before, rather than hand one row's place to the wrong
//  element.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport

/// What the loop's actions were handed.
@MainActor
private final class Edits {
    var deleted: [IndexSet] = []
    var moved: [(IndexSet, Int)] = []
}

@MainActor
@Suite("Editing a list whose rows are several views each")
struct ListMultiViewRowEditingTests {

    private static let items = ["a", "b", "c"]

    /// Each element's two rows.
    @ViewBuilder
    private static func pair(_ item: String) -> some View {
        Text("\(item) one")
        Text("\(item) two")
    }

    /// Each element's row, and a detail row for `b` only.
    @ViewBuilder
    private static func varying(_ item: String) -> some View {
        Text(item)
        if item == "b" { Text("detail") }
    }

    private func list(_ edits: Edits, @ViewBuilder _ content: () -> some View) -> some View {
        List(selection: .constant(String?.none)) { content() }.frame(height: 12)
    }

    @Test("Delete on either of an element's two rows deletes that element")
    func deleteFromAPair() {
        let fixture = ListSectionEditingFixture()
        let edits = Edits()
        let view = list(edits) {
            ForEach(Self.items, id: \.self) { Self.pair($0) }
                .onDelete { edits.deleted.append($0) }
        }
        fixture.render(view)
        #expect(fixture.pressDelete(onRow: 1, named: "a"))
        #expect(fixture.pressDelete(onRow: 4, named: "c"))
        #expect(edits.deleted == [IndexSet(integer: 0), IndexSet(integer: 2)], "\(edits.deleted)")
    }

    @Test("Delete on a row of a loop whose rows vary deletes the element it draws")
    func deleteFromVaryingRows() {
        let fixture = ListSectionEditingFixture()
        let edits = Edits()
        let view = list(edits) {
            ForEach(Self.items, id: \.self) { Self.varying($0) }
                .onDelete { edits.deleted.append($0) }
        }
        fixture.render(view)
        #expect(fixture.pressDelete(onRow: 2, named: "b"))
        #expect(fixture.pressDelete(onRow: 3, named: "c"))
        #expect(edits.deleted == [IndexSet(integer: 1), IndexSet(integer: 2)], "\(edits.deleted)")
    }

    @Test("In a Section, Delete on any of an element's rows deletes that element, for both row shapes")
    func deleteInASection() {
        let fixture = ListSectionEditingFixture()
        let edits = Edits()
        fixture.render(
            list(edits) {
                Section("Pairs") {
                    ForEach(Self.items, id: \.self) { Self.pair($0) }
                        .onDelete { edits.deleted.append($0) }
                }
            })
        // Row 0 is the header.
        #expect(fixture.pressDelete(onRow: 4, named: "b"))
        let varyingFixture = ListSectionEditingFixture()
        varyingFixture.render(
            list(edits) {
                Section("Varying") {
                    ForEach(Self.items, id: \.self) { Self.varying($0) }
                        .onDelete { edits.deleted.append($0) }
                }
            })
        #expect(varyingFixture.pressDelete(onRow: 3, named: "b"))
        #expect(edits.deleted == [IndexSet(integer: 1), IndexSet(integer: 1)], "\(edits.deleted)")
    }

    // MARK: - Moving

    /// The moves `.onMove` was handed, as `(source offsets, destination)`.
    private func moves(_ edits: Edits) -> [String] {
        edits.moved.map { "\(Array($0.0)) -> \($0.1)" }
    }

    /// Ctrl-R on `row`, Up `steps` times, Return.
    private func pickUpAndMoveUp(_ fixture: ListSectionEditingFixture, row: Int, by steps: Int) throws {
        let handler = try #require(fixture.handler)
        handler.focusedIndex = row
        #expect(handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)))
        for _ in 0..<steps { _ = handler.handleKeyEvent(KeyEvent(key: .up)) }
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
    }

    @Test("Ctrl-R on either row of a pair picks the element up, and it lands only between elements")
    func pickUpAPair() throws {
        let fixture = ListSectionEditingFixture()
        let edits = Edits()
        let view = list(edits) {
            ForEach(Self.items, id: \.self) { Self.pair($0) }
                .onMove { edits.moved.append(($0, $1)) }
        }
        fixture.render(view)
        // The second row of "a", one step down: past the whole of "b".
        #expect(fixture.pickUpMoveAndPlace(row: 1, named: "a", by: 1))
        fixture.render(view)
        // The first row of "c", one step up: before the whole of "b".
        try pickUpAndMoveUp(fixture, row: 4, by: 1)
        #expect(moves(edits) == ["[0] -> 2", "[2] -> 1"], "\(moves(edits))")
    }

    @Test("Ctrl-Down and Ctrl-Up move a focused element of several rows past whole elements")
    func nudgeAPair() throws {
        let fixture = ListSectionEditingFixture()
        let edits = Edits()
        let view = list(edits) {
            ForEach(Self.items, id: \.self) { Self.pair($0) }
                .onMove { edits.moved.append(($0, $1)) }
        }
        fixture.render(view)
        let handler = try #require(fixture.handler)
        handler.focusedIndex = 3
        #expect(handler.handleKeyEvent(KeyEvent(key: .down, ctrl: true)))
        handler.focusedIndex = 2
        #expect(handler.handleKeyEvent(KeyEvent(key: .up, ctrl: true)))
        #expect(moves(edits) == ["[1] -> 3", "[1] -> 0"], "\(moves(edits))")
    }

    @Test("A loop whose rows vary moves its elements whole, in a Section too")
    func moveVaryingRows() throws {
        let edits = Edits()
        let fixture = ListSectionEditingFixture()
        fixture.render(
            list(edits) {
                ForEach(Self.items, id: \.self) { Self.varying($0) }
                    .onMove { edits.moved.append(($0, $1)) }
            })
        // "c", one step up: before the whole of "b" (its row and its detail).
        try pickUpAndMoveUp(fixture, row: 3, by: 1)
        let sectioned = ListSectionEditingFixture()
        let sectionView = list(edits) {
            Section("Varying") {
                ForEach(Self.items, id: \.self) { Self.varying($0) }
                    .onMove { edits.moved.append(($0, $1)) }
            }
        }
        sectioned.render(sectionView)
        // The detail row of "b" (row 3 after the header), one step down: after "c".
        #expect(sectioned.pickUpMoveAndPlace(row: 3, named: "b", by: 1))
        #expect(moves(edits) == ["[2] -> 1", "[1] -> 3"], "\(moves(edits))")
    }
}
