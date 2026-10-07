//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectionRowGestureTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What a press other than a plain one does on a row's selectable text: a
/// Control-click, the secondary click where a terminal keeps the right button.
@MainActor
@Suite("textSelection(_:) on rows: Control-clicks")
struct TextSelectionRowGestureTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    struct Item: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    static let items = (0..<5).map { Item(id: $0, name: "name \($0) here") }

    enum Shape {
        /// A List whose rows' own Text is selectable, with a selection menu.
        case listWithMenu
        /// The same List with no menu.
        case listWithoutMenu
        /// A Table inside `.textSelection(.enabled)`, with a selection menu.
        case tableWithMenu
        /// A scroll view of text under `.contextMenu`.
        case scrollViewInMenu
    }

    struct Page: View {
        let shape: Shape
        let selection: Box<Int?>
        var body: some View {
            let binding = Binding(get: { selection.value }, set: { selection.value = $0 })
            switch shape {
            case .listWithMenu:
                AnyView(
                    List(TextSelectionRowGestureTests.items, selection: binding) { item in
                        Text(item.name).textSelection(.enabled)
                    }
                    .contextMenu(forSelectionType: Int.self) { _ in Button("Row Action") {} }
                    .frame(height: 9))
            case .listWithoutMenu:
                AnyView(
                    List(TextSelectionRowGestureTests.items, selection: binding) { item in
                        Text(item.name).textSelection(.enabled)
                    }
                    .frame(height: 9))
            case .tableWithMenu:
                AnyView(
                    Table(TextSelectionRowGestureTests.items, selection: binding) {
                        TableColumn("Name", value: \.name)
                    }
                    .textSelection(.enabled)
                    .contextMenu(forSelectionType: Int.self) { _ in Button("Row Action") {} }
                    .frame(height: 9))
            case .scrollViewInMenu:
                AnyView(
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(TextSelectionRowGestureTests.items) { Text($0.name) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 6)
                    .contextMenu { Button("Page Action") {} })
            }
        }
    }

    struct PageApp: App {
        let page: Page
        init() { page = Page(shape: .listWithMenu, selection: Box(nil)) }
        init(page: Page) { self.page = page }
        var body: some Scene {
            WindowGroup { page }.mouseSupport(.full)
        }
    }

    @MainActor
    final class Harness {
        let app: HeadlessApp<PageApp>
        let page: Page
        var now: Int64 = 0

        init(_ shape: Shape) {
            page = Page(shape: shape, selection: Box(nil))
            app = HeadlessApp(PageApp(page: page), width: 40, height: 14)
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

        func click(_ point: (x: Int, y: Int), button: MouseButton = .left, ctrl: Bool = false) {
            app.send(MouseEvent(button: button, phase: .pressed, x: point.x, y: point.y, ctrl: ctrl))
            frame()
            app.send(MouseEvent(button: button, phase: .released, x: point.x, y: point.y, ctrl: ctrl))
            frame()
        }

        func escape() {
            app.send(KeyEvent(key: .escape))
            frame()
        }
    }

    /// Owner, 2026-10-06: a Control-click on a row opens its menu, if it has
    /// one. On the row's text it started a selection instead.
    @Test("A Control-click on a List row's text opens the row's menu, as a right-click does")
    func controlClickOnListRowTextOpensTheMenu() throws {
        let harness = Harness(.listWithMenu)
        let name = try harness.position(of: "name 2")
        harness.click((name.x + 1, name.y), button: .right)
        try #require(harness.shows("Row Action"), "precondition: a right-click opens it")
        harness.escape()
        try #require(!harness.shows("Row Action"))
        harness.click((name.x + 1, name.y), ctrl: true)
        #expect(harness.shows("Row Action"))
        #expect(harness.app.services.screenSelection.current == nil)
    }

    @Test("A Control-click on a Table row's text opens the row's menu")
    func controlClickOnTableRowTextOpensTheMenu() throws {
        let harness = Harness(.tableWithMenu)
        let name = try harness.position(of: "name 3")
        harness.click((name.x + 1, name.y), ctrl: true)
        #expect(harness.shows("Row Action"))
        #expect(harness.app.services.screenSelection.current == nil)
    }

    /// With no menu, the Control-click goes on to the row, which takes it as
    /// it takes one on its blank cells.
    @Test("With no menu, a Control-click on a row's text is the row's, as on its blank cells")
    func controlClickWithoutAMenuFallsToTheRow() throws {
        let onText = Harness(.listWithoutMenu)
        let name = try onText.position(of: "name 2")
        onText.click((name.x + 1, name.y), ctrl: true)
        let onBlank = Harness(.listWithoutMenu)
        onBlank.click((name.x + 30, name.y), ctrl: true)
        try #require(onBlank.page.selection.value == 2, "precondition: the row takes a Control-click on blank cells")
        #expect(onText.page.selection.value == onBlank.page.selection.value)
        #expect(onText.app.services.screenSelection.current == nil)
    }

    /// A scroll view's background takes a press only for its click, and held
    /// a Control-click for it: the menu around never saw it.
    @Test("A Control-click on a scroll view's text opens the menu around it, as a right-click does")
    func controlClickReachesAMenuAroundAScrollView() throws {
        let harness = Harness(.scrollViewInMenu)
        let name = try harness.position(of: "name 1")
        harness.click((name.x + 1, name.y), button: .right)
        try #require(harness.shows("Page Action"), "precondition: a right-click opens it")
        harness.escape()
        try #require(!harness.shows("Page Action"))
        harness.click((name.x + 1, name.y), ctrl: true)
        #expect(harness.shows("Page Action"))
    }
}

/// A drag that starts on a draggable or movable row's selectable text.
@MainActor
@Suite("textSelection(_:) on rows: drags")
struct TextSelectionRowDragTests {
    typealias Item = TextSelectionRowGestureTests.Item
    static let items = TextSelectionRowGestureTests.items

    enum Shape {
        /// A List whose rows' selectable Text is `.draggable`.
        case draggableList
        /// The same rows with no `.textSelection`: the control.
        case draggableListUnselectable
        /// A List whose rows' selectable Text vends an item provider.
        case itemProviderList
        /// A Table whose rows are `TableRow.draggable`, its cell's Text selectable.
        case draggableTable
        /// A List of a ForEach with `.onMove`, its rows' Text selectable.
        case movableList
        /// Draggable tabs inside `.textSelection(.enabled)`: a title is chrome.
        case draggableTabInScope(TabInteractionsLook)
        /// A `.draggable` view holding a Button, inside `.textSelection(.enabled)`.
        case draggableButtonInScope
    }

    struct Page: View {
        let shape: Shape
        let moves: TextSelectionRowGestureTests.Box<[String]>
        var body: some View {
            switch shape {
            case .draggableList:
                AnyView(
                    List(TextSelectionRowDragTests.items) { item in
                        Text(item.name).textSelection(.enabled).draggable(item.name)
                    }
                    .frame(height: 9))
            case .draggableListUnselectable:
                AnyView(
                    List(TextSelectionRowDragTests.items) { item in
                        Text(item.name).draggable(item.name)
                    }
                    .frame(height: 9))
            case .itemProviderList:
                AnyView(
                    List(TextSelectionRowDragTests.items) { item in
                        Text(item.name).textSelection(.enabled)
                            .itemProvider { NSItemProvider(object: item.name as NSString) }
                    }
                    .frame(height: 9))
            case .draggableTable:
                AnyView(
                    Table(of: Item.self) {
                        TableColumn("Name") { item in Text(item.name).textSelection(.enabled) }
                    } rows: {
                        ForEach(TextSelectionRowDragTests.items) { item in TableRow(item).draggable(item.name) }
                    }
                    .frame(height: 9))
            case .movableList:
                AnyView(
                    List {
                        ForEach(TextSelectionRowDragTests.items) { item in
                            Text(item.name).textSelection(.enabled)
                        }
                        .onMove { from, to in moves.value.append("\(Array(from)) -> \(to)") }
                    }
                    .frame(height: 9))
            case .draggableTabInScope(let look):
                AnyView(
                    TextSelectionRowDragTests.tabs(look)
                        .textSelection(.enabled))
            case .draggableButtonInScope:
                AnyView(
                    VStack(alignment: .leading) {
                        HStack {
                            Button("name 1") { moves.value.append("clicked") }
                            Text("tail")
                        }
                        .draggable("dragged")
                    }
                    .textSelection(.enabled))
            }
        }
    }

    /// Two tabs, the first draggable, in `look`.
    @ViewBuilder
    static func tabs(_ look: TabInteractionsLook) -> some View {
        let view = TabView {
            Tab("name 1", systemImage: "star") { Text("first") }.draggable("name 1")
            Tab("Two", systemImage: "star") { Text("second") }
        }
        switch look {
        case .compact: view
        case .bordered: view.tabViewStyle(.bordered)
        case .sidebar: view.tabViewStyle(.sidebarAdaptable)
        }
    }

    struct PageApp: App {
        let page: Page
        init() { page = Page(shape: .draggableList, moves: .init([])) }
        init(page: Page) { self.page = page }
        var body: some Scene {
            WindowGroup { page }.mouseSupport(.full)
        }
    }

    /// What a drag from `from` to `to` did: the text it selected, whether a
    /// drag session ran while it moved, and the moves the list made.
    struct Outcome {
        var selected: String?
        var dragged: Bool
        var moves: [String]
    }

    func drag(_ shape: Shape, onText: Bool) throws -> Outcome {
        let page = Page(shape: shape, moves: .init([]))
        let app = HeadlessApp(PageApp(page: page), width: 40, height: 14)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        let y = try #require(app.screen.firstIndex { $0.stripped.contains("name 1") })
        let line = app.screen[y].stripped
        // In cells: a tab's symbol before its title is two.
        let start = String(line[..<(try #require(line.range(of: "name 1")).lowerBound)]).strippedLength
        let x = onText ? start : start + 25
        var dragged = false
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        frame()
        for step in 1...3 {
            app.send(MouseEvent(button: .left, phase: .dragged, x: x + step, y: y + (step == 3 ? 2 : 0)))
            frame()
            dragged = dragged || app.services.dragAndDropSession.active != nil
        }
        app.send(MouseEvent(button: .left, phase: .released, x: x + 3, y: y + 2))
        frame()
        return Outcome(
            selected: app.services.screenSelection.current?.text, dragged: dragged, moves: page.moves.value)
    }

    /// Measured on macOS 15.8.1 (decisions D4X, B-D4X-7): a drag that starts
    /// on a draggable row's selectable text selects the text, and the row is
    /// not dragged. TUIkit's drag handle took the press ahead of the text.
    @Test("A drag from a draggable List row's selectable text selects it and drags no row")
    func draggableListRowText() throws {
        let outcome = try drag(.draggableList, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    @Test("A drag from an item-provider List row's selectable text selects it and drags no row")
    func itemProviderListRowText() throws {
        let outcome = try drag(.itemProviderList, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    @Test("A drag from a draggable Table row's selectable cell text selects it and drags no row")
    func draggableTableRowText() throws {
        let outcome = try drag(.draggableTable, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    @Test("A drag from a movable List row's selectable text selects it and moves no row")
    func movableListRowText() throws {
        let outcome = try drag(.movableList, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
        #expect(outcome.moves.isEmpty)
    }

    /// Review round 1 of the follow-ups: under an enabled scope around a
    /// tab view, a press on a draggable tab's title passed the handle over,
    /// and the tab strip took it — the tab dragged only from its padding. A
    /// title is chrome, not text the handle's content made selectable.
    @Test(
        "Under an enabled scope a draggable tab still drags from its title",
        arguments: TabInteractionsLook.allCases)
    func draggableTabTitle(_ look: TabInteractionsLook) throws {
        let outcome = try drag(.draggableTabInScope(look), onText: true)
        #expect(outcome.dragged)
        #expect(outcome.selected == nil)
    }

    /// A sidebar's tab titles are chrome too: under an enabled scope around
    /// the tab view its list kept them for a selection, so a click on one
    /// selected no tab.
    @Test("Under an enabled scope a click on a sidebar tab's title selects the tab")
    func sidebarTabTitleClick() throws {
        let page = Page(shape: .draggableTabInScope(.sidebar), moves: .init([]))
        let app = HeadlessApp(PageApp(page: page), width: 40, height: 14)
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        try #require(app.screen.contains { $0.stripped.contains("first") })
        let y = try #require(app.screen.firstIndex { $0.stripped.contains("Two") })
        let line = app.screen[y].stripped
        let x = String(line[..<(try #require(line.range(of: "Two")).lowerBound)]).strippedLength
        app.send(MouseEvent(button: .left, phase: .pressed, x: x + 1, y: y))
        app.frame(atNanos: 50_000_001)
        app.send(MouseEvent(button: .left, phase: .released, x: x + 1, y: y))
        app.frame(atNanos: 66_666_668)
        #expect(app.screen.contains { $0.stripped.contains("second") })
        #expect(app.services.screenSelection.current == nil)
    }

    /// The same for a control's label inside a `.draggable` view: the scope
    /// around them makes neither selectable, and the view drags from the
    /// label as it does with no scope.
    @Test("Under an enabled scope a draggable view still drags from a Button's label in it")
    func draggableViewFromButtonLabel() throws {
        let outcome = try drag(.draggableButtonInScope, onText: true)
        #expect(outcome.dragged)
        #expect(outcome.selected == nil)
        #expect(!outcome.moves.contains("clicked"))
    }

    /// The rows still drag from where there is no selectable text: their
    /// blank cells, and text no `.textSelection(.enabled)` made selectable.
    @Test("A draggable row still drags from its blank cells, and from text that is not selectable")
    func rowsStillDrag() throws {
        #expect(try drag(.draggableTable, onText: false).dragged)
        let unselectable = try drag(.draggableListUnselectable, onText: true)
        #expect(unselectable.dragged)
        #expect(unselectable.selected == nil)
    }
}
