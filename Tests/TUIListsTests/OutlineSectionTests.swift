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
        // The cursor starts on the first section's header; Down takes it to n1.
        app.press(.down)
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
