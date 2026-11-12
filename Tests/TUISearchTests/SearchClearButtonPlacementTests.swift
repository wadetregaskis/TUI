//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchClearButtonPlacementTests.swift
//
//  The search field's ✗ stood three cells past the field, where the row's
//  spacing puts it one: it is a plain button under `.focusable(false)`, and the
//  plain style kept two blank cells in front of its label for a focus bullet
//  the button could never show. The blank cells took clicks too, so a click
//  beside the field emptied it. Found by the window-chrome hunt, 2026-11-10.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUISearch
import TUITesting
@testable import TUITestSupport

/// The query a page searches, by reference so the binding a frame built reaches
/// it. Each app has its own, so suites running side by side share nothing.
private final class Query: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
    var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

/// The field in a toolbar's bottom bar, holding text from the start.
private struct BarApp: App {
    static let query = Query("abc")
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("BODY")
                .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                .searchable(text: Self.query.binding)
        }
    }
}

@MainActor
@Suite("The search field's ✗", .rendersEnglishUI)
struct SearchClearButtonPlacementTests {
    /// Where the field's trailing cap and the ✗ are on the row that holds them.
    private func columns(_ lines: [String]) throws -> (row: Int, cap: Int, cross: Int) {
        let row = try #require(lines.firstIndex { $0.contains("✗") }, "no ✗ on \(lines)")
        let cells = Array(lines[row])
        let cross = try #require(cells.firstIndex(of: "✗"))
        let cap = try #require(cells[..<cross].lastIndex(of: "▌"), "no field before the ✗: \(lines[row])")
        return (row, cap, cross)
    }

    @Test(
        "On a page the ✗ stands one cell past the field, and only the ✗ empties it",
        arguments: [10, 20, 40])
    func onAPage(width: Int) throws {
        let query = Query("")
        let app = TestApp(width: width, height: 6) { Text("BODY").searchable(text: query.binding) }
        _ = app.press(.tab)
        app.type("abc")
        let (row, cap, cross) = try columns(app.screen.lines)
        #expect(cross == cap + 2, "one cell of spacing between the field and the ✗: \(app.screen.lines[row])")

        // The cell between them is the row's spacing, not the button's.
        app.click(at: CellPoint(x: cap + 1, y: row))
        #expect(query.text == "abc", "a click beside the ✗ leaves the field as it is")
        app.click(at: CellPoint(x: cross, y: row))
        #expect(query.text.isEmpty, "a click on the ✗ empties the field")
    }

    @Test("In a toolbar's bar the ✗ stands one cell past the field")
    func inABar() throws {
        BarApp.query.text = "abc"
        let app = TestApp(BarApp(), width: 30, height: 8)
        app.advance(by: .milliseconds(50))
        let (row, cap, cross) = try columns(app.screen.lines)
        #expect(cross == cap + 2, "\(app.screen.lines[row])")
        app.click(at: CellPoint(x: cross, y: row))
        #expect(BarApp.query.text.isEmpty, "a click on the ✗ empties the field")
    }

    @Test("Ctrl-U still empties the field from the keyboard")
    func keyboardRoute() {
        let query = Query("")
        let app = TestApp(width: 20, height: 6) { Text("BODY").searchable(text: query.binding) }
        _ = app.press(.tab)
        app.type("abc")
        _ = app.press(KeyEvent(key: .character("u"), ctrl: true))
        #expect(query.text.isEmpty)
        #expect(!app.screen.contains("✗"))
    }
}
