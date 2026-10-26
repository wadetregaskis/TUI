//  🖥️ TUI — A Terminal UI framework for Swift
//  TextSelectionRowGestureTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

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
        #if canImport(UniformTypeIdentifiers)
            /// A List whose rows' selectable Text vends an item provider.
            case itemProviderList
        #endif
        /// A Table whose rows are `TableRow.draggable`, its cell's Text selectable.
        case draggableTable
        /// A List of a ForEach with `.onMove`, its rows' Text selectable.
        case movableList
        /// Draggable tabs inside `.textSelection(.enabled)`: a title is chrome.
        case draggableTabInScope(TabInteractionsLook)
        /// A `.draggable` view holding a Button, with `.textSelection(.enabled)`
        /// inside the handle or around it.
        case draggableButton(scopeInside: Bool)
        /// A `.draggable` Text with `.textSelection(.enabled)` inside the
        /// handle or around it.
        case draggableText(scopeInside: Bool)
        /// A scroll view of `.draggable` Text inside `.textSelection(.enabled)`.
        case draggableScrollViewInScope
        /// A List of `.draggable` Text inside `.textSelection(.enabled)`.
        case draggableListInScope
        /// A `.draggable` Text whose content has a context menu and a drop
        /// destination, inside `.textSelection(.enabled)`.
        case draggableTextWithMenuAndDropInScope
        /// A List whose `.draggable` rows hold a Button, inside
        /// `.textSelection(.enabled)`.
        case draggableListRowButtonInScope
        /// A `.draggable` Text with an `.onMouseEvent` closure that takes a
        /// left press or declines it, inside `.textSelection(.enabled)`.
        case draggableTextWithMouseEventInScope(takesLeftPress: Bool)
        /// A `.draggable` Text with an `onScrollGesture`, inside
        /// `.textSelection(.enabled)`.
        case draggableTextWithScrollGestureInScope
        /// A List whose `.draggable` rows hold a TextField, inside
        /// `.textSelection(.enabled)`.
        case draggableListRowFieldInScope
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
            #if canImport(UniformTypeIdentifiers)
                case .itemProviderList:
                    AnyView(
                        List(TextSelectionRowDragTests.items) { item in
                            Text(item.name).textSelection(.enabled)
                                .itemProvider { NSItemProvider(object: item.name as NSString) }
                        }
                        .frame(height: 9))
            #endif
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
            case .draggableButton(let scopeInside):
                let row = HStack {
                    Button("name 1") { moves.value.append("clicked") }
                    Text("tail")
                }
                if scopeInside {
                    AnyView(VStack(alignment: .leading) { row.textSelection(.enabled).draggable("dragged") })
                } else {
                    AnyView(VStack(alignment: .leading) { row.draggable("dragged") }.textSelection(.enabled))
                }
            case .draggableText(let scopeInside):
                let text = Text("name 1 is here")
                if scopeInside {
                    AnyView(VStack(alignment: .leading) { text.textSelection(.enabled).draggable("dragged") })
                } else {
                    AnyView(VStack(alignment: .leading) { text.draggable("dragged").textSelection(.enabled) })
                }
            case .draggableScrollViewInScope:
                AnyView(
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(TextSelectionRowDragTests.items) { item in Text(item.name).draggable(item.name) }
                        }
                    }
                    .textSelection(.enabled)
                    .frame(height: 9))
            case .draggableListInScope:
                AnyView(
                    List(TextSelectionRowDragTests.items) { item in Text(item.name).draggable(item.name) }
                        .textSelection(.enabled)
                        .frame(height: 9))
            case .draggableTextWithMenuAndDropInScope:
                AnyView(
                    VStack(alignment: .leading) {
                        Text("name 1 is here")
                            .contextMenu { Button("Act") {} }
                            .dropDestination(for: String.self) { _, _ in true }
                            .draggable("dragged")
                    }
                    .textSelection(.enabled))
            case .draggableListRowButtonInScope:
                AnyView(
                    List(TextSelectionRowDragTests.items) { item in
                        HStack {
                            Button(item.name) { moves.value.append("clicked") }
                            Text("tail")
                        }
                        .draggable(item.name)
                    }
                    .textSelection(.enabled)
                    .frame(height: 9))
            case .draggableTextWithMouseEventInScope(let takesLeftPress):
                AnyView(
                    VStack(alignment: .leading) {
                        Text("name 1 is here")
                            .onMouseEvent { event in
                                guard event.button == .left else { return event.button == .right }
                                if takesLeftPress, event.phase == .pressed { moves.value.append("pressed") }
                                return takesLeftPress
                            }
                            .draggable("dragged")
                    }
                    .textSelection(.enabled))
            case .draggableTextWithScrollGestureInScope:
                AnyView(
                    VStack(alignment: .leading) {
                        Text("name 1 is here").onScrollGesture { _ in }.draggable("dragged")
                    }
                    .textSelection(.enabled))
            case .draggableListRowFieldInScope:
                AnyView(
                    List(TextSelectionRowDragTests.items) { item in
                        TextField("Name", text: .constant(item.name)).draggable(item.name)
                    }
                    .textSelection(.enabled)
                    .frame(height: 9))
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
    /// not dragged. TUI's drag handle took the press ahead of the text.
    @Test("A drag from a draggable List row's selectable text selects it and drags no row")
    func draggableListRowText() throws {
        let outcome = try drag(.draggableList, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    #if canImport(UniformTypeIdentifiers)
        @Test("A drag from an item-provider List row's selectable text selects it and drags no row")
        func itemProviderListRowText() throws {
            let outcome = try drag(.itemProviderList, onText: true)
            #expect(outcome.selected?.hasPrefix("name 1") == true)
            #expect(!outcome.dragged)
        }
    #endif

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

    /// The same for a control's label inside a `.draggable` view: a scope
    /// makes it no selectable text, inside the handle or around it, and the
    /// view drags from the label as it does with no scope. (Review round 2
    /// of the follow-ups: with the scope inside, the handle stood aside and
    /// the Button took the press.)
    @Test(
        "Under an enabled scope a draggable view still drags from a Button's label in it",
        arguments: [false, true])
    func draggableViewFromButtonLabel(scopeInside: Bool) throws {
        let outcome = try drag(.draggableButton(scopeInside: scopeInside), onText: true)
        #expect(outcome.dragged)
        #expect(outcome.selected == nil)
        #expect(!outcome.moves.contains("clicked"))
    }

    /// `textSelection` is environment-like, so in SwiftUI the order of it and
    /// `.draggable` changes nothing about the Text's selectability; nor does
    /// the container. Review round 2 of the follow-ups: with the scope around
    /// the handle, or around a scroll view of draggable text, the drag
    /// dragged, where under a scope inside it or around a List it selected.
    @Test(
        "A drag on draggable selectable text selects it, whatever the modifiers' order or the container",
        arguments: [
            Shape.draggableText(scopeInside: true), .draggableText(scopeInside: false), .draggableScrollViewInScope,
            .draggableListInScope,
        ])
    func draggableTextSelectsInAnyOrder(_ shape: Shape) throws {
        let outcome = try drag(shape, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    /// A context menu's trigger and a drop zone take no plain left press:
    /// in front of them, as in front of nothing, the handle stands aside.
    @Test("A drag on draggable text selects it through a context menu and a drop destination")
    func draggableTextThroughPassiveRegions() throws {
        let outcome = try drag(.draggableTextWithMenuAndDropInScope, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    /// An app's `.onMouseEvent` closure says whether it takes a left press
    /// only when offered one. The review of the follow-ups' fixes: one that
    /// declines it (and `onScrollGesture`, built on one) was taken for a
    /// control, so the handle kept a press on its text and the view moved,
    /// where it selects as it does with the scope and no handle.
    @Test(
        "A drag on draggable selectable text selects it through an app's mouse handler that declines the press",
        arguments: [Shape.draggableTextWithMouseEventInScope(takesLeftPress: false), .draggableTextWithScrollGestureInScope])
    func draggableTextThroughDecliningHandler(_ shape: Shape) throws {
        let outcome = try drag(shape, onText: true)
        #expect(outcome.selected?.hasPrefix("name 1") == true)
        #expect(!outcome.dragged)
    }

    /// One that takes it has it, as under the scope with no handle: the
    /// handle stood aside for the text, and the closure was offered the
    /// press in turn.
    @Test("An app's mouse handler that takes the left press on draggable selectable text has it")
    func appHandlerTakesThePress() throws {
        let outcome = try drag(.draggableTextWithMouseEventInScope(takesLeftPress: true), onText: true)
        #expect(outcome.moves == ["pressed"])
        #expect(!outcome.dragged)
        #expect(outcome.selected == nil)
    }

    /// In a List, a draggable row drags from a Button's label in it, as a
    /// draggable view does, rather than the Button taking the press.
    @Test("Under an enabled scope a draggable List row drags from a Button's label in it")
    func draggableListRowFromButtonLabel() throws {
        let outcome = try drag(.draggableListRowButtonInScope, onText: true)
        #expect(outcome.dragged)
        #expect(outcome.selected == nil)
        #expect(!outcome.moves.contains("clicked"))
    }

    /// A field is a control, as a Button is: a draggable row drags from its
    /// text under a scope, as with none, rather than the field keeping the
    /// drag for a selection of its own.
    @Test("Under an enabled scope a draggable List row drags from a TextField's text in it")
    func draggableListRowFromField() throws {
        let outcome = try drag(.draggableListRowFieldInScope, onText: true)
        #expect(outcome.dragged)
        #expect(outcome.selected == nil)
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
