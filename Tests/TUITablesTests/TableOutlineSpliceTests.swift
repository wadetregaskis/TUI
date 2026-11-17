//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlineSpliceTests.swift
//
//  A `Table(_:children:)`'s kept outline, made again for a change of its open
//  branches by splicing the changed branches' rows in or out: twinned with
//  the tree flattened whole after every step of seeded random scripts of
//  keys, clicks and the app's writes, and seen to cost the rows it changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITables
@testable import TUIView

private struct Node: Identifiable {
    let id: Int
    var children: [Self]?
}

/// SplitMix64: the same numbers from a seed on every platform, so a failing
/// seed fails again.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// The app's set, as `Table(_:children:expansion:)` is handed it.
@MainActor
private final class Model {
    var open: Set<Int> = []
    var binding: Binding<Set<Int>> { Binding(get: { self.open }, set: { self.open = $0 }) }
}

@MainActor
@Suite("A kept outline spliced for a change of its open branches")
struct TableOutlineSpliceTests {
    /// A random forest of about `count` rows, five deep at most: branches,
    /// some with no rows, and leaves. With `sharing`, a few ids repeat.
    private static func forest(count: Int, sharing: Bool, using generator: inout Seeded) -> [Node] {
        var next = 0
        func nodes(depth: Int, budget: Int) -> [Node] {
            var made: [Node] = []
            let width = Int.random(in: 1...max(1, min(budget, 6)), using: &generator)
            for _ in 0..<width where next < count {
                var id = next
                next += 1
                if sharing, id > 10, Int.random(in: 0..<25, using: &generator) == 0 { id = Int.random(in: 0..<id, using: &generator) }
                if depth < 5, Int.random(in: 0..<3, using: &generator) == 0 {
                    made.append(Node(id: id, children: nodes(depth: depth + 1, budget: budget / 2)))
                } else {
                    made.append(Node(id: id))
                }
            }
            return made
        }
        var roots: [Node] = []
        while next < count { roots += nodes(depth: 0, budget: count) }
        return roots
    }

    /// The tree flattened whole with the branches `reading` opens: what the
    /// kept outline must be, row for row.
    private static func flattened(
        _ roots: _TableOutlineRoots<Node>, expansion: OutlineExpansion<Node.ID>
    ) -> _TableOutline<Node> {
        let branches = roots.values.indices.filter { roots.isBranch(roots.values[$0]) }
        return _TableOutline(
            _TableOutline.flattening(roots: roots, branches: branches, expansion: expansion.read()),
            expansion: expansion)
    }

    /// Whether `kept` and `whole` list the same rows, placed and linked
    /// alike, and answer alike by id for every id the tree has and one more.
    private static func expectTwins(
        _ kept: _TableOutline<Node>, _ whole: _TableOutline<Node>, ids: Range<Int>, step: String
    ) {
        #expect(kept.values.map(\.id) == whole.values.map(\.id), "\(step): rows")
        guard kept.rows.count == whole.rows.count else { return }
        for index in kept.rows.indices {
            let (mine, theirs) = (kept.rows[index], whole.rows[index])
            let same =
                mine.placement.depth == theirs.placement.depth
                && mine.placement.disclosure == theirs.placement.disclosure && mine.parent == theirs.parent
                && (mine.branch < 0) == (theirs.branch < 0)
                && (mine.branch < 0 || kept.branchNodes[mine.branch].value.id == whole.branchNodes[theirs.branch].value.id)
            #expect(same, "\(step): row \(index), id \(kept.values[index].id)")
            if !same { return }
        }
        for id in ids.lowerBound..<(ids.upperBound + 1) {
            #expect(kept.prefix(for: id) == whole.prefix(for: id), "\(step): prefix of \(id)")
            #expect(kept.triangleColumns(for: id) == whole.triangleColumns(for: id), "\(step): triangle of \(id)")
            #expect(kept.parentRowID(of: AnyHashable(id)) == whole.parentRowID(of: AnyHashable(id)), "\(step): parent of \(id)")
        }
    }

    /// Plays `steps` random steps against a cache, the expansion kept by
    /// the table (`model` nil) or by the app, twinning the kept outline with
    /// the tree flattened whole after each.
    private func play(seed: UInt64, count: Int, steps: Int, sharing: Bool, app: Bool) {
        var generator = Seeded(state: seed)
        let model = Model()
        let box = StateBox<Set<Int>>([])
        let forest = Self.forest(count: count, sharing: sharing, using: &generator)
        let roots = _TableOutlineRoots(forest, children: \Node.children, expansion: app ? model.binding : nil)
        let expansion = app ? OutlineExpansion<Node.ID>(model.binding) : OutlineExpansion<Node.ID>(box)
        let cache = _TableOutlineCache<Node>()
        /// Writes the app's set or the table's box, as a write from code.
        func write(_ change: (inout Set<Int>) -> Void) {
            if app {
                change(&model.open)
            } else {
                change(&box.value)
            }
        }
        var kept = cache.outline(of: roots, expansion: expansion)
        for step in 0..<steps {
            let shown = kept.values
            // A key or click on a shown row (two, at times, before the next
            // frame), or the app's write of a few ids or of a new set.
            switch Int.random(in: 0..<10, using: &generator) {
            case 0..<5:
                for _ in 0..<(Int.random(in: 0..<4, using: &generator) == 0 ? 2 : 1) {
                    guard let row = shown.randomElement(using: &generator) else { break }
                    let target: Bool? = [nil, true, false].randomElement(using: &generator)!
                    kept.setExpanded(
                        AnyHashable(row.id), to: target, includingDescendants: Bool.random(using: &generator))
                }
            case 5..<9:
                let ids = (0..<Int.random(in: 1...3, using: &generator)).map { _ in Int.random(in: -1...count, using: &generator) }
                let opens = Bool.random(using: &generator)
                write { set in if opens { set.formUnion(ids) } else { set.subtract(ids) } }
            default:
                let ids = (0..<count).filter { _ in Int.random(in: 0..<3, using: &generator) == 0 }
                write { $0 = Set(ids) }
            }
            kept = cache.outline(of: roots, expansion: expansion)
            Self.expectTwins(kept, Self.flattened(roots, expansion: expansion), ids: -1..<count, step: "seed \(seed) step \(step)")
        }
    }

    @Test(
        "Random keys, clicks and writes leave the kept outline what flattening the tree whole makes",
        arguments: [UInt64(1), 2, 3, 4, 5, 6])
    func twinOfTheWholeFlattening(seed: UInt64) {
        play(seed: seed, count: 120, steps: 150, sharing: false, app: seed.isMultiple(of: 2))
    }

    @Test("The same where rows share ids, which the outline makes again whole", arguments: [UInt64(7), 8])
    func twinWithSharedIDs(seed: UInt64) {
        play(seed: seed, count: 120, steps: 80, sharing: true, app: seed.isMultiple(of: 2))
    }

    @Test("Opening or closing one branch lists that branch's rows, not the outline's")
    func oneBranchListsItsRows() {
        let big = Node(id: 0, children: (1...1_000).map { Node(id: $0) })
        let small = Node(id: 2_000, children: [Node(id: 2_001), Node(id: 2_002, children: [Node(id: 2_003)])])
        let model = Model()
        model.open = [0, 2_002]
        let roots = _TableOutlineRoots([big, small], children: \Node.children, expansion: model.binding)
        let expansion = OutlineExpansion<Node.ID>(model.binding)
        let cache = _TableOutlineCache<Node>()
        let first = cache.outline(of: roots, expansion: expansion)
        #expect(cache.listed == 1_002, "the first outline lists every row it shows")
        #expect(first.setExpanded(AnyHashable(2_000), to: true, includingDescendants: false))
        let opened = cache.outline(of: roots, expansion: expansion)
        #expect(cache.listed == 1_002 + 3, "the small branch's three rows, its own open one's among them")
        #expect(opened.values.suffix(4).map(\.id) == [2_000, 2_001, 2_002, 2_003])
        #expect(opened.setExpanded(AnyHashable(2_000), to: false, includingDescendants: false))
        _ = cache.outline(of: roots, expansion: expansion)
        #expect(cache.listed == 1_002 + 3 + 3)
        model.open.insert(5)
        #expect(cache.outline(of: roots, expansion: expansion).values.count == 1_002, "a leaf's id opens nothing")
        #expect(cache.listed == 1_002 + 6, "and lists nothing")
    }
}
