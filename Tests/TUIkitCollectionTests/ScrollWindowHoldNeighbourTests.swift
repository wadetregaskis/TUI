//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollWindowHoldNeighbourTests.swift
//
//  The top-row hold's neighbours: read again when a row arrives or leaves
//  beside the top row, and the row before it judging whether the top row's
//  place is kept — the SCROLLANCHOR review's S3 and S4, fixed by lane
//  SCROLLB — and a move an `onMove` applies a frame late. Beside
//  `ScrollWindowHoldTests`, whose harness they use, for that file's length.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitLists

extension ScrollWindowHoldTests {

    /// The top row renamed a frame after a row arrived just after it. The
    /// arrival left the top row in place, so that frame read nothing beside it,
    /// and the row after it it remembered was a frame stale: the rename put the
    /// row two after it on top (the SCROLLANCHOR review, S3), and with rows
    /// inserted above as well moved the view k + 2.
    @Test(
        "A top row renamed a frame after a row arrived just after it keeps its place",
        arguments: StackPath.allCases, [0, 5])
    func renamedAfterAnArrivalBesideIt(path: StackPath, above: Int) {
        let scroller = Scroller(path)
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)",
            let index = scroller.items.firstIndex(where: { $0.id == top })
        else {
            Issue.record("precondition: a whole row at the top \(before)")
            return
        }
        scroller.items.insert(Row(id: 2_000), at: index + 1)
        #expect(scroller.frame().first == "row \(top)", "precondition: an arrival below the top row moves nothing")
        scroller.items[index] = Row(id: top + 3_000)
        if above > 0 { scroller.insert(1_000..<(1_000 + above)) }
        let after = scroller.frame()
        #expect(after.first == "row \(top + 3_000)", "before: \(before)\nafter:  \(after)")
    }

    /// The top row removed as one row or two arrive above it: the row after it
    /// takes its place either way. Judged by "the row after it still as far
    /// after the place", one row arriving left the row after it exactly there,
    /// and the row from above the screen took the top.
    @Test(
        "A top row removed as rows arrive above it gives its place to the row after it",
        arguments: StackPath.allCases, [1, 2])
    func removedTopRowAsRowsArrive(path: StackPath, above: Int) {
        let scroller = Scroller(path)
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)",
            let index = scroller.items.firstIndex(where: { $0.id == top })
        else {
            Issue.record("precondition: a whole row at the top \(before)")
            return
        }
        let next = scroller.items[index + 1].id
        scroller.items.remove(at: index)
        scroller.insert(1_000..<(1_000 + above))
        let after = scroller.frame()
        #expect(after.first == "row \(next)", "before: \(before)\nafter:  \(after)")
    }

    /// The top row and the row above it renamed in one update — a bulk edit
    /// of two selected rows. Asked of the row before it alone, the place was
    /// judged gone, and the row after it was put on top: the view moved a row
    /// (the review of d46184a69). The rows either side of the place still
    /// stand one apart, so it is the place, renamed.
    @Test("A top row renamed with the row above it in one update keeps its place", arguments: StackPath.allCases)
    func renamedWithTheRowAboveIt(path: StackPath) {
        let scroller = Scroller(path)
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)",
            let index = scroller.items.firstIndex(where: { $0.id == top }), index > 0
        else {
            Issue.record("precondition: a whole row at the top, with one above it \(before)")
            return
        }
        scroller.items[index - 1] = Row(id: scroller.items[index - 1].id + 3_000)
        scroller.items[index] = Row(id: top + 3_000)
        let after = scroller.frame()
        #expect(after.first == "row \(top + 3_000)", "before: \(before)\nafter:  \(after)")
    }

    @Test(
        "A List's or Table's top row renamed with the row above it in one update keeps its place",
        arguments: ListKind.allCases)
    func listRenamedWithTheRowAboveIt(kind: ListKind) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        guard let top = listedRows(before).first, let index = lister.items.firstIndex(where: { $0.id == top }),
            index > 0
        else {
            Issue.record("precondition: rows on screen, with one above \(before)")
            return
        }
        lister.items[index - 1] = Row(id: lister.items[index - 1].id + 3_000)
        lister.items[index] = Row(id: top + 3_000)
        let after = lister.frame()
        #expect(listedRows(after).first == top + 3_000, "before: \(before)\nafter:  \(after)")
    }

    /// The review's input: the cursor below the top row moved a row with the
    /// view, onto another row, where the next chord acted.
    @Test("A List's cursor stays on its row when the top row is renamed with the row above it")
    func listCursorThroughARenameWithTheRowAbove() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8, selectionMode: .single, canBeFocused: true)
        var ids = Array(0..<40)
        handler.itemIDs = ids
        func settle() {
            handler.settleScrollPosition(
                measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        }
        settle()
        handler.scrollOffset = 10
        handler.focusedIndex = 13
        settle()
        ids[9] = 3_009
        ids[10] = 3_010
        handler.itemIDs = ids
        settle()
        #expect(handler.scrollOffset == 10)
        #expect(handler.focusedIndex == 13)
    }

    @Test(
        "A List's or Table's top row renamed a frame after a row arrived just after it keeps its place",
        arguments: ListKind.allCases, [0, 5])
    func listRenamedAfterAnArrivalBesideIt(kind: ListKind, above: Int) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        guard let top = listedRows(before).first, let index = lister.items.firstIndex(where: { $0.id == top }) else {
            Issue.record("precondition: rows on screen \(before)")
            return
        }
        lister.items.insert(Row(id: 2_000), at: index + 1)
        #expect(listedRows(lister.frame()).first == top, "precondition: an arrival below the top row moves nothing")
        lister.items[index] = Row(id: top + 3_000)
        if above > 0 { lister.insert(1_000..<(1_000 + above)) }
        let after = lister.frame()
        #expect(listedRows(after).first == top + 3_000, "before: \(before)\nafter:  \(after)")
    }

    @Test(
        "A List's or Table's top row removed as rows arrive above it gives its place to the row after it",
        arguments: ListKind.allCases, [1, 2])
    func listRemovedTopRowAsRowsArrive(kind: ListKind, above: Int) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        guard let top = listedRows(before).first, let index = lister.items.firstIndex(where: { $0.id == top }) else {
            Issue.record("precondition: rows on screen \(before)")
            return
        }
        let next = lister.items[index + 1].id
        lister.items.remove(at: index)
        lister.insert(1_000..<(1_000 + above))
        let after = lister.frame()
        #expect(listedRows(after).first == next, "before: \(before)\nafter:  \(after)")
    }

    /// The cursor moves with the hold, so a hold two rows off moved it onto
    /// another row, where the next chord acted.
    @Test("A List's cursor stays on its row when the top row is renamed a frame after a row arrived beside it")
    func listCursorThroughARenameBesideAnArrival() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8, selectionMode: .single, canBeFocused: true)
        var ids = Array(0..<40)
        handler.itemIDs = ids
        func settle() {
            handler.settleScrollPosition(
                measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        }
        settle()
        handler.scrollOffset = 10
        handler.focusedIndex = 13
        settle()
        ids.insert(2_000, at: 11)
        handler.itemIDs = ids
        handler.itemCount = ids.count
        settle()
        #expect(handler.scrollOffset == 10, "precondition: an arrival below the top row moves nothing")
        ids[10] = 3_010
        handler.itemIDs = ids
        settle()
        #expect(handler.scrollOffset == 10)
        #expect(handler.id(at: handler.focusedIndex) == 12)
    }

    /// An `onMove` that applies the move later — `Task { await store.move(…) }`
    /// — draws the key's frame with the rows unmoved. The list waited one frame
    /// for its own move, so the moved rows a frame later were held: the row
    /// moved onto the top row's place went out of view, and the cursor landed
    /// on the old top row (the SCROLLANCHOR review, S4).
    @Test("A row an onMove moves a frame late onto the top row's place stays on screen, with the cursor on it")
    func listLateOwnMoveIsNotHeld() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8, selectionMode: .single, canBeFocused: true)
        var ids = Array(0..<40)
        handler.itemIDs = ids
        var pending: (source: IndexSet, destination: Int)?
        handler.onMove = { pending = ($0, $1) }
        func settle() {
            handler.settleScrollPosition(
                measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        }
        settle()
        handler.scrollOffset = 10
        handler.focusedIndex = 17
        settle()
        #expect(handler.nudgeFocusedRow(by: -handler.pageStep))
        #expect(handler.focusedIndex == 10, "precondition: moved onto the top row's place")
        settle()
        guard let move = pending else {
            Issue.record("precondition: a move asked for")
            return
        }
        ids.move(fromOffsets: move.source, toOffset: move.destination)
        handler.itemIDs = ids
        settle()
        #expect(handler.scrollOffset == 10)
        #expect(handler.id(at: handler.focusedIndex) == 17)
    }
}
