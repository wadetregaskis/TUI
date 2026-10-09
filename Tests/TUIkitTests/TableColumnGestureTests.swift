//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnGestureTests.swift
//
//  The user's gestures on a table bound to a `TableColumnCustomization`
//  (decisions B45): the header's menu shows and hides columns, dragging a
//  title moves its column, dragging the gap after it resizes it — the width
//  kept in the customization, as SwiftUI keeps it — and Ctrl-K picks a column
//  for the keyboard's `<`/`>`, `-`/`+` and Return. Each is taken away by the
//  column's `disabledCustomizationBehavior`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTables

@Observable
@MainActor
private final class Columns {
    var customization = TableColumnCustomization<Entry>()
    var bound = true
    var sortOrder = [KeyPathComparator(\Entry.alpha)]
    var selection: Set<Int> = []
    /// Whether the table carries a column of `Toggle`s instead of its usual
    /// four columns.
    var toggles = false
    /// The entries whose toggle is on.
    var flags: Set<Int> = []
    /// Whether the table carries a row menu that builds nothing.
    var emptyRowMenu = false
}

private struct Entry: Identifiable, Equatable {
    let id: Int
    var alpha: String { "a\(id)" }
    var beta: String { "b\(id)" }
    var gamma: String { "g\(id)" }
}

private struct ColumnsApp: App {
    let columns: Columns?

    init() { columns = nil }

    init(_ columns: Columns) { self.columns = columns }

    var body: some Scene {
        WindowGroup {
            // The line of key hints, where the column mode says how to leave
            // it: a bare WindowGroup draws none.
            Group { if let columns { ColumnsPage(columns: columns) } }
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}

private struct ColumnsPage: View {
    let columns: Columns
    private let entries = (1...3).map(Entry.init)

    var body: some View {
        if columns.emptyRowMenu, columns.toggles {
            toggleTable.contextMenu(forSelectionType: Int.self) { _ in }
        } else if columns.emptyRowMenu {
            boundTable.contextMenu(forSelectionType: Int.self) { _ in }
        } else if columns.toggles {
            toggleTable
        } else if columns.bound {
            boundTable
        } else {
            Table(entries, sortOrder: Bindable(columns).sortOrder) {
                TableColumn("Alpha", value: \.alpha).customizationID("alpha")
                TableColumn("Beta", value: \.beta).customizationID("beta")
            }
            .frame(height: 9)
        }
    }

    private var boundTable: some View {
        Table(
            entries, selection: Bindable(columns).selection, sortOrder: Bindable(columns).sortOrder,
            columnCustomization: Bindable(columns).customization
        ) {
            TableColumn("Alpha", value: \.alpha)
                .width(min: 4, ideal: 8, max: 30).customizationID("alpha")
            TableColumn("Beta", value: \.beta)
                .width(min: 4, ideal: 8, max: 30).customizationID("beta")
            TableColumn("Gamma", value: \.gamma)
                .width(min: 4, ideal: 8, max: 30).customizationID("gamma")
                .disabledCustomizationBehavior([.resize, .reorder])
            TableColumn("Delta") { (entry: Entry) in Text(verbatim: "d\(entry.id)") }
                .width(6)
        }
        .frame(height: 9)
    }
}

extension ColumnsPage {
    /// Alpha and Beta, and a Delta column of toggles.
    private var toggleTable: some View {
        Table(
            entries, selection: Bindable(columns).selection, sortOrder: Bindable(columns).sortOrder,
            columnCustomization: Bindable(columns).customization
        ) {
            TableColumn("Alpha", value: \.alpha).customizationID("alpha")
            TableColumn("Beta", value: \.beta).customizationID("beta")
            TableColumn("Delta") { (entry: Entry) in
                Toggle(
                    "",
                    isOn: Binding(
                        get: { columns.flags.contains(entry.id) },
                        set: { on in
                            if on { columns.flags.insert(entry.id) } else { columns.flags.remove(entry.id) }
                        }))
            }
            .width(6)
        }
        .frame(height: 9)
    }
}

@MainActor
private final class Harness {
    let columns = Columns()
    let app: HeadlessApp<ColumnsApp>
    private var now: Int64 = 0

    init(bound: Bool = true, toggles: Bool = false, emptyRowMenu: Bool = false) {
        columns.bound = bound
        columns.toggles = toggles
        columns.emptyRowMenu = emptyRowMenu
        app = HeadlessApp(ColumnsApp(columns), width: 60, height: 14)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var lines: [String] { app.screen.map(\.stripped) }

    var screen: String { lines.joined(separator: "\n") }

    func shows(_ text: String) -> Bool { lines.contains { $0.contains(text) } }

    /// The header line, found by two titles on it — Alpha may be hidden.
    var headerY: Int? { lines.firstIndex { $0.contains("Beta") && $0.contains("Delta") } }

    func column(of text: String, on y: Int) -> Int? {
        lines[y].range(of: text).map { lines[y].distance(from: lines[y].startIndex, to: $0.lowerBound) }
    }

    /// The headers' left edges, in the order drawn.
    var headerOrder: [String] {
        guard let y = headerY else { return [] }
        return ["Alpha", "Beta", "Gamma", "Delta"]
            .compactMap { title in column(of: title, on: y).map { (title, $0) } }
            .sorted { $0.1 < $1.1 }.map(\.0)
    }

    func send(_ event: MouseEvent) {
        app.send(event)
        frame()
    }

    func key(_ event: KeyEvent) {
        app.send(event)
        frame()
    }

    func rightClick(x: Int, y: Int) {
        app.send(MouseEvent(button: .right, phase: .pressed, x: x, y: y))
        app.send(MouseEvent(button: .right, phase: .released, x: x, y: y))
        frame()
    }

    /// A left-button drag from `from` to `to`, a cell at a time.
    func drag(from: (x: Int, y: Int), toX: Int) {
        send(MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        let step = toX > from.x ? 1 : -1
        var x = from.x
        while x != toX {
            x += step
            send(MouseEvent(button: .left, phase: .dragged, x: x, y: from.y))
        }
        send(MouseEvent(button: .left, phase: .released, x: toX, y: from.y))
    }
}

/// The header orders the tests expect, typed once: an array literal inside each `#expect`, beside its
/// interpolated message, made each of those lines cost about 50 ms to type-check (lane TC2).
private let alphabetical: [String] = ["Alpha", "Beta", "Gamma", "Delta"]
private let betaFirst: [String] = ["Beta", "Alpha", "Gamma", "Delta"]
private let alphaHidden: [String] = ["Beta", "Gamma", "Delta"]

@MainActor
@Suite("Column customization gestures")
struct TableColumnGestureTests {
    @Test("A right-click on a header opens the column menu; Hide hides that column")
    func headerMenuHides() throws {
        let harness = Harness()
        let y = try #require(harness.headerY, "\(harness.screen)")
        harness.rightClick(x: try #require(harness.column(of: "Beta", on: y)), y: y)
        #expect(harness.shows("Hide “Beta”"), "\(harness.screen)")
        harness.key(KeyEvent(key: .down))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.columns.customization[visibility: "beta"] == .hidden)
        #expect(!harness.headerOrder.contains("Beta"), "\(harness.screen)")
        // The menu shows it again, unmarked while hidden.
        harness.rightClick(x: try #require(harness.column(of: "Alpha", on: y)), y: y)
        #expect(harness.shows("Beta"), "the menu lists the hidden column:\n\(harness.screen)")
        // Hide “Alpha”, the divider, Alpha, Beta: the fourth row.
        for _ in 0..<3 { harness.key(KeyEvent(key: .down)) }
        harness.key(KeyEvent(key: .enter))
        #expect(harness.columns.customization[visibility: "beta"] == .visible, "\(harness.screen)")
        #expect(harness.headerOrder.contains("Beta"))
    }

    @Test("Without a customization binding, the header has no column menu")
    func noBindingNoMenu() throws {
        let harness = Harness(bound: false)
        let y = try #require(harness.lines.firstIndex { $0.contains("Alpha") && $0.contains("Beta") })
        harness.rightClick(x: try #require(harness.column(of: "Beta", on: y)), y: y)
        #expect(!harness.shows("Hide"), "\(harness.screen)")
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        harness.key(KeyEvent(key: .character(">")))
        #expect(harness.lines[y].contains("Alpha"))
    }

    @Test("Dragging a title moves its column, and the customization records the order")
    func dragReorders() throws {
        let harness = Harness()
        let y = try #require(harness.headerY)
        let alpha = try #require(harness.column(of: "Alpha", on: y))
        let beta = try #require(harness.column(of: "Beta", on: y))
        harness.drag(from: (alpha + 1, y), toX: beta + 6)
        #expect(harness.headerOrder == betaFirst, "\(harness.screen)")
        #expect(harness.columns.sortOrder == [KeyPathComparator(\Entry.alpha)], "a drag must not sort")
        let encoded = String(bytes: try JSONEncoder().encode(harness.columns.customization), encoding: .utf8) ?? ""
        #expect(encoded.contains("\"order\""), "\(encoded)")
        // Gamma may not move: a drag over it moves nothing.
        let gamma = try #require(harness.column(of: "Gamma", on: y))
        harness.drag(from: (gamma + 1, y), toX: gamma - 6)
        #expect(harness.headerOrder == betaFirst, "\(harness.screen)")
    }

    @Test("A click on a title still sorts")
    func clickSorts() throws {
        let harness = Harness()
        let y = try #require(harness.headerY)
        let beta = try #require(harness.column(of: "Beta", on: y))
        harness.send(MouseEvent(button: .left, phase: .pressed, x: beta + 1, y: y))
        harness.send(MouseEvent(button: .left, phase: .released, x: beta + 1, y: y))
        #expect(harness.columns.sortOrder.first == KeyPathComparator(\Entry.beta))
    }

    @Test("Dragging the gap after a title resizes the column within its bounds, and the width persists")
    func dragResizes() throws {
        let harness = Harness()
        let y = try #require(harness.headerY)
        let alpha = try #require(harness.column(of: "Alpha", on: y))
        let beta = try #require(harness.column(of: "Beta", on: y))
        let width = beta - alpha - 2
        // The gap is the two cells before Beta.
        harness.drag(from: (beta - 1, y), toX: beta + 2)
        #expect(harness.columns.customization[width: "alpha"] == width + 3, "\(harness.screen)")
        #expect(harness.column(of: "Beta", on: y) == beta + 3)
        // Past the maximum, the width stops there.
        let gap = try #require(harness.column(of: "Beta", on: y)) - 1
        harness.drag(from: (gap, y), toX: gap + 20)
        #expect(harness.columns.customization[width: "alpha"] == 30)
        // The width survives an encoding round trip.
        let data = try JSONEncoder().encode(harness.columns.customization)
        let decoded = try JSONDecoder().decode(TableColumnCustomization<Entry>.self, from: data)
        #expect(decoded[width: "alpha"] == 30)
        #expect(decoded == harness.columns.customization)
    }

    @Test("A column whose resizing is disabled has no gap to drag")
    func resizeDisabled() throws {
        let harness = Harness()
        let y = try #require(harness.headerY)
        let delta = try #require(harness.column(of: "Delta", on: y))
        harness.drag(from: (delta - 1, y), toX: delta + 3)
        #expect(harness.columns.customization[width: "gamma"] == nil)
        #expect(harness.column(of: "Delta", on: y) == delta)
    }

    @Test("Ctrl-K picks a column; < and > move it, - and + resize it, Return opens its menu")
    func keyboard() throws {
        let harness = Harness()
        let y = try #require(harness.headerY)
        let beta = try #require(harness.column(of: "Beta", on: y))
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        harness.key(KeyEvent(key: .character(">")))
        #expect(harness.headerOrder == betaFirst, "\(harness.screen)")
        harness.key(KeyEvent(key: .character("+")))
        harness.key(KeyEvent(key: .character("+")))
        let alphaWidth = try #require(harness.columns.customization[width: "alpha"])
        harness.key(KeyEvent(key: .character("-")))
        #expect(harness.columns.customization[width: "alpha"] == alphaWidth - 1)
        // → picks the next column; Return opens the menu on it.
        harness.key(KeyEvent(key: .right))
        harness.key(KeyEvent(key: .enter))
        #expect(harness.shows("Hide “Gamma”"), "\(harness.screen)")
        harness.key(KeyEvent(key: .escape))
        #expect(!harness.shows("Hide “Gamma”"))
        // The menu was the mode's own: back at the table, ← picks Alpha and
        // `<` moves it back.
        harness.frame()
        #expect(harness.shows("stop editing columns"), "\(harness.screen)")
        harness.key(KeyEvent(key: .left))
        harness.key(KeyEvent(key: .character("<")))
        #expect(harness.headerOrder == alphabetical, "\(harness.screen)")
        // Escape lets the column go: ">" moves nothing now.
        harness.key(KeyEvent(key: .escape))
        harness.key(KeyEvent(key: .character(">")))
        #expect(harness.headerOrder == alphabetical, "\(harness.screen)")
        _ = beta
    }

    @Test("Escape lets go of a picked column the menu hid, and goes no further")
    func escapeAfterHidingThePickedColumn() throws {
        let harness = Harness()
        harness.columns.selection = [2]
        harness.frame()
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        // Return opens the menu on Alpha, picked; its first row hides it.
        harness.key(KeyEvent(key: .enter))
        #expect(harness.shows("Hide “Alpha”"), "\(harness.screen)")
        harness.key(KeyEvent(key: .enter))
        #expect(harness.columns.customization[visibility: "alpha"] == .hidden, "\(harness.screen)")
        // Back at the table (the status bar a frame behind the menu's
        // closing), the mode goes on, on the first column left.
        harness.frame()
        #expect(harness.shows("stop editing columns"), "\(harness.screen)")
        harness.key(KeyEvent(key: .escape))
        #expect(harness.columns.selection == [2], "Escape went on to the rows and cleared the selection")
        // And the mode is off: `>` moves nothing.
        harness.key(KeyEvent(key: .character(">")))
        #expect(harness.headerOrder == alphaHidden, "\(harness.screen)")
    }

    // MARK: A batch of input between two frames

    @Test("Two drag reports in one batch move a title once, not there and back")
    func dragReportsInOneBatch() throws {
        let harness = Harness()
        let y = try #require(harness.headerY)
        let alpha = try #require(harness.column(of: "Alpha", on: y))
        let beta = try #require(harness.column(of: "Beta", on: y))
        harness.send(MouseEvent(button: .left, phase: .pressed, x: alpha + 1, y: y))
        // Over Beta far enough to swap, and a cell further, with no frame
        // between: the second report must see the swap the first made.
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta + 6, y: y))
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta + 7, y: y))
        harness.frame()
        harness.send(MouseEvent(button: .left, phase: .released, x: beta + 7, y: y))
        #expect(harness.headerOrder == betaFirst, "\(harness.screen)")
    }

    @Test("Column keys in one batch each act on what the one before left")
    func columnKeysInOneBatch() throws {
        let harness = Harness()
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        // `>` then `<`: back where it started.
        harness.app.send(KeyEvent(key: .character(">")))
        harness.app.send(KeyEvent(key: .character("<")))
        harness.frame()
        #expect(harness.headerOrder == alphabetical, "\(harness.screen)")
        // `+` twice: two cells wider.
        let y = try #require(harness.headerY)
        let width = try #require(harness.column(of: "Beta", on: y)) - 2
            - (try #require(harness.column(of: "Alpha", on: y)))
        harness.app.send(KeyEvent(key: .character("+")))
        harness.app.send(KeyEvent(key: .character("+")))
        harness.frame()
        #expect(harness.columns.customization[width: "alpha"] == width + 2, "\(harness.screen)")
    }

    @Test("A column key in the batch that hid the picked column picks another, and goes no further")
    func columnKeyAfterHidingInOneBatch() throws {
        let harness = Harness()
        harness.columns.selection = [2]
        harness.frame()
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        // Hidden behind the keys' back, then Return and Escape before a frame.
        harness.columns.customization[visibility: "alpha"] = .hidden
        harness.app.send(KeyEvent(key: .enter))
        harness.app.send(KeyEvent(key: .escape))
        harness.frame()
        #expect(!harness.shows("Hide “"), "Return opened a menu on a column the user had not seen picked")
        #expect(harness.columns.selection == [2], "a column key went on to the rows")
        harness.key(KeyEvent(key: .character(">")))
        #expect(harness.headerOrder == alphaHidden, "the mode outlived Escape:\n\(harness.screen)")
    }

    @Test(
        "A drag after the press that opened the column menu resizes nothing, and letting go closes the menu, with or without a frame between",
        arguments: [false, true])
    func menuOpeningPressSpendsItsDrag(frameBetween: Bool) throws {
        // A Ctrl-press on Beta's title opens the menu and hands the gesture to
        // it; until a frame draws the menu over the header, its drag — Ctrl let
        // go — lands on the header's own regions, here the gap before Beta.
        // Drawn, the menu's backdrop takes the drag there, and the release —
        // the pointer moved, so a hold let go away from the menu — closes it.
        // Undrawn, the same release closes it too.
        let harness = Harness()
        let y = try #require(harness.headerY)
        let beta = try #require(harness.column(of: "Beta", on: y))
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: beta + 1, y: y, ctrl: true))
        if frameBetween { harness.frame() }
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta - 1, y: y))
        if frameBetween { harness.frame() }
        harness.app.send(MouseEvent(button: .left, phase: .released, x: beta - 1, y: y))
        harness.frame()
        #expect(!harness.shows("Hide “Beta”"), "letting go left the menu up:\n\(harness.screen)")
        #expect(harness.columns.customization[width: "alpha"] == nil, "the drag resized Alpha:\n\(harness.screen)")
        // Its release is the menu's too, and sorts nothing — Ctrl let go or
        // not, since the release takes its press's modifiers (`stampClickCount`).
        let sort = Harness()
        sort.app.send(MouseEvent(button: .left, phase: .pressed, x: beta + 1, y: y, ctrl: true))
        sort.app.send(MouseEvent(button: .left, phase: .released, x: beta + 1, y: y))
        sort.frame()
        #expect(sort.columns.sortOrder == [KeyPathComparator(\Entry.alpha)], "the release sorted")
    }

    @Test(
        "The release of the press that opened the column menu selects no row, with or without a frame between",
        arguments: [false, true])
    func menuOpeningPressSpendsItsReleaseOnARow(frameBetween: Bool) throws {
        // The table has no row menu, so its rows' handler had no menu to ask
        // about the gesture: a release that reached a row before a frame drew
        // the menu was a click there, carrying the press's Ctrl — a toggle.
        let harness = Harness()
        let y = try #require(harness.headerY)
        let alpha = try #require(harness.column(of: "Alpha", on: y))
        let beta = try #require(harness.column(of: "Beta", on: y))
        let row = try #require(harness.lines.firstIndex { $0.contains("a2") }, "\(harness.screen)")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: beta + 1, y: y, ctrl: true))
        if frameBetween { harness.frame() }
        harness.app.send(MouseEvent(button: .left, phase: .released, x: alpha, y: row))
        harness.frame()
        #expect(harness.columns.selection.isEmpty, "the release selected a row:\n\(harness.screen)")
        #expect(harness.shows("Hide “Beta”"), "a click's release closed the menu:\n\(harness.screen)")
    }

    @Test(
        "The release of the press that opened the column menu toggles no Toggle under it, with or without a frame between",
        arguments: [false, true])
    func menuOpeningPressSpendsItsReleaseOnAControl(frameBetween: Bool) throws {
        // A row's controls win over the rows' own region, so the rows' check
        // of the gesture never hears a release on one: until a frame drew the
        // menu, it was the Toggle's — a click it was never pressed for.
        let harness = Harness(toggles: true)
        let y = try #require(harness.headerY, "\(harness.screen)")
        let beta = try #require(harness.column(of: "Beta", on: y))
        let delta = try #require(harness.column(of: "Delta", on: y))
        let first = try #require(harness.lines.firstIndex { $0.contains("a1") }, "\(harness.screen)")
        let second = try #require(harness.lines.firstIndex { $0.contains("a2") })
        // A click on a toggle toggles it: the cell takes the pointer.
        harness.send(MouseEvent(button: .left, phase: .pressed, x: delta + 1, y: first))
        harness.send(MouseEvent(button: .left, phase: .released, x: delta + 1, y: first))
        #expect(harness.columns.flags == [1], "\(harness.screen)")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: beta + 1, y: y, ctrl: true))
        if frameBetween { harness.frame() }
        harness.app.send(MouseEvent(button: .left, phase: .released, x: delta + 1, y: second))
        harness.frame()
        #expect(harness.columns.flags == [1], "the release toggled a2:\n\(harness.screen)")
        #expect(harness.shows("Hide “Beta”"), "a click's release closed the menu:\n\(harness.screen)")
    }

    @Test("A drag after a press that opened a row menu which built nothing resizes no column")
    func emptyRowMenuPressSpendsItsDrag() throws {
        // A row menu that builds nothing closes on the frame after its press
        // without having drawn a backdrop, so after that frame the drag is
        // hit-tested against the table: here, the gap before Beta, which
        // never saw a press and resized Alpha from the gesture state it was
        // left with.
        let harness = Harness(emptyRowMenu: true)
        let y = try #require(harness.headerY, "\(harness.screen)")
        let beta = try #require(harness.column(of: "Beta", on: y))
        let row = try #require(harness.lines.firstIndex { $0.contains("a1") }, "\(harness.screen)")
        let rowX = try #require(harness.column(of: "a1", on: row))
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: rowX, y: row, ctrl: true))
        harness.frame()
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta - 1, y: y))
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta + 3, y: y))
        harness.frame()
        harness.app.send(MouseEvent(button: .left, phase: .released, x: beta + 3, y: y))
        harness.frame()
        #expect(harness.columns.customization[width: "alpha"] == nil, "the drag resized Alpha:\n\(harness.screen)")
        #expect(harness.columns.selection.isEmpty, "\(harness.screen)")
    }

    @Test("The release of a press that opened a row menu which built nothing toggles no Toggle a frame later")
    func emptyRowMenuPressSpendsItsReleaseOnAControl() throws {
        // The menu closed undrawn on the frame after the press, so nothing of
        // it takes the release; the rows' own check never hears a release on
        // a cell's control, which wins over the rows' region.
        let harness = Harness(toggles: true, emptyRowMenu: true)
        let y = try #require(harness.headerY, "\(harness.screen)")
        let delta = try #require(harness.column(of: "Delta", on: y))
        let first = try #require(harness.lines.firstIndex { $0.contains("a1") }, "\(harness.screen)")
        let second = try #require(harness.lines.firstIndex { $0.contains("a2") })
        let alpha = try #require(harness.column(of: "a1", on: first))
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: alpha, y: first, ctrl: true))
        harness.frame()
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: delta + 1, y: second))
        harness.frame()
        harness.app.send(MouseEvent(button: .left, phase: .released, x: delta + 1, y: second))
        harness.frame()
        #expect(harness.columns.flags.isEmpty, "the release toggled a2:\n\(harness.screen)")
        #expect(harness.columns.selection.isEmpty, "\(harness.screen)")
    }

    @Test("Without a customization binding, a Ctrl-click on a sortable title sorts, as a click does")
    func ctrlClickSortsWithoutAMenu() throws {
        let harness = Harness(bound: false)
        let y = try #require(harness.lines.firstIndex { $0.contains("Alpha") && $0.contains("Beta") })
        let beta = try #require(harness.column(of: "Beta", on: y))
        harness.send(MouseEvent(button: .left, phase: .pressed, x: beta + 1, y: y, ctrl: true))
        harness.send(MouseEvent(button: .left, phase: .released, x: beta + 1, y: y, ctrl: true))
        #expect(harness.columns.sortOrder.first == KeyPathComparator(\Entry.beta), "\(harness.screen)")
    }
}
