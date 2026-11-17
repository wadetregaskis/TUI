//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineExpansionBindingTests.swift
//
//  `List(_:children:expansion:)` and `OutlineGroup(_:children:expansion:)`:
//  the app keeps which branches are open. The outline opens exactly the ids in
//  the set, the user's keys and clicks write it, the app's writes open and
//  close branches, in a list of the outline alone, in a `Section` and in a
//  bare outline; and with no binding the outline behaves as it did before it
//  took one. The list's twin of TableOutlineExpansionBindingTests.
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

/// The branches the app keeps open, and the row the list selects.
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

/// Where the outline sits: a `List(_:children:)`, an `OutlineGroup` in a
/// list's `Section`, or a bare `OutlineGroup` in a `VStack`.
enum OutlineHost: CaseIterable, CustomTestStringConvertible {
    case list, section

    var testDescription: String { self == .list ? "List(_:children:)" : "Section { OutlineGroup }" }
}

@MainActor
private func app(
    _ model: Model, in host: OutlineHost = .list, roots: [Node] = tree, height: Int = 14, bound: Bool = true
) -> TestApp {
    let expansion = bound ? model.openBinding : nil
    return TestApp(width: 40, height: height) {
        ScrollViewReader { proxy in
            // In a builder a bare `_ = …` does not compile: `let _` is the
            // idiom for a side effect there, as in ScrollViewReaderTests.
            // swiftlint:disable:next redundant_discardable_let
            let _ = model.proxy = proxy
            switch host {
            case .list:
                List(roots, children: \.children, expansion: expansion, selection: model.selectionBinding) {
                    Text(verbatim: $0.id)
                }
            case .section:
                List(selection: model.selectionBinding) {
                    Section {
                        OutlineGroup(roots, children: \.children, expansion: expansion) { Text(verbatim: $0.id) }
                    }
                }
            }
        }
    }
}

/// Puts the keyboard on the list's first row.
@MainActor
private func focus(_ app: TestApp) {
    _ = app.screen
    if app.focusedID == nil { app.press(.tab) }
}

@MainActor
@Suite("List(_:children:expansion:) and OutlineGroup(_:children:expansion:): the app's own expansion")
struct OutlineExpansionBindingTests {
    @Test("A root the set names starts open; nothing else does", arguments: OutlineHost.allCases)
    func startsOpen(_ host: OutlineHost) {
        let screen = app(Model(open: ["root"]), in: host).screen
        #expect(screen.contains("alpha"), "\(screen)")
        #expect(screen.contains("bravo"))
        #expect(!screen.contains("alpha-one"), "alpha is not in the set")
        #expect(!screen.contains("other-one"))
    }

    @Test("The app's writes to the set open and close branches", arguments: OutlineHost.allCases)
    func appOpensAndCloses(_ host: OutlineHost) {
        let model = Model()
        let app = app(model, in: host)
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

    @Test("Right, Left, Option-Right and Option-Left write the set", arguments: OutlineHost.allCases)
    func keysWriteTheSet(_ host: OutlineHost) {
        let model = Model()
        let app = app(model, in: host)
        focus(app)
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

    @Test("Two toggles before the next frame each read what the one before wrote, and the app's writes")
    func togglesBetweenFrames() {
        let model = Model()
        let outline = OutlineGroup(tree, children: \.children, expansion: model.openBinding) { Text(verbatim: $0.id) }
        let app = TestApp(width: 40, height: 14) {
            List(selection: model.selectionBinding) { outline }
        }
        _ = app.screen
        // Two keys handled before the next frame act on one pass's rows: the
        // second reads the set the first wrote, not the one the pass read.
        #expect(outline.setRowExpanded(AnyHashable("root"), to: nil, includingDescendants: false))
        #expect(model.open == ["root"])
        model.open.insert("other")
        #expect(outline.setRowExpanded(AnyHashable("root"), to: nil, includingDescendants: false))
        #expect(model.open == ["other"], "the second toggle closed root, keeping the app's write")
        #expect(
            !outline.setRowExpanded(AnyHashable("root"), to: false, includingDescendants: false),
            "closing a closed branch moves nothing, and writes nothing")
    }

    @Test("The kept rows are the same while the app's set is, and flattened again when it changes")
    func keptWhileTheSetIsTheSame() {
        let model = Model(open: ["root"])
        let kept = OutlineVisibleNodes<Node, String>()
        let expansion = OutlineExpansion(model.openBinding)
        let keyPaths: [AnyKeyPath] = [\Node.id, \Node.children]
        var flattenings = 0
        func nodes() -> [String] {
            let reading = expansion.read()
            return kept.nodes(roots: tree, keyPaths: keyPaths, comparesByStorage: true, expansion: reading) {
                flattenings += 1
                return OutlineGroup(tree, children: \.children) { Text(verbatim: $0.id) }
                    .visibleNodes(expanded: reading.open)
            }.map(\.id)
        }
        #expect(nodes() == ["root", "alpha", "bravo", "other", "last"])
        #expect(nodes() == ["root", "alpha", "bravo", "other", "last"])
        #expect(flattenings == 1, "an unchanged set keeps the rows")
        model.open.insert("other")
        #expect(nodes() == ["root", "alpha", "bravo", "other", "other-one", "last"])
        #expect(flattenings == 2)
        #expect(nodes().count == 6)
        #expect(flattenings == 2)
    }

    @Test("A click on a triangle writes the set", arguments: OutlineHost.allCases)
    func clickWritesTheSet(_ host: OutlineHost) throws {
        let model = Model()
        let app = app(model, in: host)
        try app.click(TerminalSymbols.disclosureCollapsed)
        #expect(model.open == ["root"])
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("alpha"))
    }

    @Test("A bare outline: the set opens it, and its triangle's keys and clicks write the set")
    func bareOutline() throws {
        let model = Model(open: ["root"])
        let app = TestApp(width: 40, height: 14) {
            VStack(alignment: .leading, spacing: 0) {
                OutlineGroup(tree, children: \.children, expansion: model.openBinding) { Text(verbatim: $0.id) }
            }
        }
        #expect(app.screen.contains("alpha"), "\(app.screen)")
        #expect(!app.screen.contains("alpha-one"))
        model.open.insert("alpha")
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("alpha-one"), "\(app.screen)")
        focus(app)
        app.press(.left)
        #expect(model.open == ["alpha"], "Left on the root's triangle, the first Tab stop, closes it")
        app.press(.right)
        #expect(model.open == ["root", "alpha"])
        try app.click(TerminalSymbols.disclosureCollapsed)
        #expect(model.open.contains("alpha-two"), "the first closed triangle on screen is alpha-two's")
    }

    @Test("Find: open a row's ancestors from code, select it and scroll to it", arguments: OutlineHost.allCases)
    func findOpensAncestors(_ host: OutlineHost) throws {
        // Many roots, so the match is well below the first screen.
        let roots = (0..<60).map { index in
            Node(
                id: "folder-\(index)",
                children: [Node(id: "sub-\(index)", children: [Node(id: "file-\(index)")])])
        }
        let model = Model()
        let app = app(model, in: host, roots: roots, height: 10)
        #expect(!app.screen.contains("file-42"))
        model.open.formUnion(["folder-42", "sub-42"])
        model.selection = "file-42"
        model.proxy?.scrollTo("file-42")
        app.advance(by: .milliseconds(20))
        let screen = app.screen
        #expect(screen.contains("file-42"), "\(screen)")
        let file = try #require(screen.location(of: "file-42"))
        let sub = try #require(screen.location(of: "sub-42"))
        #expect(file.x - sub.x == DisclosureMetrics.contentIndent, "a level beneath its parent")
        #expect(!screen.contains("sub-41"), "only the match's ancestors opened")
    }

    @Test("Ids the set names that are leaves, or not in the tree, open nothing", arguments: OutlineHost.allCases)
    func strayIDs(_ host: OutlineHost) {
        let model = Model(open: ["last", "nowhere"])
        let app = app(model, in: host)
        #expect(app.screen.contains("last"))
        #expect(!app.screen.contains("alpha"))
        focus(app)
        app.press(.right)
        #expect(model.open == ["last", "nowhere", "root"], "the user's open keeps the app's other ids")
    }
}

/// With no binding the outline keeps its own expansion, as before it took one:
/// the same script, with and without the app's binding, draws the same frames
/// and selects the same rows.
@MainActor
@Suite("List(_:children:) and OutlineGroup with and without an expansion binding")
struct OutlineExpansionTwinTests {
    private func frames(_ host: OutlineHost, bound: Bool) -> (frames: [[String]], selections: [String?]) {
        let model = Model()
        let app = app(model, in: host, bound: bound)
        var frames = [app.screen.lines]
        var selections = [model.selection]
        focus(app)
        frames.append(app.screen.lines)
        for (key, modifiers) in [
            (Key.right, EventModifiers()), (.down, []), (.right, .option), (.down, []), (.down, []), (.left, []),
            (.left, []), (.down, []), (.down, []), (.right, []), (.space, []), (.up, []), (.left, .option),
            (.end, []), (.right, []), (.space, []),
        ] as [(Key, EventModifiers)] {
            app.press(key, modifiers: modifiers)
            frames.append(app.screen.lines)
            selections.append(model.selection)
        }
        return (frames, selections)
    }

    @Test("Bound and unbound outlines draw the same frames under one script of keys", arguments: OutlineHost.allCases)
    func sameFrames(_ host: OutlineHost) {
        let unbound = frames(host, bound: false)
        let bound = frames(host, bound: true)
        #expect(unbound.frames.count == bound.frames.count)
        for (index, pair) in zip(unbound.frames, bound.frames).enumerated() {
            #expect(pair.0 == pair.1, "frame \(index)")
        }
        #expect(unbound.selections == bound.selections)
        #expect(unbound.frames.contains { $0.joined().contains("deep") }, "the script opened the tree")
    }
}
