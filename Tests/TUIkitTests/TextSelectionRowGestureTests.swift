//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectionRowGestureTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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
