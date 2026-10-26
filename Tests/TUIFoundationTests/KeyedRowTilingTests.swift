//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyedRowTilingTests.swift
//
//  `KeyedRowTiling` places one slot's runs on its keyed children: a counted
//  loop on exactly its rows, a loop placed by its keys on a run of its
//  elements' keys, an outline on a run of outline rows, and a provider the walk
//  cannot see into on whatever is left. It finds a tiling whenever one exists,
//  however the runs that can take more or fewer rows sit among those that
//  cannot.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@Suite("A slot's keyed children are tiled by the runs that made them")
struct KeyedRowTilingTests {

    private func spans(_ keys: [String], _ runs: [KeyedRowTiling.Run], outline: Set<Int> = []) -> [Range<Int>?]? {
        KeyedRowTiling(keys: keys, isOutlineRow: { outline.contains($0) }).spans(of: runs)
    }

    @Test("A loop placed by its keys stops where a counted loop after it fits, with another such loop after that")
    func boundedBetweenLoops() {
        let found = spans(
            ["1", "2", "2", "3", "3", "4", "5", "5", "6"],
            [
                .byKeys(elementKeys: ["1", "2", "3"]),
                .counted(rows: 2, firstKey: "3", lastKey: "4"),
                .byKeys(elementKeys: ["5", "6"]),
            ])
        #expect(found == [0..<4, 4..<6, 6..<9])
    }

    @Test("Before a provider the walk cannot see into, the same; it owns what is left")
    func boundedBeforeAnOpaqueRun() {
        let found = spans(
            ["a", "b", "b", "c", "c", "d", "x", "e"],
            [
                .byKeys(elementKeys: ["a", "b", "c"]),
                .counted(rows: 2, firstKey: "c", lastKey: "d"),
                .opaque,
                .byKeys(elementKeys: ["e"]),
            ])
        #expect(found == [0..<4, 4..<6, nil, 7..<8])
    }

    @Test("Runs between two providers the walk cannot see into are not placed")
    func betweenTwoOpaqueRuns() {
        let found = spans(
            ["a", "b", "c"],
            [
                .counted(rows: 1, firstKey: "a", lastKey: "a"),
                .opaque,
                .counted(rows: 1, firstKey: "b", lastKey: "b"),
                .opaque,
                .counted(rows: 1, firstKey: "c", lastKey: "c"),
            ])
        #expect(found == [0..<1, nil, nil, nil, 2..<3])
    }

    /// Two loops placed by their keys, the first ending on a key the second's
    /// rows start with: either can have made the rows of that key, and the
    /// earlier takes them — before a provider the walk cannot see into, with
    /// none, and after one, where the placement this search replaced gave
    /// them to the later loop (decisions D1S, B-D1S-5).
    @Test("Of two loops tied on a key, the earlier takes its rows, on either side of a provider")
    func tiedLoopsGiveTheRowsToTheEarlier() {
        let tied: [KeyedRowTiling.Run] = [.byKeys(elementKeys: ["1", "2"]), .byKeys(elementKeys: ["2", "3"])]
        #expect(spans(["1", "1", "2", "2", "3", "3"], tied) == [0..<4, 4..<6])
        #expect(spans(["1", "1", "2", "2", "3", "3", "z"], tied + [.opaque]) == [0..<4, 4..<6, nil])
        #expect(spans(["z", "1", "1", "2", "2", "3", "3"], [.opaque] + tied) == [nil, 1..<5, 5..<7])
    }

    @Test("Where no tiling fits, nothing is placed")
    func noTiling() {
        #expect(spans(["a", "c"], [.counted(rows: 2, firstKey: "a", lastKey: "b")]) == nil)
        #expect(spans(["a", "b"], [.byKeys(elementKeys: ["a"])]) == nil)
    }

    @Test("A loop whose elements' keys repeat is read from each start as its rows are assigned")
    func repeatedKeys() {
        let keys = ["a", "b", "a", "a"]
        let tiling = KeyedRowTiling(keys: keys, isOutlineRow: { _ in false })
        let loop = ["a", "b", "a"]
        let found = tiling.spans(of: [.byKeys(elementKeys: loop), .counted(rows: 1, firstKey: "a", lastKey: "a")])
        #expect(found == [0..<3, 3..<4])
        #expect(tiling.elements(ofLoopKeyed: loop, in: 0..<3) == [0, 1, 2])
    }

    @Test("An outline takes the outline rows in front of the loop after it")
    func outlineRows() {
        let found = spans(
            ["n1", "n2", "z"], [.outline, .counted(rows: 1, firstKey: "z", lastKey: "z")], outline: [0, 1])
        #expect(found == [0..<2, 2..<3])
    }
}
