//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineSectionTests.swift
//
//  An outline inside a `Section` of a `List` opens and closes from the keys as
//  one that is the list's whole content does: the list asks the view its rows
//  came from to open a row, and for a section that was the `Section`, which
//  opens nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITesting

/// A node: an id, and its children stored in it, as an app's tree of values is.
private struct Node: Identifiable {
    let id: Int
    var children: [Self]?
}

/// One root over `count` rows: a group every 100, in each a group every 10,
/// the rest leaves. Opened all the way it shows `count + 1` rows, three deep.
private func tree(count: Int) -> [Node] {
    var groups: [Node] = []
    for start in stride(from: 0, to: count, by: 100) {
        let end = min(start + 100, count)
        var members: [Node] = []
        var index = start + 1
        while index < end {
            if index.isMultiple(of: 10) {
                members.append(Node(id: index, children: ((index + 1)..<min(index + 10, end)).map { Node(id: $0) }))
                index += 10
            } else {
                members.append(Node(id: index))
                index += 1
            }
        }
        groups.append(Node(id: start, children: members))
    }
    return [Node(id: -1, children: groups)]
}

/// The selection a list writes.
@MainActor
private final class Chosen {
    var one: Int?
}

@MainActor
@Suite("An outline inside a Section opens from the keys")
struct OutlineSectionTests {
    /// The tree in one `Section`, with nothing else in the list.
    private func inSection(_ rows: [Node], chosen: Chosen) -> TestApp {
        TestApp(width: 40, height: 12) {
            List(selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                Section {
                    OutlineGroup(rows, children: \.children) { Text(verbatim: "n\($0.id)") }
                }
            }
        }
    }

    /// The tree as the list's whole content: the list the section's must
    /// behave as.
    private func alone(_ rows: [Node], chosen: Chosen) -> TestApp {
        TestApp(width: 40, height: 12) {
            List(rows, children: \.children, selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                Text(verbatim: "n\($0.id)")
            }
        }
    }

    /// Plays `steps` on both lists, comparing their screens and selections
    /// after each, from the tree opened all the way by Option-Right on the
    /// root.
    private func twins(_ steps: [(String, (TestApp) -> Void)], sourceLocation: SourceLocation = #_sourceLocation) {
        let rows = tree(count: 600)
        let (sectionChoice, aloneChoice) = (Chosen(), Chosen())
        let lists = [inSection(rows, chosen: sectionChoice), alone(rows, chosen: aloneChoice)]
        for app in lists {
            _ = app.screen
            if app.focusedID == nil { app.press(.tab) }
            app.press(.right, modifiers: .option)
        }
        #expect(lists[0].screen.contains("n5"), "Option-Right opened the tree: \(lists[0].screen)")
        #expect(lists[0].screen == lists[1].screen, "opened", sourceLocation: sourceLocation)
        for (name, step) in steps {
            for app in lists { step(app) }
            #expect(lists[0].screen == lists[1].screen, "after \(name)", sourceLocation: sourceLocation)
            #expect(sectionChoice.one == aloneChoice.one, "selection after \(name)", sourceLocation: sourceLocation)
        }
    }

    /// Seen failing without the section's outline handed up: Option-Right
    /// opened nothing, and the list showed the closed root alone.
    @Test("Left, Right and their Option forms open and close as in a list of the outline alone")
    func disclosesAsAlone() {
        twins([
            ("Down to a leaf of a branch", { $0.press(.down, times: 12) }),
            ("Left on a leaf walks to its group", { $0.press(.left) }),
            ("Left closes the group", { $0.press(.left) }),
            ("Right opens it again", { $0.press(.right) }),
            ("Option-Left folds a subtree", { $0.press(.left, modifiers: .option) }),
            ("Option-Right opens it again", { $0.press(.right, modifiers: .option) }),
            ("Page Down, Space", { $0.press(.pageDown, times: 3); $0.press(.space) }),
            ("End", { $0.press(.end) }),
        ])
    }

    /// Two sections, an outline in each: a key opens the rows of the outline
    /// the cursor is in.
    @Test("in a list of two sections, each outline opens its own rows")
    func eachSectionsOutlineOpens() {
        let first = [Node(id: 1, children: [Node(id: 2), Node(id: 3)])]
        let second = [Node(id: 10, children: [Node(id: 11), Node(id: 12)])]
        let app = TestApp(width: 40, height: 12) {
            List(selection: Binding<Int?>.constant(nil)) {
                Section("A") { OutlineGroup(first, children: \.children) { Text(verbatim: "n\($0.id)") } }
                Section("B") { OutlineGroup(second, children: \.children) { Text(verbatim: "n\($0.id)") } }
            }
        }
        _ = app.screen
        if app.focusedID == nil { app.press(.tab) }
        // The cursor starts on n1, the first section's first row: never on a
        // header, as SwiftUI's keyboard never is.
        app.press(.right)
        #expect(app.screen.contains("n2"), "Right on n1 opened it: \(app.screen)")
        // Down past n2, n3 and the second header, to n10.
        app.press(.down, times: 3)
        app.press(.right)
        #expect(app.screen.contains("n11"), "Right on n10 opened it: \(app.screen)")
        app.press(.down)
        app.press(.left)
        app.press(.left)
        #expect(!app.screen.contains("n11"), "Left walked out of n11 and closed n10: \(app.screen)")
        #expect(app.screen.contains("n2"), "the first outline stayed open: \(app.screen)")
    }
}

/// Holds the `ScrollViewProxy` a reader hands its content.
@MainActor
private final class ProxyBox {
    var proxy: ScrollViewProxy?
}

/// A list whose content is one `Section` holding an outline builds only the
/// rows it draws, as a list of the outline alone does (finding G1-section),
/// and draws, moves, opens, closes, selects and scrolls exactly as the eager
/// section did. The eager twin is the same section with the outline's
/// windowing off (`OutlineGroup.windowsListRows`), every row extracted at
/// once.
@MainActor
@Suite("An outline inside a List's Section builds only the rows it draws")
struct OutlineSectionWindowTests {
    /// The tree in one section, with a header and a footer.
    private func section(_ rows: [Node], chosen: Chosen, windowed: Bool = true) -> TestApp {
        TestApp(width: 40, height: 12) {
            List(selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                Section {
                    Self.windowing(OutlineGroup(rows, children: \.children) { Text(verbatim: "n\($0.id)") }, windowed)
                } header: {
                    Text(verbatim: "Things")
                } footer: {
                    Text(verbatim: "The end")
                }
            }
        }
    }

    private static func windowing<D, I, L>(_ outline: OutlineGroup<D, I, L>, _ on: Bool) -> OutlineGroup<D, I, L> {
        var outline = outline
        outline.windowsListRows = on
        return outline
    }

    /// Opens the whole tree: Option-Right on the root, the first row under the
    /// header.
    private func openAll(_ app: TestApp) {
        _ = app.screen
        if app.focusedID == nil { app.press(.tab) }
        app.press(.home)
        if !app.screen.contains("n5") { app.press(.right, modifiers: .option) }
        if !app.screen.contains("n5") {
            app.press(.down)
            app.press(.right, modifiers: .option)
        }
    }

    /// Seen failing without the windowing: the section made a box for every
    /// open row each pass.
    @Test("the rows a frame lists do not grow with the open rows")
    func listedIndependentOfOpenRows() {
        var listedAt: [Int: Int] = [:]
        for count in [1_000, 10_000] {
            let app = section(tree(count: count), chosen: Chosen())
            openAll(app)
            #expect(app.screen.contains("n5"), "the tree opened: \(app.screen)")
            let before = app.headless.renderCache.rowWork.listed
            app.scroll(.down, by: 5)
            app.scroll(.down, by: 5)
            app.press(.pageDown, times: 2)
            app.press(.down, times: 3)
            app.press(.left)
            app.press(.right)
            listedAt[count] = app.headless.renderCache.rowWork.listed - before
        }
        #expect(listedAt[1_000] == listedAt[10_000], "the same steps list the same rows at 1,000 and 10,000: \(listedAt)")
        #expect((listedAt[1_000] ?? .max) < 400, "a screenful or so a step, not the tree: \(listedAt)")
    }

    /// Plays `steps` on the windowed section and its eager twin, comparing
    /// their screens and selections after each.
    private func twins(
        _ steps: [(String, (TestApp) -> Void)], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rows = tree(count: 2_000)
        let (windowedChoice, eagerChoice) = (Chosen(), Chosen())
        let lists = [section(rows, chosen: windowedChoice), section(rows, chosen: eagerChoice, windowed: false)]
        for app in lists { openAll(app) }
        #expect(lists[0].screen.contains("n5"), "opened: \(lists[0].screen)", sourceLocation: sourceLocation)
        #expect(lists[0].screen == lists[1].screen, "opened", sourceLocation: sourceLocation)
        for (name, step) in steps {
            for app in lists { step(app) }
            #expect(lists[0].screen == lists[1].screen, "after \(name)", sourceLocation: sourceLocation)
            #expect(windowedChoice.one == eagerChoice.one, "selection after \(name)", sourceLocation: sourceLocation)
        }
    }

    @Test("scrolled anywhere, the windowed section draws what the eager one does, header and footer included")
    func drawsAsEagerAtScrollPositions() {
        twins([
            ("a wheel step", { $0.scroll(.down, by: 1) }),
            ("seven more", { $0.scroll(.down, by: 7) }),
            ("three hundred more", { $0.scroll(.down, by: 300) }),
            ("back up forty", { $0.scroll(.up, by: 40) }),
            ("to the end, and the footer", { $0.scroll(.down, by: 5_000) }),
            ("back to the top, and the header", { $0.scroll(.up, by: 5_000) }),
        ])
    }

    @Test("Up, Down, Page Down, Home and End move the cursor as in the eager section")
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

    @Test("Left closes and walks out, Right opens, as in the eager section, far down the tree")
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

    @Test("Space selects and type select finds a row, as in the eager section")
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
                List {
                    Section("Things") { OutlineGroup(rows, children: \.children) { Text(verbatim: "n\($0.id)") } }
                }
            }
        }
        openAll(app)
        #expect(!app.screen.contains("n1503"))
        // Centred: the section's header is pinned over the top row.
        box.proxy?.scrollTo(1_503, anchor: .center)
        #expect(app.screen.contains("n1503"), "\(app.screen)")
    }
}
