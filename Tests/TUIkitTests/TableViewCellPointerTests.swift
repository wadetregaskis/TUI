//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableViewCellPointerTests.swift
//
//  A control in a table's view cell answers the pointer: the cell's hit
//  regions are carried into the table's buffer at the cell's column and the
//  row's lines, so a click on a `Button` presses it, a tap gesture fires, a
//  `.contextMenu` opens and draws its menu — and a click anywhere else on the
//  row still selects it. They were dropped with the rest of the cell's buffer,
//  so a click on a button in a cell selected the row (decisions B46).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@Observable
@MainActor
private final class Ledger {
    var selection: Int?
    var pressed: [String] = []
    /// Whether the table's cells are two lines tall.
    var tall = false
}

private struct Entry: Identifiable, Equatable {
    let id: Int
    var name: String { "item\(id)" }
}

private struct LedgerApp: App {
    let ledger: Ledger?

    init() { ledger = nil }

    init(_ ledger: Ledger) { self.ledger = ledger }

    var body: some Scene {
        WindowGroup {
            if let ledger { LedgerPage(ledger: ledger) }
        }
    }
}

private struct LedgerPage: View {
    let ledger: Ledger
    private let entries = (0..<4).map(Entry.init)

    var body: some View {
        if ledger.tall {
            Table(entries, selection: Bindable(ledger).selection) {
                TableColumn("Name", value: \.name)
                TableColumn("Actions") { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "row \(entry.id)")
                        Button("Go\(entry.id)") { ledger.pressed.append("go \(entry.id)") }
                    }
                }
                .lineLimit(2)
            }
        } else {
            Table(entries, selection: Bindable(ledger).selection) {
                TableColumn("Name", value: \.name)
                TableColumn("Act") { entry in
                    Button("Go\(entry.id)") { ledger.pressed.append("go \(entry.id)") }
                }
                .width(12)
                .alignment(.trailing)
                TableColumn("Tap") { entry in
                    Text(verbatim: "tap\(entry.id)")
                        .onTapGesture { ledger.pressed.append("tap \(entry.id)") }
                }
                TableColumn("Menu") { entry in
                    Text(verbatim: "menu\(entry.id)")
                        .contextMenu {
                            Button("Rename\(entry.id)") { ledger.pressed.append("rename \(entry.id)") }
                        }
                }
            }
        }
    }
}

@MainActor
private final class Harness {
    let ledger = Ledger()
    let app: HeadlessApp<LedgerApp>
    private var now: Int64 = 0

    init(tall: Bool = false) {
        ledger.tall = tall
        app = HeadlessApp(LedgerApp(ledger), width: 70, height: 20)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    /// Where `text` is drawn: its line and the column of its first character.
    func position(of text: String) throws -> (x: Int, y: Int) {
        let y = try #require(app.screen.firstIndex { $0.stripped.contains(text) }, "\(text) is not drawn")
        let line = app.screen[y].stripped
        let range = try #require(line.range(of: text))
        return (line.distance(from: line.startIndex, to: range.lowerBound), y)
    }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    /// A click — press and release — at `point`, a frame after each.
    func click(_ point: (x: Int, y: Int), button: MouseButton = .left) {
        app.send(MouseEvent(button: button, phase: .pressed, x: point.x, y: point.y))
        frame()
        app.send(MouseEvent(button: button, phase: .released, x: point.x, y: point.y))
        frame()
    }
}

@MainActor
@Suite("A control in a table's view cell answers the pointer")
struct TableViewCellPointerTests {
    @Test("A click on a button in a cell presses it and leaves the selection alone")
    func buttonTakesTheClick() throws {
        let harness = Harness()
        // Frames enough for the rows to be kept and served: the click must
        // still reach the button on a row whose line came from the memo.
        harness.frame()
        harness.click(try harness.position(of: "Go2"))
        #expect(harness.ledger.pressed == ["go 2"], "pressed \(harness.ledger.pressed)")
        #expect(harness.ledger.selection == nil, "the click selected row \(String(describing: harness.ledger.selection))")
    }

    @Test("A click on a row away from its controls still selects it")
    func rowTakesTheRest() throws {
        let harness = Harness()
        harness.click(try harness.position(of: "item1"))
        #expect(harness.ledger.selection == 1)
        #expect(harness.ledger.pressed.isEmpty)
        // Beside the trailing-aligned button, in its own column's cells: the
        // row's, not the button's.
        let go = try harness.position(of: "Go3")
        harness.click((go.x - 3, go.y))
        #expect(harness.ledger.selection == 3)
        #expect(harness.ledger.pressed.isEmpty, "pressed \(harness.ledger.pressed)")
    }

    @Test("A tap gesture on a cell's view fires")
    func tapGestureFires() throws {
        let harness = Harness()
        harness.click(try harness.position(of: "tap0"))
        #expect(harness.ledger.pressed == ["tap 0"], "pressed \(harness.ledger.pressed)")
    }

    @Test("A context menu on a cell's view opens on a right-click and draws its menu")
    func contextMenuOpens() throws {
        let harness = Harness()
        let menu = try harness.position(of: "menu1")
        harness.app.send(MouseEvent(button: .right, phase: .pressed, x: menu.x, y: menu.y))
        harness.app.send(MouseEvent(button: .right, phase: .released, x: menu.x, y: menu.y))
        harness.frame()
        #expect(harness.shows("Rename1"), "the menu was not drawn:\n\(harness.app.screen.map(\.stripped).joined(separator: "\n"))")
        harness.app.send(KeyEvent(key: .down))
        harness.frame()
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.ledger.pressed == ["rename 1"], "pressed \(harness.ledger.pressed)")
    }

    @Test("A left click on a cell with a context menu selects the row: the trigger passes it down")
    func leftClickOnContextMenuCellSelects() throws {
        let harness = Harness()
        harness.click(try harness.position(of: "menu2"))
        #expect(harness.ledger.selection == 2)
        #expect(!harness.shows("Rename2"))
    }

    @Test("A button on the second line of a tall cell takes the click")
    func multiLineCellButton() throws {
        let harness = Harness(tall: true)
        harness.click(try harness.position(of: "Go1"))
        #expect(harness.ledger.pressed == ["go 1"], "pressed \(harness.ledger.pressed)")
        #expect(harness.ledger.selection == nil)
        harness.click(try harness.position(of: "row 2"))
        #expect(harness.ledger.selection == 2)
    }
}
