//  🖥️ TUI — A Terminal UI framework for Swift
//  FirstKeyFromEmptySelectionTests.swift
//
//  What the first key does in a focused table or list under
//  `.selectionFollowsCursor()` with nothing selected, beside what macOS does
//  (`Tools/SwiftUIProbes/Scroll to a row/firstkey.swift`, `firstkey.out`):
//  there Down selects the first row, Up the last, a typed letter the first row
//  it names, and Home, End and the page keys only scroll, with a row selected
//  or without. Where TUI differs the expectation is macOS's, under
//  `withKnownIssue`; the analysis, the plan and what was built are in
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

    @Test("Home selects nothing")
    func homeSelectsNothing() {
        let selected = Selected()
        let app = table(selected)
        app.press(.home)
        #expect(selected.single == nil)
    }

    @Test("A letter that is not the cursor row's selects the first row it names")
    func typeSelectFindsTheFirstRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.character("c"))
        app.advance(by: .milliseconds(20))
        #expect(selected.single == 2)
    }

    // MARK: - Where TUI differs

    @Test("Down selects the first row")
    func downSelectsTheFirstRow() {
        let selected = Selected()
        let app = table(selected)
        app.press(.down)
        withKnownIssue("The cursor starts on row 0, so the first Down moves it to row 1 and selects that") {
            #expect(selected.single == 0)
        }
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
        withKnownIssue("The cursor starts on row 0, so the first Down moves it to row 1 and selects that") {
            #expect(selected.multiple == [0])
        }
    }

    @Test("The letter of the first row selects the first row")
    func typeSelectFirstRowsLetter() {
        let selected = Selected()
        let app = table(selected)
        app.press(.character("a"))
        app.advance(by: .milliseconds(20))
        withKnownIssue("A first character searches after the cursor, which is on row 0 with nothing selected") {
            #expect(selected.single == 0)
        }
    }

    @Test("End selects nothing")
    func endSelectsNothing() {
        let selected = Selected()
        let app = table(selected)
        app.press(.end)
        withKnownIssue("APPFB-1 has End select; on macOS it only scrolls (an owner question)") {
            #expect(selected.single == nil)
        }
    }

    @Test("Page Down selects nothing")
    func pageDownSelectsNothing() {
        let selected = Selected()
        let app = table(selected)
        app.press(.pageDown)
        withKnownIssue("APPFB-1 has the page keys select; on macOS they only scroll (an owner question)") {
            #expect(selected.single == nil)
        }
    }

    @Test("Home leaves a selected row selected")
    func homeKeepsTheSelection() {
        let selected = Selected()
        let app = table(selected)
        app.press(.down)
        app.press(.down)
        app.press(.down)
        let before = selected.single
        app.press(.home)
        withKnownIssue("APPFB-1 has Home select; on macOS it only scrolls (an owner question)") {
            #expect(selected.single == before)
        }
    }

    @Test("A selection the app clears is forgotten: Down selects the first row")
    func clearedByTheApp() {
        let selected = Selected()
        let app = table(selected)
        for _ in 0..<5 { app.press(.down) }
        #expect(selected.single == 5)
        app.press(.character("j"))
        #expect(selected.single == nil)
        app.press(.down)
        withKnownIssue("The cursor stays on the row the selection left, and Down goes on from it") {
            #expect(selected.single == 0)
        }
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
}
