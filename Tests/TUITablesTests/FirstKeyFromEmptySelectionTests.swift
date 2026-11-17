//  🖥️ TUI — A Terminal UI framework for Swift
//  FirstKeyFromEmptySelectionTests.swift
//
//  What the first key does in a focused table or list under
//  `.selectionFollowsCursor()` with nothing selected, beside what macOS does
//  (`Tools/SwiftUIProbes/Scroll to a row/firstkey.swift`, `firstkey.out`):
//  there Down selects the first row, Up the last, a typed letter the first row
//  it names, and Home, End and the page keys only scroll, with a row selected
//  or without. TUI does as macOS does but for Home, End and the page keys,
//  which select (the owner's A-FIRSTKEY-1, 2026-11-16, keeping APPFB-1): a
//  deliberate deviation. A cursor the user placed (a key, a click, the pointer
//  while the focus follows it, Space clearing the selection) is drawn; with
//  none placed, no row is. The analysis, the rulings and what was built are in
//  `Documentation/Historical/Lists, tables and tabs/The first key from an empty selection.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
import TUITables
import TUITesting

private struct Row: Identifiable, Hashable, Sendable {
    let id: Int
    /// The letter cycles a to z, as the probe's do: `a` names rows 0, 26, 52
    /// and 78, `c` rows 2, 28, 54 and 80. Ends in a dash, so `a-5-` is not
    /// found inside `a-52-`.
    var name: String { "\(Array("abcdefghijklmnopqrstuvwxyz")[id % 26])-\(id)-" }
}

@Observable
@MainActor
private final class Selected {
    var single: Int?
    var multiple: Set<Int> = []
    var names = ["kilo", "lima", "mike"]
}

private struct Node: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

@MainActor
@Suite("The first key from an empty selection")
struct FirstKeyFromEmptySelectionTests {
    private let rows = (0..<100).map(Row.init)

    /// A focused table of 100 rows that follows the cursor (unless `follows`
    /// is false), whose `j` key clears the selection, as an app's Deselect All
    /// does.
    private func table(_ selected: Selected, follows: Bool = true) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            Table(rows, selection: Binding(get: { selected.single }, set: { selected.single = $0 })) {
                TableColumn("Name", value: \Row.name)
            }
            .selectionFollowsCursor(follows)
            .onKeyPress("j") {
                selected.single = nil
                return .handled
            }
        }
        app.press(.tab)
        return app
    }

    // MARK: - Where TUI already does what macOS does

    @Test("Up selects the last row")
    func upSelectsTheLastRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.up)
        #expect(selected.single == 99)
    }

    @Test("A letter that is not the cursor row's selects the first row it names")
    func typeSelectFindsTheFirstRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.character("c"))
        app.advance(by: .milliseconds(20))
        #expect(selected.single == 2)
    }

    @Test("Down selects the first row")
    func downSelectsTheFirstRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.down)
        #expect(selected.single == 0)
    }

    @Test("Down selects the first row of a list with a multiple selection")
    func downSelectsTheFirstRowOfAList() {
        let selected = Selected()
        let app = TestApp(width: 40, height: 12) {
            List(selection: Binding(get: { selected.multiple }, set: { selected.multiple = $0 })) {
                ForEach(rows) { Text(verbatim: $0.name) }
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        app.press(.down)
        #expect(selected.multiple == [0])
    }

    @Test("The letter of the first row selects the first row")
    func typeSelectFirstRowsLetter() {
        let selected = Selected()
        let app = table(selected)
        app.press(.character("a"))
        app.advance(by: .milliseconds(20))
        #expect(selected.single == 0)
    }

    @Test("A selection the app clears is forgotten: Up selects the last row")
    func clearedByTheAppUp() {
        let selected = Selected()
        let app = table(selected)
        for _ in 0..<5 { app.press(.down) }
        app.press(.character("j"))
        app.press(.up)
        #expect(selected.single == 99)
    }

    @Test("A selection the app clears is forgotten: Down selects the first row")
    func clearedByTheApp() {
        let selected = Selected()
        let app = table(selected)
        for _ in 0..<5 { app.press(.down) }
        #expect(selected.single == 4)
        app.press(.character("j"))
        #expect(selected.single == nil)
        app.press(.down)
        #expect(selected.single == 0)
    }

    @Test("A selection the app starts with: Down selects the row after it")
    func startingSelection() {
        let selected = Selected()
        selected.single = 5
        let app = table(selected)
        app.press(.down)
        #expect(selected.single == 6)
    }

    @Test("Without the modifier too, the cursor starts on the selection the app starts with")
    func startingSelectionWithoutTheModifier() {
        let selected = Selected()
        selected.single = 5
        let app = table(selected, follows: false)
        app.press(.down)
        #expect(selected.single == 5, "the arrow moves the cursor alone")
        app.press(.space)
        #expect(selected.single == 6)
    }

    // MARK: - Home, End and the page keys select (A-FIRSTKEY-1, a deliberate deviation)

    // macOS's only scroll, with a row selected or without; the owner kept
    // APPFB-1's reading on 2026-11-16, so that a keyboard user reaches the
    // first and last rows in one key ("Deliberate deviations from SwiftUI.md").

    @Test("From nothing, Home selects the first row")
    func homeSelectsTheFirstRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.home)
        #expect(selected.single == 0)
    }

    @Test("From nothing, End selects the last row")
    func endSelectsTheLastRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.end)
        #expect(selected.single == 99)
    }

    @Test("From nothing, Page Down selects the row a page on")
    func pageDownSelectsAPageOn() {
        let selected = Selected()
        let app = table(selected)
        app.press(.pageDown)
        #expect(selected.single == 9)
    }

    @Test("Home moves a selection to the first row")
    func homeMovesTheSelection() {
        let selected = Selected()
        let app = table(selected)
        app.press(.down, times: 3)
        #expect(selected.single == 2)
        app.press(.home)
        #expect(selected.single == 0)
    }

    // MARK: - A placed cursor is drawn; an unplaced one is not (the owner, 2026-11-16)

    /// The names of the rows drawn unlike the others: the cursor row and the
    /// selected rows. A row's styles in order up to its name, its text left
    /// out, is what tells them apart (the scrollbar's thumb, after the name,
    /// is on some rows and not others); the most common of those among the
    /// rows of its parity is a plain row's (a table's rows are striped).
    private func distinctRows(_ app: TestApp, among names: [String]) -> [String] {
        let lines = app.screen.styledLines
        var styles: [String: String] = [:]
        for name in names {
            guard let line = lines.first(where: { $0.contains(name) }), let end = line.range(of: name)?.upperBound
            else { continue }
            styles[name] = line[..<end].matches(of: /\u{1B}\[[0-9;:]*m/).map { String($0.output) }.joined()
        }
        let plain = (0..<2).map { parity in
            let drawn = names.indices.filter { $0 % 2 == parity }.compactMap { styles[names[$0]] }
            return Dictionary(grouping: drawn) { $0 }.max { $0.value.count < $1.value.count }?.key
        }
        return names.indices.filter { index in
            styles[names[index]].map { $0 != plain[index % 2] } ?? false
        }
        .map { names[$0] }
    }

    private var firstNames: [String] { rows.prefix(8).map(\.name) }

    @Test("From nothing, no row is drawn as the cursor's; the first Down draws it")
    func nothingPlacedDrawsNoCursor() {
        let selected = Selected()
        let app = table(selected)
        #expect(app.focusedID != nil)
        #expect(distinctRows(app, among: firstNames).isEmpty, "\(app.screen)")
        app.press(.down)
        #expect(distinctRows(app, among: firstNames) == ["a-0-"], "\(app.screen)")
    }

    @Test("With nothing placed, the focus arriving scrolls nothing back to the first row")
    func focusArrivingRevealsNothing() throws {
        let selected = Selected()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("Go") {}
                Table(rows, selection: Binding(get: { selected.single }, set: { selected.single = $0 })) {
                    TableColumn("Name", value: \Row.name)
                }
                .selectionFollowsCursor()
            }
        }
        try app.scroll(.down, by: 10, over: "a-0-")
        #expect(!app.screen.contains("a-0-"), "precondition: the wheel scrolled the rows")
        app.press(.tab)
        #expect(app.focusedID != nil)
        #expect(!app.screen.contains("a-0-"), "\(app.screen)")
        app.press(.down)
        #expect(selected.single == 0)
        #expect(app.screen.contains("a-0-"), "Down scrolls back to the row it selects")
    }

    @Test("A selection the app clears takes the drawn cursor with it")
    func appClearHidesTheCursor() {
        let selected = Selected()
        let app = table(selected)
        app.press(.down, times: 3)
        #expect(distinctRows(app, among: firstNames) == ["c-2-"], "\(app.screen)")
        app.press(.character("j"))
        #expect(selected.single == nil)
        #expect(distinctRows(app, among: firstNames).isEmpty, "\(app.screen)")
    }

    /// A-FIRSTKEY-3: Space clearing the selection is the user's own act, and
    /// leaves the cursor where it is, drawn, for the next arrow to go on from.
    @Test("After Space clears the selection the cursor is drawn on its row, and Down goes on from it")
    func spaceClearKeepsTheCursor() {
        let selected = Selected()
        let app = table(selected)
        app.press(.down, times: 3)
        app.press(.space)
        #expect(selected.single == nil)
        #expect(distinctRows(app, among: firstNames) == ["c-2-"], "\(app.screen)")
        app.press(.down)
        #expect(selected.single == 3)
    }

    /// A-FIRSTKEY-2: a cursor the pointer parked, while the focus follows it,
    /// is placed. (Focus Follows Pointer is a *nix idea; macOS has no such
    /// cursor to compare with.)
    @Test("A cursor the pointer parked is drawn on its row, and Down goes on from it")
    func pointerParkedCursor() throws {
        let selected = Selected()
        let app = TestApp(PointerApp(selected: selected, rows: rows), width: 40, height: 12)
        try app.hover(over: "c-2-")
        #expect(app.focusedID != nil)
        #expect(selected.single == nil, "the pointer selects nothing")
        #expect(distinctRows(app, among: firstNames) == ["c-2-"], "\(app.screen)")
        app.press(.down)
        #expect(selected.single == 3)
    }

    /// The same on the first row, where the cursor stood, unplaced, already.
    @Test("A cursor the pointer parked on the first row is drawn there")
    func pointerParkedOnTheFirstRow() throws {
        let selected = Selected()
        let app = TestApp(PointerApp(selected: selected, rows: rows), width: 40, height: 12)
        try app.hover(over: "a-0-")
        #expect(distinctRows(app, among: firstNames) == ["a-0-"], "\(app.screen)")
        app.press(.down)
        #expect(selected.single == 1)
    }
}

extension FirstKeyFromEmptySelectionTests {
    // MARK: - From no row, the keys that act on the cursor's row act on none

    @Test("From nothing, Space selects nothing, and no cursor row is drawn")
    func spaceFromNothing() {
        let selected = Selected()
        let app = table(selected)
        app.press(.space)
        #expect(selected.single == nil)
        #expect(distinctRows(app, among: firstNames).isEmpty, "\(app.screen)")
    }

    @Test("From nothing, Delete deletes no row; after Down, the first")
    func deleteFromNothing() {
        let selected = Selected()
        let app = TestApp(width: 40, height: 12) {
            List(selection: Binding<String?>.constant(nil)) {
                ForEach(selected.names, id: \.self) { Text($0) }
                    .onDelete { offsets in
                        for offset in offsets.reversed() { selected.names.remove(at: offset) }
                    }
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        app.press(.delete)
        #expect(selected.names == ["kilo", "lima", "mike"])
        app.press(.down)
        app.press(.delete)
        #expect(selected.names == ["lima", "mike"])
    }

    @Test("From nothing, a tree's Right opens no branch")
    func rightFromNothing() {
        let tree = [Node(id: "root", children: [Node(id: "leaf")])]
        let app = TestApp(width: 40, height: 12) {
            Table(tree, children: \.children, selection: Binding<String?>.constant(nil)) {
                TableColumn("Name", value: \Node.id)
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        app.press(.right)
        #expect(!app.screen.contains("leaf"), "\(app.screen)")
        #expect(app.focusedID != nil, "the tree keeps the key")
    }
}

/// A table that follows the cursor, in a window whose focus follows the
/// pointer.
private struct PointerApp: App {
    let selected: Selected
    let rows: [Row]
    init() { (selected, rows) = (Selected(), []) }
    init(selected: Selected, rows: [Row]) { (self.selected, self.rows) = (selected, rows) }

    var body: some Scene {
        WindowGroup {
            Table(rows, selection: Binding(get: { selected.single }, set: { selected.single = $0 })) {
                TableColumn("Name", value: \Row.name)
            }
            .selectionFollowsCursor()
        }
        .focusFollowsPointer()
    }
}
