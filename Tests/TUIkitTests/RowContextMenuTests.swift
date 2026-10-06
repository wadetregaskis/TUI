//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowContextMenuTests.swift
//
//  Context menus on a table's and a list's rows: a `TableRow`'s own
//  `.contextMenu`, and `contextMenu(forSelectionType:menu:primaryAction:)`
//  around either container — the set of rows it acts on (measured on macOS
//  15.8: a selected row → the selection, an unselected row → that row, empty
//  space → none), which menu wins, Shift+F10 on the cursor row, and the
//  primary action that replaced `onRowActivate` (decisions A30).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@Observable
@MainActor
private final class Rows {
    var selection: Set<Int> = [2, 3]
    var ran: [String] = []
    var opened: [[Int]] = []
    var shape: Shape = .selectionMenu

    enum Shape {
        /// A table with a selection menu and a primary action.
        case selectionMenu
        /// A table whose rows 1 and 2 have menus of their own, inside a view
        /// with a `.contextMenu` of its own.
        case rowMenus
        /// Both: a selection menu around rows with menus, and a cell view
        /// with one.
        case both
        /// A selection menu naming a type that is not the rows' ids.
        case wrongType
        /// A selection menu that builds nothing for empty space.
        case emptyForNone
        /// A list with a selection menu, a section header, and rows whose
        /// views carry a `.contextMenu`.
        case list
        /// A table whose selection menu builds nothing, kept for its primary
        /// action — the shape that replaced `onRowActivate`.
        case emptyMenuTable
        /// The same, on a list.
        case emptyMenuList
        /// A list with no selection binding, a selection menu around it and a
        /// `.contextMenu` around that.
        case selectionlessList
        /// A table with no selection binding and a selection menu around it.
        case selectionlessTable
        /// The selection-menu table, inside a view with a `.contextMenu`.
        case selectionMenuInMenu
    }
}

private struct Item: Identifiable, Equatable {
    let id: Int
    var name: String { "item\(id)" }
}

private struct RowsApp: App {
    let rows: Rows?

    init() { rows = nil }

    init(_ rows: Rows) { self.rows = rows }

    var body: some Scene {
        WindowGroup {
            if let rows { RowsPage(rows: rows) }
        }
    }
}

private struct RowsPage: View {
    let rows: Rows
    private let items = (1...4).map(Item.init)

    var body: some View {
        switch rows.shape {
        case .selectionMenu: selectionMenuTable
        case .rowMenus: rowMenuTable.contextMenu { Button("outer") { rows.ran.append("outer") } }
        case .both: bothTable
        case .wrongType: wrongTypeTable.contextMenu { Button("outer") { rows.ran.append("outer") } }
        case .emptyForNone: emptyForNoneTable
        case .list: list
        case .emptyMenuTable: emptyMenuTable
        case .emptyMenuList: emptyMenuList
        case .selectionlessList: selectionlessList.contextMenu { Button("outer") { rows.ran.append("outer") } }
        case .selectionlessTable: selectionlessTable
        case .selectionMenuInMenu:
            selectionMenuTable.contextMenu { Button("outer") { rows.ran.append("outer") } }
        }
    }

    private func menu(_ ids: Set<Int>) -> some View {
        Button("sel \(ids.sorted())") { rows.ran.append("sel \(ids.sorted())") }
    }

    private var selectionMenuTable: some View {
        Table(items, selection: Bindable(rows).selection) {
            TableColumn("Name", value: \.name)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            menu(ids)
        } primaryAction: { ids in
            rows.opened.append(ids.sorted())
        }
        .frame(height: 9)
    }

    private var rowMenuTable: some View {
        Table(of: Item.self, selection: Bindable(rows).selection) {
            TableColumn("Name", value: \.name)
        } rows: {
            ForEach(items) { item in
                if item.id <= 2 {
                    TableRow(item).contextMenu { Button("row \(item.id)") { rows.ran.append("row \(item.id)") } }
                } else {
                    TableRow(item)
                }
            }
        }
        .frame(height: 9)
    }

    private var bothTable: some View {
        Table(of: Item.self, selection: Bindable(rows).selection) {
            TableColumn("Name", value: \.name)
            TableColumn("View") { item in
                Text(verbatim: "cell\(item.id)").contextMenu { Button("cellmenu") {} }
            }
        } rows: {
            ForEach(items) { item in
                TableRow(item).contextMenu { Button("row \(item.id)") {} }
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in menu(ids) }
        .frame(height: 9)
    }

    private var wrongTypeTable: some View {
        Table(items, selection: Bindable(rows).selection) {
            TableColumn("Name", value: \.name)
            TableColumn("View") { item in
                Text(verbatim: "cell\(item.id)").contextMenu { Button("cellmenu \(item.id)") {} }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("wrong \(ids.count)") {}
        } primaryAction: { _ in
            rows.ran.append("wrong primary")
        }
        .frame(height: 9)
    }

    private var emptyForNoneTable: some View {
        Table(items, selection: Bindable(rows).selection) {
            TableColumn("Name", value: \.name)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if !ids.isEmpty { menu(ids) }
        }
        .frame(height: 9)
    }

    private var list: some View {
        List(selection: Bindable(rows).selection) {
            Section("Header") {
                ForEach(items) { item in
                    Text(item.name).contextMenu { Button("view \(item.id)") {} }
                }
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            menu(ids)
        } primaryAction: { ids in
            rows.opened.append(ids.sorted())
        }
        .frame(height: 10)
    }

    private var emptyMenuTable: some View {
        Table(items, selection: Bindable(rows).selection) {
            TableColumn("Name", value: \.name)
        }
        .contextMenu(forSelectionType: Int.self) { _ in
        } primaryAction: { ids in
            rows.opened.append(ids.sorted())
        }
        .frame(height: 9)
    }

    private var emptyMenuList: some View {
        List(selection: Bindable(rows).selection) {
            ForEach(items) { item in Text(item.name) }
        }
        .contextMenu(forSelectionType: Int.self) { _ in
        } primaryAction: { ids in
            rows.opened.append(ids.sorted())
        }
        .frame(height: 9)
    }

    private var selectionlessList: some View {
        List(items) { item in
            if item.id <= 2 {
                Text(item.name).contextMenu { Button("view \(item.id)") { rows.ran.append("view \(item.id)") } }
            } else {
                Text(item.name)
            }
        }
            .contextMenu(forSelectionType: Int.self) { ids in
                menu(ids)
            } primaryAction: { ids in
                rows.opened.append(ids.sorted())
            }
            .frame(height: 9)
    }

    private var selectionlessTable: some View {
        Table(items) {
            TableColumn("Name", value: \.name)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            menu(ids)
        } primaryAction: { ids in
            rows.opened.append(ids.sorted())
        }
        .frame(height: 9)
    }
}

@MainActor
private final class Harness {
    let rows = Rows()
    let app: HeadlessApp<RowsApp>
    private var now: Int64 = 0

    init(_ shape: Rows.Shape) {
        rows.shape = shape
        app = HeadlessApp(RowsApp(rows), width: 40, height: 16)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func position(of text: String) throws -> (x: Int, y: Int) {
        let y = try #require(app.screen.firstIndex { $0.stripped.contains(text) }, "\(text) is not drawn")
        let line = app.screen[y].stripped
        let range = try #require(line.range(of: text))
        return (line.distance(from: line.startIndex, to: range.lowerBound), y)
    }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    var screen: String { app.screen.map(\.stripped).joined(separator: "\n") }

    /// A secondary click — the right button, or Ctrl with the left.
    func secondaryClick(_ point: (x: Int, y: Int), ctrl: Bool = false) {
        let button: MouseButton = ctrl ? .left : .right
        app.send(MouseEvent(button: button, phase: .pressed, x: point.x, y: point.y, ctrl: ctrl))
        app.send(MouseEvent(button: button, phase: .released, x: point.x, y: point.y, ctrl: ctrl))
        frame()
    }

    /// A Ctrl-click with a frame between its press and its release — the
    /// frame on which a menu that built nothing closes. `ctrlHeldOnRelease`
    /// false lets Ctrl go before the button.
    func ctrlClickAcrossAFrame(_ point: (x: Int, y: Int), ctrlHeldOnRelease: Bool = true) {
        app.send(MouseEvent(button: .left, phase: .pressed, x: point.x, y: point.y, ctrl: true))
        frame()
        app.send(
            MouseEvent(button: .left, phase: .released, x: point.x, y: point.y, ctrl: ctrlHeldOnRelease))
        frame()
    }

    func key(_ event: KeyEvent) {
        app.send(event)
        frame()
    }

    /// Closes whatever menu is up.
    func escape() { key(KeyEvent(key: .escape)) }
}

@MainActor
@Suite("Context menus on a table's and a list's rows")
struct RowContextMenuTests {
    @Test("A right-click on a selected row acts on the selection, on another row on that row, on empty space on none")
    func selectionMenuSets() throws {
        let harness = Harness(.selectionMenu)
        harness.secondaryClick(try harness.position(of: "item2"))
        #expect(harness.shows("sel [2, 3]"), "\(harness.screen)")
        harness.escape()
        harness.secondaryClick(try harness.position(of: "item1"))
        #expect(harness.shows("sel [1]"), "\(harness.screen)")
        harness.escape()
        let below = try harness.position(of: "item4")
        harness.secondaryClick((below.x, below.y + 2))
        #expect(harness.shows("sel []"), "\(harness.screen)")
        harness.escape()
        #expect(harness.rows.selection == [2, 3], "a menu click changed the selection")
    }

    @Test("Choosing an item runs it; a Ctrl-click opens the menu as a right-click does")
    func chooseAndCtrlClick() throws {
        let harness = Harness(.selectionMenu)
        harness.secondaryClick(try harness.position(of: "item4"), ctrl: true)
        #expect(harness.shows("sel [4]"), "\(harness.screen)")
        #expect(harness.rows.selection == [2, 3], "the Ctrl-click toggled a row instead")
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.rows.ran == ["sel [4]"])
        #expect(!harness.shows("sel [4]"))
    }

    @Test("Shift+F10, and the Menu key, open the menu on the cursor row by the same rule")
    func keyboardOpens() throws {
        // The cursor starts on row 0 (item1), which is not selected.
        let first = Harness(.selectionMenu)
        first.key(KeyEvent(key: .f10, shift: true))
        #expect(first.shows("sel [1]"), "\(first.screen)")
        let second = Harness(.selectionMenu)
        second.key(KeyEvent(key: .down))
        second.key(KeyEvent(key: .f10, shift: true))
        #expect(second.shows("sel [2, 3]"), "\(second.screen)")
        // The Menu key, where the terminal reports it, is the same key; on a
        // list too.
        let third = Harness(.selectionMenu)
        third.key(KeyEvent(key: .menu))
        #expect(third.shows("sel [1]"), "\(third.screen)")
        let list = Harness(.list)
        list.key(KeyEvent(key: .down))
        list.key(KeyEvent(key: .menu))
        #expect(list.shows("sel ["), "\(list.screen)")
    }

    @Test("primaryAction: Return on a selected cursor row acts on the selection, on another on that row; a double-click on its row")
    func primaryAction() throws {
        let harness = Harness(.selectionMenu)
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.rows.opened == [[2, 3]])
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.rows.opened == [[2, 3], [4]])
        #expect(harness.rows.selection == [2, 3], "Return selected as well as activating")
        let row = try harness.position(of: "item1")
        for _ in 0..<2 {
            harness.app.send(MouseEvent(button: .left, phase: .pressed, x: row.x, y: row.y))
            harness.app.send(MouseEvent(button: .left, phase: .released, x: row.x, y: row.y))
            harness.frame()
        }
        #expect(harness.rows.opened == [[2, 3], [4], [1]], "\(harness.rows.opened)")
    }

    @Test("A row's own menu opens on it; a row without one leaves the click to the menu around the table")
    func rowMenus() throws {
        let harness = Harness(.rowMenus)
        harness.secondaryClick(try harness.position(of: "item2"))
        #expect(harness.shows("row 2"), "\(harness.screen)")
        harness.escape()
        harness.secondaryClick(try harness.position(of: "item3"))
        #expect(harness.shows("outer"), "\(harness.screen)")
        #expect(!harness.shows("row 3"))
        harness.escape()
        // A click puts the cursor on item1 (and the focus on the table), whose
        // own menu Shift+F10 opens; a row without one opens nothing.
        let first = try harness.position(of: "item1")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: first.x, y: first.y))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: first.x, y: first.y))
        harness.frame()
        harness.key(KeyEvent(key: .f10, shift: true))
        #expect(harness.shows("row 1"), "Shift+F10 did not open the cursor row's menu:\n\(harness.screen)")
        harness.escape()
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .f10, shift: true))
        #expect(!harness.shows("row 3"), "\(harness.screen)")
    }

    @Test("The selection menu wins over a row's own menu and a cell view's")
    func selectionMenuWins() throws {
        let harness = Harness(.both)
        harness.secondaryClick(try harness.position(of: "cell1"))
        #expect(harness.shows("sel [1]"), "\(harness.screen)")
        #expect(!harness.shows("cellmenu") && !harness.shows("row 1"))
        harness.escape()
        harness.secondaryClick(try harness.position(of: "item3"))
        #expect(harness.shows("sel [2, 3]"), "\(harness.screen)")
    }

    @Test("A selection menu for another item type never activates")
    func wrongType() throws {
        let harness = Harness(.wrongType)
        harness.secondaryClick(try harness.position(of: "item1"))
        #expect(!harness.shows("wrong"), "\(harness.screen)")
        #expect(harness.shows("outer"), "the click did not reach the menu around the table")
        harness.escape()
        // The menu that never activates leaves a cell view's own menu be.
        harness.secondaryClick(try harness.position(of: "cell2"))
        #expect(harness.shows("cellmenu 2"), "\(harness.screen)")
        harness.escape()
        harness.key(KeyEvent(key: .enter))
        #expect(!harness.rows.ran.contains("wrong primary"))
    }

    @Test("A menu that builds nothing does not open, and leaves the keyboard alone")
    func emptyMenu() throws {
        let harness = Harness(.emptyForNone)
        let below = try harness.position(of: "item4")
        harness.secondaryClick((below.x, below.y + 2))
        harness.frame()
        #expect(!harness.shows("sel ["), "\(harness.screen)")
        // The table still takes its keys: no menu section holds the keyboard.
        harness.key(KeyEvent(key: .f10, shift: true))
        #expect(harness.shows("sel [1]"), "\(harness.screen)")
    }

    @Test("A list's selection menu: the same rule, a header is empty space, and a row view's menu yields")
    func listSelectionMenu() throws {
        let harness = Harness(.list)
        harness.secondaryClick(try harness.position(of: "item3"))
        #expect(harness.shows("sel [2, 3]"), "\(harness.screen)")
        #expect(!harness.shows("view 3"))
        harness.escape()
        harness.secondaryClick(try harness.position(of: "item4"))
        #expect(harness.shows("sel [4]"), "\(harness.screen)")
        harness.escape()
        harness.secondaryClick(try harness.position(of: "Header"))
        #expect(harness.shows("sel []"), "\(harness.screen)")
        harness.escape()
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.rows.opened.count == 1, "\(harness.rows.opened)")
    }

    @Test(
        "A Ctrl-click on a menu that builds nothing is spent, though the menu closed before the release",
        arguments: [false, true])
    func emptyMenuCtrlClickIsSpent(onList: Bool) throws {
        let harness = Harness(onList ? .emptyMenuList : .emptyMenuTable)
        harness.ctrlClickAcrossAFrame(try harness.position(of: "item1"))
        #expect(harness.rows.selection == [2, 3], "the release toggled the row:\n\(harness.screen)")
        harness.ctrlClickAcrossAFrame(try harness.position(of: "item4"), ctrlHeldOnRelease: false)
        #expect(harness.rows.selection == [2, 3], "the release selected the row:\n\(harness.screen)")
        // An Option-click still toggles: the menu has the Ctrl-click only.
        let row = try harness.position(of: "item1")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: row.x, y: row.y, meta: true))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: row.x, y: row.y, meta: true))
        harness.frame()
        #expect(harness.rows.selection == [1, 2, 3], "\(harness.screen)")
    }

    @Test("A list with no selection binding takes no selection menu and no primary action, as SwiftUI's")
    func selectionlessListTakesNoMenu() throws {
        let harness = Harness(.selectionlessList)
        harness.secondaryClick(try harness.position(of: "item3"))
        #expect(!harness.shows("sel ["), "\(harness.screen)")
        #expect(harness.shows("outer"), "the click did not go on to the menu around the list:\n\(harness.screen)")
        harness.escape()
        // A row view's own menu is its own again.
        harness.secondaryClick(try harness.position(of: "item2"))
        #expect(harness.shows("view 2"), "\(harness.screen)")
        #expect(!harness.shows("sel ["))
        harness.escape()
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        let row = try harness.position(of: "item3")
        for _ in 0..<2 {
            harness.app.send(MouseEvent(button: .left, phase: .pressed, x: row.x, y: row.y))
            harness.app.send(MouseEvent(button: .left, phase: .released, x: row.x, y: row.y))
            harness.frame()
        }
        #expect(harness.rows.opened.isEmpty, "\(harness.rows.opened)")
    }

    @Test("A table with no selection binding takes the menu and the primary action, per row: Return on the cursor row")
    func selectionlessTableActsPerRow() throws {
        // B-D4T-1: where macOS's Return does nothing, TUIkit's acts on the
        // cursor row; a double-click and a right-click act on the row clicked,
        // as macOS's do.
        let harness = Harness(.selectionlessTable)
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.rows.opened == [[2]], "\(harness.rows.opened)")
        let row = try harness.position(of: "item3")
        for _ in 0..<2 {
            harness.app.send(MouseEvent(button: .left, phase: .pressed, x: row.x, y: row.y))
            harness.app.send(MouseEvent(button: .left, phase: .released, x: row.x, y: row.y))
            harness.frame()
        }
        #expect(harness.rows.opened == [[2], [3]], "\(harness.rows.opened)")
        harness.secondaryClick(try harness.position(of: "item4"))
        #expect(harness.shows("sel [4]"), "\(harness.screen)")
    }

    @Test("A right-click on a table's column header opens no row menu: it goes on to the menu around the table")
    func headerIsNotEmptySpace() throws {
        let harness = Harness(.selectionMenuInMenu)
        harness.secondaryClick(try harness.position(of: "Name"))
        #expect(!harness.shows("sel ["), "\(harness.screen)")
        #expect(harness.shows("outer"), "\(harness.screen)")
        harness.escape()
        // Below the rows is still the table's empty space.
        let below = try harness.position(of: "item4")
        harness.secondaryClick((below.x, below.y + 2))
        #expect(harness.shows("sel []"), "\(harness.screen)")
    }

    @Test("Shift+F10 on a list hangs the menu under the cursor row")
    func listKeyboardMenuHangsUnderTheCursorRow() throws {
        let harness = Harness(.list)
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .down))
        let row = try harness.position(of: "item3")
        harness.key(KeyEvent(key: .f10, shift: true))
        let menu = try harness.position(of: "sel [")
        #expect(menu.y > row.y && menu.y <= row.y + 2, "\(harness.screen)")
    }
}
