//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineListWindowTests.swift
//
//  A `List(_:children:)` builds the rows it draws, not every open row
//  (finding G1): the work a frame does must not grow with the open part of the
//  tree, and the windowed list must draw, move, open, close, select and scroll
//  exactly as the eager one did. The eager twin is the same outline with its
//  windowing turned off (`OutlineGroup.windowsListRows`), its rows extracted
//  all at once, as a `Section` holding an outline still extracts them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITesting

/// Counts the reads of every node's id: the flattening walk reads one a node,
/// so a pass that walks the tree reads as many ids as there are open rows.
@MainActor
private final class IDReads {
    var count = 0
}

/// A node: an id, and its children stored in it, as an app's tree of values
/// is. The id is read through a counter (``IDReads``).
private struct Item: Identifiable {
    let raw: Int
    let reads: IDReads
    var children: [Self]?

    var id: Int {
        MainActor.assumeIsolated { reads.count += 1 }
        return raw
    }
}

/// One root over `count` rows: a group every 100, in each a group every 10,
/// the rest leaves. Opened all the way it shows `count + 1` rows, three deep.
@MainActor
private func tree(count: Int, reads: IDReads = IDReads()) -> [Item] {
    var groups: [Item] = []
    for start in stride(from: 0, to: count, by: 100) {
        let end = min(start + 100, count)
        var members: [Item] = []
        var index = start + 1
        while index < end {
            if index.isMultiple(of: 10) {
                let leaves = ((index + 1)..<min(index + 10, end)).map { Item(raw: $0, reads: reads) }
                members.append(Item(raw: index, reads: reads, children: leaves))
                index += 10
            } else {
                members.append(Item(raw: index, reads: reads))
                index += 1
            }
        }
        groups.append(Item(raw: start, reads: reads, children: members))
    }
    return [Item(raw: -1, reads: reads, children: groups)]
}

/// Holds the `ScrollViewProxy` a reader hands its content.
@MainActor
private final class ProxyBox {
    var proxy: ScrollViewProxy?
}

/// The selection both twins write.
@MainActor
private final class Chosen {
    var one: Int?
}

/// A model whose tree the app replaces, as an edit does.
@MainActor
@Observable
private final class Model {
    var tree: [Item]
    init(tree: [Item]) { self.tree = tree }
}

@MainActor
@Suite("An outline in a List builds only the rows it draws")
struct OutlineListWindowTests {
    /// A list of `rows` under one root, the whole of a small terminal.
    private func windowed(_ rows: [Item], chosen: Chosen, width: Int = 40, height: Int = 12) -> TestApp {
        TestApp(width: width, height: height) {
            List(rows, children: \.children, selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                Text(verbatim: "n\($0.raw)")
            }
        }
    }

    /// The same list with the outline's windowing off, every row extracted at
    /// once: the drawing the windowed list must match.
    private func eager(_ rows: [Item], chosen: Chosen, width: Int = 40, height: Int = 12) -> TestApp {
        TestApp(width: width, height: height) {
            List(selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                Self.unwindowed(OutlineGroup(rows, children: \.children) { Text(verbatim: "n\($0.raw)") })
            }
        }
    }

    private static func unwindowed<D, I, L>(_ outline: OutlineGroup<D, I, L>) -> OutlineGroup<D, I, L> {
        var outline = outline
        outline.windowsListRows = false
        return outline
    }

    /// The row boxes the list has made so far.
    private func listed(_ app: TestApp) -> Int { app.headless.renderCache.rowWork.listed }

    /// Opens the whole tree: Option-Right on the root, the first row.
    private func openAll(_ app: TestApp) {
        _ = app.screen
        if app.focusedID == nil { app.press(.tab) }
        app.press(.right, modifiers: .option)
    }

    // MARK: - Building

    /// Seen failing without the windowing: the eager rows made a box for every
    /// open row each pass, 1,001 and 10,001 of them here.
    @Test("the rows a frame lists do not grow with the open rows")
    func listedIndependentOfOpenRows() {
        var listedAt: [Int: Int] = [:]
        for count in [1_000, 10_000] {
            let app = windowed(tree(count: count), chosen: Chosen())
            openAll(app)
            #expect(app.screen.contains("n1"), "the tree opened")
            let before = listed(app)
            app.scroll(.down, by: 5)
            app.scroll(.down, by: 5)
            app.press(.pageDown, times: 2)
            app.press(.down, times: 3)
            app.press(.left)
            app.press(.right)
            listedAt[count] = listed(app) - before
        }
        #expect(listedAt[1_000] == listedAt[10_000], "the same steps list the same rows at 1,000 and 10,000: \(listedAt)")
        #expect((listedAt[1_000] ?? .max) < 400, "a screenful or so a step, not the tree: \(listedAt)")
    }

    /// Seen failing without the kept nodes: every pass walked the open tree,
    /// reading 1,002 ids a frame here.
    @Test("a scroll or a cursor move walks no tree")
    func scrollWalksNoTree() {
        let reads = IDReads()
        let app = windowed(tree(count: 1_000, reads: reads), chosen: Chosen())
        openAll(app)
        #expect(app.screen.contains("n1"))
        reads.count = 0
        app.scroll(.down, by: 5)
        app.press(.down, times: 3)
        app.press(.pageDown)
        #expect(reads.count < 100, "ids read by three steps over 1,001 open rows: \(reads.count)")
    }

    // MARK: - Drawing and keys, against the eager twin

    /// Plays `steps` on both twins, comparing their screens and selections
    /// after each.
    private func twins(
        _ steps: [(String, (TestApp) -> Void)], count: Int = 2_000, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rows = tree(count: count)
        let (windowedChoice, eagerChoice) = (Chosen(), Chosen())
        let lists = [windowed(rows, chosen: windowedChoice), eager(rows, chosen: eagerChoice)]
        for app in lists { openAll(app) }
        #expect(lists[0].screen == lists[1].screen, "opened", sourceLocation: sourceLocation)
        for (name, step) in steps {
            for app in lists { step(app) }
            #expect(lists[0].screen == lists[1].screen, "after \(name)", sourceLocation: sourceLocation)
            #expect(windowedChoice.one == eagerChoice.one, "selection after \(name)", sourceLocation: sourceLocation)
        }
    }

    @Test("scrolled anywhere, the windowed list draws what the eager one does")
    func drawsAsEagerAtScrollPositions() {
        twins([
            ("a wheel step", { $0.scroll(.down, by: 1) }),
            ("seven more", { $0.scroll(.down, by: 7) }),
            ("three hundred more", { $0.scroll(.down, by: 300) }),
            ("back up forty", { $0.scroll(.up, by: 40) }),
            ("to the end", { $0.scroll(.down, by: 5_000) }),
        ])
    }

    @Test("Up, Down, Page Down, Home and End move the cursor as the eager list does")
    func movesAsEager() {
        twins([
            ("Down", { $0.press(.down, times: 3) }),
            ("Page Down", { $0.press(.pageDown, times: 4) }),
            ("Up", { $0.press(.up, times: 2) }),
            ("End", { $0.press(.end) }),
            ("Up from the end", { $0.press(.up) }),
            ("Home", { $0.press(.home) }),
        ])
    }

    @Test("Left closes and walks out, Right opens, as in the eager list, far down the tree")
    func disclosesAsEager() {
        twins([
            ("Page Down", { $0.press(.pageDown, times: 6) }),
            ("Left on a leaf walks to its group", { $0.press(.left) }),
            ("Left closes the group", { $0.press(.left) }),
            ("Down past it", { $0.press(.down, times: 2) }),
            ("Right opens what the cursor is on", { $0.press(.right) }),
            ("Option-Left folds a subtree", { $0.press(.left, modifiers: .option) }),
            ("Option-Right opens it again", { $0.press(.right, modifiers: .option) }),
            ("End, after the tree changed", { $0.press(.end) }),
        ])
    }

    @Test("Space selects and type select finds a row, as in the eager list")
    func selectsAsEager() {
        twins([
            ("Page Down", { $0.press(.pageDown, times: 3) }),
            ("Space selects", { $0.press(.space) }),
            ("type select", { $0.type("n17") }),
            ("Space again", { $0.press(.space) }),
            ("type select far down", { $0.type("n1500") }),
        ])
    }

    @Test("scrollTo reaches a row far below the window")
    func scrollToReachesARowNeverBuilt() {
        let rows = tree(count: 2_000)
        let box = ProxyBox()
        let app = TestApp(width: 40, height: 12) {
            ScrollViewReader { reader in
                // swiftlint:disable:next redundant_discardable_let
                let _ = box.proxy = reader
                List(rows, children: \.children) { Text(verbatim: "n\($0.raw)") }
            }
        }
        openAll(app)
        #expect(!app.screen.contains("n1503"))
        box.proxy?.scrollTo(1_503, anchor: .top)
        #expect(app.screen.contains("n1503"), "\(app.screen)")
    }

    // MARK: - The kept nodes follow the tree

    @Test("a tree replaced by an edit shows the edit")
    func replacedTreeShows() {
        let model = Model(tree: tree(count: 300))
        let app = TestApp(width: 40, height: 12) {
            List(model.tree, children: \.children) { Text(verbatim: "n\($0.raw)") }
        }
        openAll(app)
        #expect(app.screen.contains("n1"))
        model.tree[0].children?[0].children?[0] = Item(raw: 9_999, reads: IDReads())
        #expect(app.screen.contains("n9999"), "\(app.screen)")
    }
}
