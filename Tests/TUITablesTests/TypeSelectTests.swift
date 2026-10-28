//  🖥️ TUI — A Terminal UI framework for Swift
//  TypeSelectTests.swift
//
//  Type select: with a list or table focused, typing a row's first characters
//  moves the cursor to it — by the row's own text, or by the text it states
//  with `.typeSelectEquivalent(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport

@MainActor
@Suite("Type select")
struct TypeSelectTests {
    private struct Person: Identifiable {
        let id: String
    }

    private static let names = ["Alpha", "Bravo", "Charlie", "Chloe", "Delta"]

    /// Renders `view` twice — the first pass registers, the second focuses —
    /// then hands back its handler and a function that types a key and
    /// re-renders.
    private func harness<V: View>(_ view: V) -> (
        handler: ItemListHandler<String>?, type: (KeyEvent) -> Bool
    ) {
        let context = makeRenderContext(width: 30, height: 10)
        _ = renderToBuffer(view, context: context)
        _ = renderToBuffer(view, context: context)
        let manager = context.environment.focusManager
        let handler = manager?.currentFocused as? ItemListHandler<String>
        return (
            handler,
            { event in
                let taken = manager?.dispatchKeyEvent(event) ?? false
                _ = renderToBuffer(view, context: context)
                return taken
            }
        )
    }

    private func list() -> some View {
        List(selection: .constant(String?.none)) {
            ForEach(Self.names, id: \.self) { Text($0) }
        }
    }

    @Test("A typed letter moves the cursor to the next row starting with it; more letters narrow it")
    func typingMovesTheCursor() {
        let (handler, type) = harness(list())
        #expect(handler?.focusedIndex == 0)
        #expect(type(KeyEvent(key: .character("c"))))
        #expect(handler?.focusedIndex == 2, "Charlie")
        #expect(type(KeyEvent(key: .character("H"))))
        #expect(handler?.focusedIndex == 2, "still Charlie: 'ch' names it")
        #expect(type(KeyEvent(key: .character("l"))))
        #expect(handler?.focusedIndex == 3, "Chloe")
    }

    @Test("A prefix no row starts with leaves the cursor where it is")
    func noMatch() {
        let (handler, type) = harness(list())
        #expect(type(KeyEvent(key: .character("z"))))
        #expect(handler?.focusedIndex == 0)
    }

    @Test("A held Control or Option is no type select, and Space still selects")
    func modifiedKeysPassThrough() {
        let (handler, type) = harness(list())
        _ = type(KeyEvent(key: .character("d"), ctrl: true))
        #expect(handler?.focusedIndex == 0)
        _ = type(KeyEvent(key: .character("d"), alt: true))
        #expect(handler?.focusedIndex == 0)
    }

    @Test("A row's stated equivalent is what it answers to; an empty one takes it out")
    func statedEquivalent() {
        let view = List(selection: .constant(String?.none)) {
            ForEach(Self.names, id: \.self) { name in
                Text("•")
                    .typeSelectEquivalent(name == "Delta" ? "" : name)
            }
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("b")))
        #expect(handler?.focusedIndex == 1, "Bravo, by its stated text")
        _ = type(KeyEvent(key: .character("d")))
        #expect(handler?.focusedIndex == 1, "Delta stated no text, so 'bd' and 'd' find nothing")
    }

    /// A `ForEach` beside a hand-written row is spliced into the list's child
    /// walk, which hands each looped row over inside `ForEach`'s value memo:
    /// the equivalent sat behind that wrapper and the row answered to its
    /// drawn "•" instead.
    @Test("A looped row spliced among hand-written rows answers to the text it states")
    func splicedLoopedRowStatedEquivalent() {
        let view = List(selection: .constant(String?.none)) {
            Text("Top").tag("Top")
            ForEach(Self.names, id: \.self) { name in
                Text("•").typeSelectEquivalent(name)
            }
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("c")))
        #expect(handler?.focusedIndex == 3, "Charlie, row 3 after Top, by its stated text")
    }

    @Test("A looped row's equivalent is found through a wrapper written after it")
    func splicedLoopedRowEquivalentThroughAWrapper() {
        let view = List(selection: .constant(String?.none)) {
            Text("Top").tag("Top")
            ForEach(Self.names, id: \.self) { name in
                Text("•").typeSelectEquivalent(name).padding(.leading, 0)
            }
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("d")))
        #expect(handler?.focusedIndex == 5, "Delta, through the padding")
    }

    /// A section of a hand-written row and a loop is taken apart by the
    /// section's own child walk, which hands the looped rows over inside the
    /// memo as the list's does.
    @Test("A looped row beside a hand-written one in a Section answers to the text it states")
    func sectionLoopedRowStatedEquivalent() {
        let view = List(selection: .constant(String?.none)) {
            Section("People") {
                Text("Top").tag("Top")
                ForEach(Self.names, id: \.self) { name in
                    Text("•").typeSelectEquivalent(name)
                }
            }
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("b")))
        #expect(handler?.focusedIndex == 3, "Bravo, after the header, Top and Alpha")
    }

    @Test("A table answers to its first column")
    func table() {
        let people = Self.names.map(Person.init)
        let view = Table(people, selection: .constant(String?.none)) {
            TableColumn("Name", value: \.id)
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("d")))
        #expect(handler?.focusedIndex == 4, "Delta")
    }

    /// A row of a tree, with or without rows below it.
    private struct Node: Identifiable {
        let id: String
        var children: [Self]?
    }

    @Test("A tree's row answers to its words, not its triangle, with children or without")
    func treeRows() {
        let nodes = [
            Node(id: "Alpha", children: [Node(id: "Inner")]), Node(id: "Bravo"),
            Node(id: "Charlie", children: [Node(id: "Deep")]),
        ]
        let view = Table(nodes, children: \.children, selection: .constant(String?.none)) {
            TableColumn("Name", value: \.id)
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("c")))
        #expect(handler?.focusedIndex == 2, "Charlie, which has children")
        // A fresh table: the typed prefix lasts until a pause, so "b" here
        // would read as "cb".
        let (leafHandler, typeInLeaf) = harness(view)
        _ = typeInLeaf(KeyEvent(key: .character("b")))
        #expect(leafHandler?.focusedIndex == 1, "Bravo, a leaf")
    }

    @Test("A table's view cell answers to the text it states")
    func tableViewCell() {
        let people = Self.names.map(Person.init)
        let view = Table(people, selection: .constant(String?.none)) {
            TableColumn("Name") { (person: Person) in
                Text("•").typeSelectEquivalent(person.id)
            }
        }
        let (handler, type) = harness(view)
        _ = type(KeyEvent(key: .character("c")))
        #expect(handler?.focusedIndex == 2, "Charlie")
    }
}
