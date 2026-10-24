//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectionModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitTables
@testable import TUIkitTestSupport

@MainActor
@Suite("textSelection(_:)")
struct TextSelectionModifierTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @Test("The selectabilities say what they allow, through the protocol too")
    func selectabilities() {
        func allows<S: TextSelectability>(_: S) -> Bool { S.allowsSelection }
        #expect(EnabledTextSelectability.allowsSelection)
        #expect(!DisabledTextSelectability.allowsSelection)
        #expect(allows(.enabled))
        #expect(!allows(.disabled))
    }

    // MARK: - Harness

    func harness(_ page: some View) -> InputChainHarness {
        let harness = InputChainHarness(width: 40, height: 10)
        harness.frame(page)
        harness.frame(page)
        return harness
    }

    func find(_ needle: String, in harness: InputChainHarness, _ page: some View) throws -> (x: Int, y: Int) {
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains(needle) })
        let prefix = try #require(lines[row].range(of: needle)).lowerBound
        return (lines[row][..<prefix].count, row)
    }

    func left(_ harness: InputChainHarness, _ phase: MousePhase, _ x: Int, _ y: Int) {
        harness.mouse(MouseEvent(button: .left, phase: phase, x: x, y: y))
    }

    func drag(_ harness: InputChainHarness, _ page: some View, from: (x: Int, y: Int), to: (x: Int, y: Int)) {
        left(harness, .pressed, from.x, from.y)
        harness.frame(page)
        left(harness, .dragged, to.x, to.y)
        harness.frame(page)
        left(harness, .released, to.x, to.y)
        harness.frame(page)
    }

    func click(_ harness: InputChainHarness, _ page: some View, _ at: (x: Int, y: Int)) {
        left(harness, .pressed, at.x, at.y)
        left(harness, .released, at.x, at.y)
        harness.frame(page)
    }

    // MARK: - Disabled

    struct Words: View {
        var body: some View {
            VStack(alignment: .leading) {
                Text("alpha beta gamma")
                Text("other words here")
            }
        }
    }

    @Test(".disabled selects nothing")
    func disabled() throws {
        let page = Words().textSelection(.disabled)
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, page, from: alpha, to: (alpha.x + 6, alpha.y + 1))
        #expect(!harness.tui.screenSelection.hasSelection)
    }

    @Test("The innermost scope wins")
    func innermostWins() throws {
        let page = VStack(alignment: .leading) {
            Text("alpha beta gamma").textSelection(.enabled)
            Text("other words here")
        }
        .textSelection(.disabled)
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, page, from: alpha, to: (alpha.x + 4, alpha.y))
        #expect(harness.tui.screenSelection.current?.text == "alpha")
        let other = try find("other", in: harness, page)
        drag(harness, page, from: other, to: (other.x + 4, other.y))
        #expect(!harness.tui.screenSelection.hasSelection)
    }

    // MARK: - Enabled on one Text

    @Test(".enabled on one Text keeps the selection to it")
    func oneText() throws {
        let page = VStack(alignment: .leading) {
            Text("alpha beta gamma").textSelection(.enabled)
            Text("other words here")
        }
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, page, from: alpha, to: (alpha.x + 8, alpha.y + 1))
        #expect(harness.tui.screenSelection.current?.text == "alpha beta gamma")
    }

    // MARK: - Lists

    struct RowsPage: View {
        let selection: Box<Int?>
        let activated: Box<[Int]>
        let selectable: Bool

        var body: some View {
            let list = List(selection: Binding(get: { selection.value }, set: { selection.value = $0 })) {
                ForEach(0..<4, id: \.self) { index in
                    Text("row \(index) words")
                }
            }
            .contextMenu(forSelectionType: Int.self) { _ in } primaryAction: { activated.value.append(contentsOf: $0.sorted()) }
            .frame(height: 8)
            if selectable {
                list.textSelection(.enabled)
            } else {
                list
            }
        }
    }

    @Test("Without the modifier a click on a row's text selects the row, as before")
    func rowsWithoutModifier() throws {
        let page = RowsPage(selection: Box(nil), activated: Box([]), selectable: false)
        let harness = harness(page)
        let row = try find("row 2", in: harness, page)
        click(harness, page, (row.x + 1, row.y))
        #expect(page.selection.value == 2)
        // And a drag over it selects no text.
        drag(harness, page, from: (row.x, row.y), to: (row.x + 4, row.y))
        #expect(!harness.tui.screenSelection.hasSelection)
    }

    @Test("Under .enabled a drag over a row's text selects it, kept to the row, and leaves the rows alone")
    func rowsDragSelectsText() throws {
        let page = RowsPage(selection: Box(nil), activated: Box([]), selectable: true)
        let harness = harness(page)
        let row1 = try find("row 1", in: harness, page)
        drag(harness, page, from: (row1.x + 4, row1.y), to: (row1.x + 6, row1.y + 2))
        #expect(harness.tui.screenSelection.current?.text == "1 words")
        #expect(page.selection.value == nil)
    }

    @Test("Under .enabled a click on a row's text selects nothing, and on its blank cells the row")
    func rowsClick() throws {
        let page = RowsPage(selection: Box(nil), activated: Box([]), selectable: true)
        let harness = harness(page)
        let row = try find("row 2", in: harness, page)
        click(harness, page, (row.x + 1, row.y))
        #expect(page.selection.value == nil)
        click(harness, page, (row.x + 20, row.y))
        #expect(page.selection.value == 2)
    }

    // MARK: - On the rows' own text

    struct RowTextPage: View {
        let selection: Box<Int?>
        var body: some View {
            List(selection: Binding(get: { selection.value }, set: { selection.value = $0 })) {
                ForEach(0..<4, id: \.self) { index in
                    Text("row \(index) words").textSelection(.enabled)
                }
            }
            .frame(height: 8)
        }
    }

    /// SwiftUI's own example shape: the modifier on the row's `Text`, which
    /// the list's environment never sees. It was a silent no-op: the press
    /// went to the list, and a drag selected rows rather than text.
    @Test("On a row's Text, a drag over it selects the text, kept to that Text, and a click selects no row")
    func rowTextModifier() throws {
        let page = RowTextPage(selection: Box(nil))
        let harness = harness(page)
        let row1 = try find("row 1", in: harness, page)
        drag(harness, page, from: (row1.x + 4, row1.y), to: (row1.x + 6, row1.y + 2))
        #expect(harness.tui.screenSelection.current?.text == "1 words")
        #expect(page.selection.value == nil)
        let row2 = try find("row 2", in: harness, page)
        click(harness, page, (row2.x + 1, row2.y))
        #expect(page.selection.value == nil)
        click(harness, page, (row2.x + 20, row2.y))
        #expect(page.selection.value == 2)
    }

    struct CellTextPage: View {
        let selection: Box<Int?>
        var body: some View {
            Table(
                (0..<4).map { Item(id: $0, name: "item \($0) name") },
                selection: Binding(get: { selection.value }, set: { selection.value = $0 })
            ) {
                TableColumn("Name") { item in Text(item.name).textSelection(.enabled) }
            }
            .frame(height: 9)
        }
    }

    @Test("On a Table cell's Text, a drag over it selects the text and leaves the rows alone")
    func cellTextModifier() throws {
        let page = CellTextPage(selection: Box(nil))
        let harness = harness(page)
        let row1 = try find("item 1", in: harness, page)
        drag(harness, page, from: (row1.x + 5, row1.y), to: (row1.x + 7, row1.y + 2))
        #expect(harness.tui.screenSelection.current?.text == "1 name")
        #expect(page.selection.value == nil)
    }

    struct TwoColumnCellTextPage: View {
        var selection = Box<Int?>(nil)
        var body: some View {
            Table(
                (0..<4).map { Item(id: $0, name: "item \($0) name") },
                selection: Binding(get: { selection.value }, set: { selection.value = $0 })
            ) {
                TableColumn("Name") { item in Text(item.name).textSelection(.enabled) }
                TableColumn("Other") { item in Text("other \(item.id)") }
            }
            .frame(height: 9)
        }
    }

    /// The table carries a view cell's regions up, its scope's among them: a
    /// press on the scoped cell's text is under that scope, and the selection
    /// keeps to the cell, as on a List row's own Text. The row's other text is
    /// under no scope: a drag there selects nothing, and a click there selects
    /// the row, as on macOS (owner ruling B-D4X-7-17; it used to keep to the
    /// row, B-D4X-17, so a click there selected nothing).
    @Test("On a Table cell's Text, a drag from it keeps to the cell, and the row's other text is the row's")
    func cellTextKeepsToTheCell() throws {
        let page = TwoColumnCellTextPage()
        let harness = InputChainHarness(width: 60, height: 10)
        harness.frame(page)
        harness.frame(page)
        let name = try find("item 1", in: harness, page)
        drag(harness, page, from: (name.x + 5, name.y), to: (name.x + 40, name.y))
        #expect(harness.tui.screenSelection.current?.text == "1 name")
        #expect(page.selection.value == nil)
        let other = try find("other 1", in: harness, page)
        drag(harness, page, from: (other.x + 1, other.y), to: (name.x, name.y))
        #expect(harness.tui.screenSelection.current == nil)
        let row2 = try find("other 2", in: harness, page)
        click(harness, page, (row2.x + 1, row2.y))
        #expect(page.selection.value == 2)
        #expect(harness.tui.screenSelection.current == nil)
    }

    struct WholeTablePage: View {
        var body: some View {
            Table((0..<4).map { Item(id: $0, name: "item \($0) name") }) {
                TableColumn("Name") { item in Text(item.name) }
                TableColumn("Other") { item in Text("other \(item.id)") }
            }
            .textSelection(.enabled)
            .frame(height: 9)
        }
    }

    /// An enabled scope around the whole table keeps a selection to the row
    /// and crosses its columns, as TUIkit's screen selection crosses from one
    /// Text to the next (B-D4X-7, deviation T6; option 1 of B-D4X-7-17).
    @Test("Around a whole Table, a drag on a row's text crosses its columns")
    func wholeTableCrossesColumns() throws {
        let page = WholeTablePage()
        let harness = InputChainHarness(width: 60, height: 10)
        harness.frame(page)
        harness.frame(page)
        let name = try find("item 1", in: harness, page)
        let other = try find("other 1", in: harness, page)
        drag(harness, page, from: (name.x, name.y), to: (other.x + 6, other.y))
        let text = try #require(harness.tui.screenSelection.current?.text)
        #expect(text.hasPrefix("item 1 name") && text.hasSuffix("other 1"), "\(text)")
    }

    struct DisabledTablePage: View {
        var body: some View {
            Table((0..<4).map { Item(id: $0, name: "item \($0) name") }) {
                TableColumn("Name") { item in Text(item.name).textSelection(.enabled) }
                TableColumn("Other") { item in Text("other \(item.id)") }
            }
            .textSelection(.disabled)
            .frame(height: 9)
        }
    }

    struct DisabledListPage: View {
        var body: some View {
            List((0..<4).map { Item(id: $0, name: "item \($0) name") }) { item in
                Text(item.name).textSelection(.enabled)
            }
            .textSelection(.disabled)
            .frame(height: 9)
        }
    }

    /// Review 2 of 01d0647cb: inside an outer `.disabled`, a cell's `.enabled`
    /// was said to lose to it, unlike a List row's. The table carries a view
    /// cell's regions up, its scope's among them, so the cell's scope is the
    /// innermost under a press on its text, and wins; the row's other text is
    /// under the outer scope alone, and selects nothing.
    @Test("Inside a disabled Table or List, a row's .enabled Text still selects: the innermost modifier wins")
    func innermostWinsInRows() throws {
        let table = DisabledTablePage()
        let harness = InputChainHarness(width: 60, height: 10)
        harness.frame(table)
        harness.frame(table)
        let name = try find("item 1", in: harness, table)
        drag(harness, table, from: (name.x + 5, name.y), to: (name.x + 40, name.y))
        #expect(harness.tui.screenSelection.current?.text == "1 name")
        let other = try find("other 2", in: harness, table)
        drag(harness, table, from: (other.x, other.y), to: (other.x + 6, other.y))
        #expect(harness.tui.screenSelection.current == nil)

        let list = DisabledListPage()
        let listHarness = self.harness(list)
        let row = try find("item 2", in: listHarness, list)
        drag(listHarness, list, from: (row.x + 5, row.y), to: (row.x + 40, row.y))
        #expect(listHarness.tui.screenSelection.current?.text == "2 name")
    }

    // MARK: - Seen through by containers

    struct LoopPage: View {
        let selection: Box<Int?>
        var body: some View {
            List(selection: Binding(get: { selection.value }, set: { selection.value = $0 })) {
                ForEach(0..<4, id: \.self) { index in
                    Text("row \(index) words")
                }
                .textSelection(.enabled)
            }
            .frame(height: 8)
        }
    }

    /// An environment-like modifier on a list's loop: SwiftUI gives every
    /// element its own row. Opaque, the wrapper made the loop ONE row.
    @Test("On a List's ForEach it leaves one row per element")
    func loopKeepsItsRows() throws {
        let page = LoopPage(selection: Box(nil))
        let harness = harness(page)
        let row = try find("row 2", in: harness, page)
        click(harness, page, (row.x + 20, row.y))
        #expect(page.selection.value == 2)
    }

    @Test("On a stack's ForEach the stack still spaces its members")
    func loopKeepsItsSpacing() throws {
        let page = VStack(alignment: .leading, spacing: 1) {
            ForEach(0..<3, id: \.self) { index in
                Text("member \(index)")
            }
            .textSelection(.enabled)
        }
        let lines = harness(page).frame(page).lines.map(\.stripped)
        let rows = (0..<3).compactMap { index in lines.firstIndex { $0.contains("member \(index)") } }
        #expect(rows.count == 3)
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $1 - $0 == 2 })
    }

    /// SwiftUI keeps a z-index through a modifier that is not a container,
    /// as `ZStack { Color.red.zIndex(1).padding(0); Color.green }` shows.
    @Test("A z-index written inside it still orders the stack")
    func zIndexSeenThrough() {
        let page = ZStack(alignment: .leading) {
            Text("AAAA").zIndex(1).textSelection(.enabled)
            Text("BB")
        }
        let lines = harness(page).frame(page).lines.map(\.stripped)
        #expect(lines.contains { $0.hasPrefix("AAAA") })
    }

    // MARK: - Tables, the sibling

    struct Item: Identifiable {
        let id: Int
        let name: String
    }

    struct TablePage: View {
        let selection: Box<Int?>
        var body: some View {
            Table(
                (0..<4).map { Item(id: $0, name: "item \($0) name") },
                selection: Binding(get: { selection.value }, set: { selection.value = $0 })
            ) {
                TableColumn("Name", value: \.name)
            }
            .frame(height: 9)
            .textSelection(.enabled)
        }
    }

    @Test("Under .enabled a Table's row text is selected as a List's is, and a click on it selects no row")
    func tableRows() throws {
        let page = TablePage(selection: Box(nil))
        let harness = harness(page)
        let row1 = try find("item 1", in: harness, page)
        drag(harness, page, from: (row1.x + 5, row1.y), to: (row1.x + 7, row1.y + 2))
        #expect(harness.tui.screenSelection.current?.text.hasPrefix("1 name") == true)
        #expect(page.selection.value == nil)
        let row2 = try find("item 2", in: harness, page)
        click(harness, page, (row2.x + 1, row2.y))
        #expect(page.selection.value == nil)
    }

    @Test("Under .enabled a double-click on a row's word selects the word and activates nothing")
    func rowsDoubleClick() throws {
        let page = RowsPage(selection: Box(nil), activated: Box([]), selectable: true)
        let harness = harness(page)
        let words = try find("words", in: harness, page)
        for _ in 0..<2 {
            left(harness, .pressed, words.x + 1, words.y)
            left(harness, .released, words.x + 1, words.y)
        }
        harness.frame(page)
        #expect(harness.tui.screenSelection.current?.text == "words")
        #expect(page.activated.value.isEmpty)
        #expect(page.selection.value == nil)
    }
}
