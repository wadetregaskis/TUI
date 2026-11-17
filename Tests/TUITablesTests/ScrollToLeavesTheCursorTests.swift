//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollToLeavesTheCursorTests.swift
//
//  `ScrollViewProxy.scrollTo(_:anchor:)` on a row of a focused `List` or
//  `Table` moves the rows in view and nothing else: the selection stays, and
//  the keyboard's row stays where it was, so the next arrow goes on from there
//  and brings it back into view. macOS does the same
//  (`Tools/SwiftUIProbes/Scroll to a row/selrow.swift`, `selrow.out`: after
//  `scrollTo(50)` with row 0 selected, Down selects row 1 and scrolls back to
//  it; with nothing selected, Down selects row 0). tuitree's feedback, G6.
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
    /// Ends in a dash, so `row-5-` is not found inside `row-50-`.
    var name: String { "row-\(id)-" }
}

@MainActor
private final class ProxyBox {
    var proxy: ScrollViewProxy?
}

@Observable
@MainActor
private final class Selected {
    var single: Int?
    var multiple: Set<Int> = []
}

@MainActor
@Suite("scrollTo moves neither a list's selection nor its cursor")
struct ScrollToLeavesTheCursorTests {
    private let rows = (0..<100).map(Row.init)

    /// A focused table of 100 rows, in a `ScrollViewReader`.
    private func table(_ selected: Selected, _ box: ProxyBox, follows: Bool) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            ScrollViewReader { reader in
                // swiftlint:disable:next redundant_discardable_let
                let _ = box.proxy = reader
                Table(rows, selection: Binding(get: { selected.single }, set: { selected.single = $0 })) {
                    TableColumn("Name", value: \Row.name)
                }
                .selectionFollowsCursor(follows)
            }
        }
        app.press(.tab)
        return app
    }

    /// A focused list of 100 rows with a multiple selection, following the
    /// cursor, in a `ScrollViewReader`.
    private func multipleList(_ selected: Selected, _ box: ProxyBox) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            ScrollViewReader { reader in
                // swiftlint:disable:next redundant_discardable_let
                let _ = box.proxy = reader
                List(selection: Binding(get: { selected.multiple }, set: { selected.multiple = $0 })) {
                    ForEach(rows) { Text(verbatim: $0.name) }
                }
                .selectionFollowsCursor()
            }
        }
        app.press(.tab)
        return app
    }

    @Test("A table's selection stays, and Down selects the row after it and scrolls back")
    func tableDownGoesOnFromTheSelection() {
        let selected = Selected()
        selected.single = 0
        let box = ProxyBox()
        let app = table(selected, box, follows: true)
        box.proxy?.scrollTo(50, anchor: .top)
        #expect(app.screen.contains("row-50-"), "\(app.screen)")
        #expect(!app.screen.contains("row-0-"))
        #expect(selected.single == 0)
        app.press(.down)
        #expect(selected.single == 1)
        #expect(app.screen.contains("row-1-"), "\(app.screen)")
        #expect(!app.screen.contains("row-50-"))
    }

    @Test("With no anchor too: the least move shows row 50, and Down goes on from row 0")
    func noAnchor() {
        let selected = Selected()
        selected.single = 0
        let box = ProxyBox()
        let app = table(selected, box, follows: true)
        box.proxy?.scrollTo(50)
        #expect(app.screen.contains("row-50-"), "\(app.screen)")
        #expect(selected.single == 0)
        app.press(.down)
        #expect(selected.single == 1)
        #expect(app.screen.contains("row-1-"), "\(app.screen)")
    }

    @Test("A list's multiple selection stays, and Down selects the row after it")
    func listMultipleSelection() {
        let selected = Selected()
        selected.multiple = [0]
        let box = ProxyBox()
        let app = multipleList(selected, box)
        box.proxy?.scrollTo(50, anchor: .top)
        #expect(app.screen.contains("row-50-"), "\(app.screen)")
        #expect(selected.multiple == [0])
        app.press(.down)
        #expect(selected.multiple == [1])
        #expect(app.screen.contains("row-1-"), "\(app.screen)")
    }

    /// Under `.selectionFollowsCursor()` with nothing selected the cursor is on
    /// no row, and the first Down selects row 0, as macOS's does, from
    /// wherever `scrollTo` left the rows (stage 2 of
    /// `Documentation/Historical/Lists, tables and tabs/The first key from an empty selection.md`,
    /// 2026-11-16; it was a known issue here, the first Down selecting row 1).
    @Test("With nothing selected, Down after scrollTo selects the first row, not one in view")
    func nothingSelected() {
        let selected = Selected()
        let box = ProxyBox()
        let app = table(selected, box, follows: true)
        box.proxy?.scrollTo(50, anchor: .top)
        #expect(app.screen.contains("row-50-"), "\(app.screen)")
        #expect(selected.single == nil)
        app.press(.down)
        // It does scroll back to the cursor, not stay at row 50.
        #expect(!app.screen.contains("row-50-"), "\(app.screen)")
        #expect(selected.single == 0)
        #expect(app.screen.contains("row-0-"))
    }

    @Test("A cursor apart from the selection stays too: Down then Space selects row 1")
    func cursorApart() {
        let selected = Selected()
        selected.single = 0
        let box = ProxyBox()
        let app = table(selected, box, follows: false)
        box.proxy?.scrollTo(50, anchor: .top)
        #expect(app.screen.contains("row-50-"), "\(app.screen)")
        app.press(.down)
        app.press(.space)
        #expect(selected.single == 1)
        #expect(app.screen.contains("row-1-"), "\(app.screen)")
    }
}
