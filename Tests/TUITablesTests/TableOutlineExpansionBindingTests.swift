//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlineExpansionBindingTests.swift
//
//  `Table(_:children:expansion:)`: the app keeps which branches are open.
//  The table opens exactly the ids in the set, the user's keys and clicks
//  write it, the app's writes open and close branches, and with no binding
//  the table behaves as it did before it took one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITables
import TUITesting
@testable import TUIView

private struct Node: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

private let tree = [
    Node(id: "root", children: [
        Node(id: "alpha", children: [Node(id: "alpha-one"), Node(id: "alpha-two", children: [Node(id: "deep")])]),
        Node(id: "bravo"),
    ]),
    Node(id: "other", children: [Node(id: "other-one")]),
    Node(id: "last"),
]

/// The branches the app keeps open, and the row the table selects.
@Observable
@MainActor
private final class Model {
    var open: Set<String>
    var selection: String?
    /// The proxy a `ScrollViewReader` hands its content, for a Find to scroll with.
    @ObservationIgnored var proxy: ScrollViewProxy?

    init(open: Set<String> = []) {
        self.open = open
    }

    var openBinding: Binding<Set<String>> {
        Binding(get: { self.open }, set: { self.open = $0 })
    }

    var selectionBinding: Binding<String?> {
        Binding(get: { self.selection }, set: { self.selection = $0 })
    }
}

@MainActor
@Suite("Table(_:children:expansion:): the app's own expansion")
struct TableOutlineExpansionBindingTests {
    private func app(_ model: Model, roots: [Node] = tree, height: Int = 14) -> TestApp {
        TestApp(width: 40, height: height) {
            ScrollViewReader { proxy in
                // In a builder a bare `_ = …` does not compile: `let _` is the
                // idiom for a side effect there, as in ScrollViewReaderTests.
                // swiftlint:disable:next redundant_discardable_let
                let _ = model.proxy = proxy
                Table(roots, children: \.children, expansion: model.openBinding, selection: model.selectionBinding) {
                    TableColumn("Name", value: \Node.id)
                }
            }
        }
    }

    @Test("A root the set names starts open; nothing else does")
    func startsOpen() {
        let screen = app(Model(open: ["root"])).screen
        #expect(screen.contains("alpha"), "\(screen)")
        #expect(screen.contains("bravo"))
        #expect(!screen.contains("alpha-one"), "alpha is not in the set")
        #expect(!screen.contains("other-one"))
    }

    @Test("The app's writes to the set open and close branches")
    func appOpensAndCloses() {
        let model = Model()
        let app = app(model)
        #expect(!app.screen.contains("alpha"))
        model.open = ["root", "alpha"]
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("alpha-one"), "\(app.screen)")
        #expect(app.screen.contains("alpha-two"))
        model.open.remove("root")
        app.advance(by: .milliseconds(20))
        #expect(!app.screen.contains("alpha"), "a closed root hides its open descendants")
        model.open.insert("root")
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("alpha-one"), "and reopened, shows them as they were left")
    }

    @Test("Right, Left, Option-Right and Option-Left write the set")
    func keysWriteTheSet() {
        let model = Model()
        let app = app(model)
        app.press(.tab)
        app.press(.right)
        #expect(model.open == ["root"])
        app.press(.left)
        #expect(model.open.isEmpty)
        app.press(.right, modifiers: .option)
        #expect(model.open == ["root", "alpha", "alpha-two"], "every branch beneath the row")
        #expect(app.screen.contains("deep"), "\(app.screen)")
        app.press(.left, modifiers: .option)
        #expect(model.open.isEmpty)
        #expect(!app.screen.contains("alpha"))
    }

    @Test("Two toggles on one frame's outline each read what the one before wrote, and the app's writes")
    func togglesBetweenFrames() {
        let model = Model()
        let outline = _TableOutlineCache<Node>().outline(
            of: _TableOutlineRoots(tree, children: \.children, expansion: model.openBinding),
            expansion: OutlineExpansion<Node.ID>(model.openBinding))
        // Two keys handled before the next frame act on one outline: the
        // second reads the set the first wrote, not the one the frame read.
        #expect(outline.setExpanded(AnyHashable("root"), to: nil, includingDescendants: false))
        #expect(model.open == ["root"])
        model.open.insert("other")
        #expect(outline.setExpanded(AnyHashable("root"), to: nil, includingDescendants: false))
        #expect(model.open == ["other"], "the second toggle closed root, keeping the app's write")
    }

    @Test("The kept outline is the same while the app's set is, and made again when it changes")
    func keptWhileTheSetIsTheSame() {
        let model = Model(open: ["root"])
        let cache = _TableOutlineCache<Node>()
        let roots = _TableOutlineRoots(tree, children: \.children, expansion: model.openBinding)
        let expansion = OutlineExpansion<Node.ID>(model.openBinding)
        let first = cache.outline(of: roots, expansion: expansion)
        #expect(cache.outline(of: roots, expansion: expansion) === first)
        model.open.insert("other")
        let second = cache.outline(of: roots, expansion: expansion)
        #expect(second !== first)
        #expect(second.values.map(\.id) == ["root", "alpha", "bravo", "other", "other-one", "last"])
        #expect(cache.outline(of: roots, expansion: expansion) === second)
    }

    @Test("A click on a triangle writes the set")
    func clickWritesTheSet() throws {
        let model = Model()
        let app = app(model)
        try app.click(TerminalSymbols.disclosureCollapsed)
        #expect(model.open == ["root"])
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("alpha"))
    }

    @Test("Find: open a row's ancestors from code, select it and scroll to it")
    func findOpensAncestors() throws {
        // Many roots, so the match is well below the first screen.
        let roots = (0..<60).map { index in
            Node(
                id: "folder-\(index)",
                children: [Node(id: "sub-\(index)", children: [Node(id: "file-\(index)")])])
        }
        let model = Model()
        let app = app(model, roots: roots, height: 10)
        #expect(!app.screen.contains("file-42"))
        model.open.formUnion(["folder-42", "sub-42"])
        model.selection = "file-42"
        model.proxy?.scrollTo("file-42")
        app.advance(by: .milliseconds(20))
        let screen = app.screen
        #expect(screen.contains("file-42"), "\(screen)")
        let file = try #require(screen.location(of: "file-42"))
        let sub = try #require(screen.location(of: "sub-42"))
        #expect(file.x - sub.x == _TableOutline<Node>.indentStep, "a level beneath its parent")
        #expect(!screen.contains("sub-41"), "only the match's ancestors opened")
    }

    @Test("Ids the set names that are leaves, or not in the tree, open nothing")
    func strayIDs() {
        let model = Model(open: ["last", "nowhere"])
        let app = app(model)
        #expect(app.screen.contains("last"))
        #expect(!app.screen.contains("alpha"))
        app.press(.tab)
        app.press(.right)
        #expect(model.open == ["last", "nowhere", "root"], "the user's open keeps the app's other ids")
    }
}

/// With no binding the table keeps its own expansion, as before it took one:
/// the same script, with and without the app's binding, draws the same frames.
@MainActor
@Suite("Table(_:children:) with and without an expansion binding")
struct TableOutlineExpansionTwinTests {
    private func frames(bound: Bool) -> [[String]] {
        let model = Model()
        let app = TestApp(width: 40, height: 14) {
            if bound {
                Table(tree, children: \.children, expansion: model.openBinding, selection: model.selectionBinding) {
                    TableColumn("Name", value: \Node.id)
                }
            } else {
                Table(tree, children: \.children, selection: model.selectionBinding) {
                    TableColumn("Name", value: \Node.id)
                }
            }
        }
        var frames = [app.screen.lines]
        app.press(.tab)
        frames.append(app.screen.lines)
        for (key, modifiers) in [
            (Key.right, EventModifiers()), (.down, []), (.right, .option), (.down, []), (.down, []), (.left, []),
            (.left, []), (.down, []), (.down, []), (.right, []), (.up, []), (.left, .option), (.end, []), (.right, []),
        ] as [(Key, EventModifiers)] {
            app.press(key, modifiers: modifiers)
            frames.append(app.screen.lines)
        }
        return frames
    }

    @Test("Bound and unbound tables draw the same frames under one script of keys")
    func sameFrames() {
        let unbound = frames(bound: false)
        let bound = frames(bound: true)
        #expect(unbound.count == bound.count)
        for (index, pair) in zip(unbound, bound).enumerated() {
            #expect(pair.0 == pair.1, "frame \(index)")
        }
    }
}
