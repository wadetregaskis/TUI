//  🖥️ TUI — A Terminal UI framework for Swift
//  HoverFocusListTests.swift
//
//  With the focus following the pointer, a `List`, `Table` or outline under
//  the pointer takes the focus, and its cursor row follows the row the pointer
//  moves onto — never its selection, and never a row the content moved under a
//  pointer at rest (owner ruling HOVER-FOCUS b, 2026-11-10).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("With the focus following the pointer, a list's cursor row follows it")
struct HoverFocusListTests {
    struct Item: Identifiable, Hashable {
        let id: Int
        let name: String
        var children: [Self]?
    }

    enum Kind: String, CaseIterable, Sendable {
        case list, sectioned, outline, table
    }

    private static let names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa"]
    private static var items: [Item] { names.enumerated().map { Item(id: $0.offset, name: $0.element) } }

    private struct Page: View {
        let kind: Kind
        var count = 3
        @State private var selection: Int?

        var body: some View {
            VStack(alignment: .leading) {
                Button("Go") {}.focusID("go")
                Text("picked \(selection.map { id in HoverFocusListTests.items.first { $0.id == id }?.name ?? "Letters" } ?? "none")")
                rows.frame(height: 7)
                Spacer()
            }
        }

        private var shown: [Item] { Array(HoverFocusListTests.items.prefix(count)) }

        @ViewBuilder private var rows: some View {
            switch kind {
            case .list:
                List(shown, selection: $selection) { Text($0.name) }.focusID("rows")
            case .sectioned:
                List(selection: $selection) {
                    Section("Greek") {
                        ForEach(shown) { Text($0.name).tag($0.id) }
                    }
                }
                .focusID("rows")
            case .outline:
                List([Item(id: 99, name: "Letters", children: shown)], children: \.children, selection: $selection) {
                    Text($0.name)
                }
                .focusID("rows")
            case .table:
                Table(shown, selection: $selection) { TableColumn("Name", value: \.name) }.focusID("rows")
            }
        }
    }

    private struct PageApp: App {
        let kind: Kind
        let follows: Bool
        var count = 3
        init() { (kind, follows) = (.list, true) }
        init(kind: Kind, follows: Bool, count: Int = 3) { (self.kind, self.follows, self.count) = (kind, follows, count) }

        var body: some Scene {
            WindowGroup { Page(kind: kind, count: count) }
                .focusFollowsPointer(follows)
        }
    }

    private func launched(_ kind: Kind, follows: Bool, count: Int = 3) -> TestApp {
        let app = TestApp(PageApp(kind: kind, follows: follows, count: count), width: 40, height: 14)
        app.advance(by: .milliseconds(20))
        if kind == .outline {
            // Open the one branch, from the keyboard, and give the focus back.
            app.press(.tab)
            app.press(.right)
            app.press(.tab, modifiers: .shift)
        }
        return app
    }

    /// The cell `offset` columns into `text`, where it first shows.
    private func cell(_ app: TestApp, _ text: String, offset: Int = 0) throws -> CellPoint {
        let lines = app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains(text) }, "\(text) is on screen")
        let start = try #require(lines[y].range(of: text)).lowerBound
        return CellPoint(x: lines[y][..<start].count + offset, y: y)
    }

    private func picked(_ app: TestApp) -> String? {
        app.screen.lines.lazy.compactMap { line in
            line.range(of: "picked ").map { String(line[$0.upperBound...]) }
        }
        .first?.trimmingCharacters(in: .whitespaces)
    }

    @Test("A move onto a row focuses the list and puts its cursor there, the selection unmoved", arguments: Kind.allCases)
    func cursorFollows(_ kind: Kind) throws {
        let app = launched(kind, follows: true)
        #expect(app.focusedID == "go")
        app.hover(at: try cell(app, "Beta"))
        #expect(app.focusedID == "rows", "\(kind): the focus is on \(app.focusedID ?? "nothing")")
        #expect(picked(app) == "none", "\(kind): the pointer chose a row")
        app.hover(at: try cell(app, "Gamma"))
        #expect(picked(app) == "none")
        app.press(.space)
        #expect(picked(app) == "Gamma", "\(kind): the keys acted on \(picked(app) ?? "nothing"), not the row under the pointer")
    }

    @Test("Off, the pointer moves neither the focus nor the cursor", arguments: Kind.allCases)
    func offMovesNothing(_ kind: Kind) throws {
        let app = launched(kind, follows: false)
        app.hover(at: try cell(app, "Gamma"))
        #expect(app.focusedID == "go")
        app.press(.tab)
        #expect(app.focusedID == "rows")
        app.hover(at: try cell(app, "Gamma", offset: 1))
        app.press(.space)
        #expect(picked(app) != "Gamma", "\(kind): the pointer moved the cursor")
    }

    @Test("Rows moving under a pointer at rest leave the cursor where it was; the next move takes it")
    func stillPointerKeepsCursor() throws {
        let app = launched(.list, follows: true, count: 10)
        let beta = try cell(app, "Beta")
        app.hover(at: beta)
        #expect(app.focusedID == "rows")
        app.scroll(.down, by: 2, at: beta)
        #expect(!app.screen.lines.contains { $0.contains("Alpha") }, "the wheel scrolled the list")
        app.press(.space)
        #expect(picked(app) == "Beta", "the rows moved under a still pointer, and the cursor went with them")
        app.hover(at: CellPoint(x: beta.x + 1, y: beta.y))
        let under = try #require(
            Self.names.first { name in app.screen.lines[beta.y].contains(name) }, "a row is under the pointer")
        app.press(.space)
        #expect(picked(app) == under, "the pointer moved, and the cursor did not follow it")
    }

    private struct SheetApp: App {
        var body: some Scene {
            WindowGroup {
                Page(kind: .list)
                    .sheet(isPresented: .constant(true)) {
                        Button("Sheet") {}.focusID("sheet")
                    }
            }
            .focusFollowsPointer()
        }
    }

    @Test("Behind a sheet, the pointer moves nothing in the list")
    func behindSheet() throws {
        let app = TestApp(SheetApp(), width: 40, height: 14)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "sheet")
        app.hover(at: try cell(app, "Gamma"))
        #expect(app.focusedID == "sheet")
    }

    private struct DisabledApp: App {
        var body: some Scene {
            WindowGroup { Page(kind: .list).disabled(true) }
                .focusFollowsPointer()
        }
    }

    @Test("A disabled list takes nothing")
    func disabledList() throws {
        let app = TestApp(DisabledApp(), width: 40, height: 14)
        app.advance(by: .milliseconds(20))
        let before = app.focusedID
        app.hover(at: try cell(app, "Gamma"))
        #expect(app.focusedID == before)
        #expect(app.focusedID != "rows")
    }
}
