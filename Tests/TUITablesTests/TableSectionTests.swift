//  🖥️ TUI — A Terminal UI framework for Swift
//  TableSectionTests.swift
//
//  Sections among a table's rows (decisions A31): a header row — a view
//  across the table — above each section's rows, which the cursor steps over
//  and nothing selects, as SwiftUI's table does (measured on macOS 15.8); a
//  collapsible section's rows leaving and coming back by its header's
//  disclosure control, from the keyboard and the pointer.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUITables
@testable import TUITestSupport

@Observable
@MainActor
private final class Produce {
    var selection: Set<Int> = []
    var fruitsShown = true
    var collapsible = false
    var emptyMiddle = false
    /// Only the fruits' section: no vegetables, no "Last".
    var onlyFruits = false
    /// Every section empty.
    var noRows = false
    /// The vegetables' header grows: a `Spacer` under its title.
    var flexibleHeader = false
    /// The vegetables' header says when it is drawn over a raised background.
    var prominenceHeader = false
    /// The vegetables' header is three lines.
    var tallHeader = false
    /// The table draws a scrollbar.
    var scrollbar = false
    var rows = 4
    var menuSets: [[Int]] = []
}

private struct Item: Identifiable, Equatable {
    let id: Int
    var name: String
}

private struct ProduceApp: App {
    let produce: Produce?

    init() { produce = nil }

    init(_ produce: Produce) { self.produce = produce }

    var body: some Scene {
        WindowGroup {
            if let produce { ProducePage(produce: produce) }
        }
    }
}

private struct ProducePage: View {
    let produce: Produce

    private var fruits: [Item] {
        produce.noRows ? [] : (1...produce.rows).map { Item(id: $0, name: "fruit\($0)") }
    }
    private var vegetables: [Item] {
        produce.noRows ? [] : [Item(id: 11, name: "veg11"), Item(id: 12, name: "veg12")]
    }

    var body: some View {
        if produce.scrollbar {
            table.scrollIndicators(.visible)
        } else {
            table
        }
    }

    private var table: some View {
        Table(of: Item.self, selection: Bindable(produce).selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Code") { item in Text(verbatim: "#\(item.id)") }
        } rows: {
            if produce.collapsible {
                Section("Fruits", isExpanded: Bindable(produce).fruitsShown) {
                    ForEach(fruits) { TableRow($0) }
                }
            } else {
                Section("Fruits") {
                    ForEach(fruits) { TableRow($0) }
                }
            }
            if produce.emptyMiddle {
                Section("Nothing here") {
                    ForEach([Item]()) { TableRow($0) }
                }
            }
            if !produce.onlyFruits {
                Section {
                    ForEach(vegetables) { TableRow($0) }
                } header: {
                    if produce.prominenceHeader {
                        ProminenceProbe()
                    } else if produce.tallHeader {
                        Text(verbatim: "Veg\nmore\nlines")
                    } else if produce.flexibleHeader {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "Vegetables")
                            Spacer()
                        }
                    } else {
                        Text(verbatim: "Vegetables")
                    }
                }
                Section("Last") {
                    ForEach([Item]()) { TableRow($0) }
                }
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            Button("menu \(ids.sorted().description)") {}
        }
        .frame(height: 14)
    }
}

/// A header that names the background prominence it is drawn under.
private struct ProminenceProbe: View {
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(verbatim: prominence == .increased ? "Vegetables raised" : "Vegetables")
    }
}

@MainActor
private final class Harness {
    let produce = Produce()
    let app: HeadlessApp<ProduceApp>
    private var now: Int64 = 0

    init(configure: (Produce) -> Void = { _ in }) {
        configure(produce)
        app = HeadlessApp(ProduceApp(produce), width: 40, height: 18)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var lines: [String] { app.screen.map(\.stripped) }

    func line(of text: String) -> Int? { lines.firstIndex { $0.contains(text) } }

    func column(of text: String, on line: Int) -> Int? {
        lines[line].range(of: text).map { lines[line].distance(from: lines[line].startIndex, to: $0.lowerBound) }
    }

    func click(x: Int, y: Int, button: MouseButton = .left) {
        app.send(MouseEvent(button: button, phase: .pressed, x: x, y: y))
        frame()
        app.send(MouseEvent(button: button, phase: .released, x: x, y: y))
        frame()
    }

    func key(_ event: KeyEvent) {
        app.send(event)
        frame()
    }

    var screen: String { lines.joined(separator: "\n") }
}

@MainActor
@Suite("Sections among a table's rows")
struct TableSectionTests {
    @Test("Each section's header is drawn above its rows, in line with the first column")
    func headersAboveRows() throws {
        let harness = Harness()
        let fruits = try #require(harness.line(of: "Fruits"), "\(harness.screen)")
        let first = try #require(harness.line(of: "fruit1"))
        let vegetables = try #require(harness.line(of: "Vegetables"))
        let veg = try #require(harness.line(of: "veg11"))
        #expect(first == fruits + 1)
        #expect(vegetables == (harness.line(of: "fruit4") ?? -1) + 1)
        #expect(veg == vegetables + 1)
        // A section with no rows at the end still draws its header.
        let belowVeg12: Int = (harness.line(of: "veg12") ?? -1) + 1
        #expect(harness.line(of: "Last") == belowVeg12, "\(harness.screen)")
        #expect(harness.column(of: "Fruits", on: fruits) == harness.column(of: "fruit1", on: first))
        // A header row draws no cells.
        #expect(!harness.lines[fruits].contains("#"))
    }

    @Test("The cursor steps over a header, and a click on one selects nothing")
    func headersAreNotRows() throws {
        let harness = Harness()
        // To the last fruit, then one more: the first vegetable, past the header.
        for _ in 0..<4 { harness.key(KeyEvent(key: .down)) }
        harness.key(KeyEvent(key: .space))
        #expect(harness.produce.selection == [11], "\(harness.produce.selection)")
        let header = try #require(harness.line(of: "Fruits"))
        harness.click(x: 6, y: header)
        #expect(harness.produce.selection == [11], "a click on a header changed the selection")
        let fruit = try #require(harness.line(of: "fruit2"))
        harness.click(x: 6, y: fruit)
        #expect(harness.produce.selection == [2])
        // Select-all takes the rows and nothing else.
        harness.key(KeyEvent(key: .character("a"), ctrl: true))
        #expect(harness.produce.selection == [1, 2, 3, 4, 11, 12])
    }

    @Test("A right-click on a header is the table's empty space to its selection menu")
    func headerIsEmptySpaceToTheMenu() throws {
        let harness = Harness()
        let header = try #require(harness.line(of: "Fruits"))
        harness.app.send(MouseEvent(button: .right, phase: .pressed, x: 6, y: header))
        harness.app.send(MouseEvent(button: .right, phase: .released, x: 6, y: header))
        harness.frame()
        #expect(harness.line(of: "menu []") != nil, "\(harness.screen)")
    }

    @Test("A section with no rows between two others still draws its header")
    func emptySectionInTheMiddle() throws {
        let harness = Harness { $0.emptyMiddle = true }
        let empty = try #require(harness.line(of: "Nothing here"), "\(harness.screen)")
        #expect(harness.line(of: "Vegetables") == empty + 1)
        #expect(harness.line(of: "fruit4") == empty - 1)
    }

    @Test("A collapsible section's header toggles its rows, from the pointer and the keyboard")
    func collapsibleSection() throws {
        let harness = Harness { $0.collapsible = true }
        let header = try #require(harness.line(of: "Fruits"), "\(harness.screen)")
        #expect(harness.lines[header].contains("▼"), "\(harness.lines[header])")
        // Tab from the table reaches the header's control; Return closes it.
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .enter))
        #expect(!harness.produce.fruitsShown, "\(harness.screen)")
        #expect(harness.line(of: "fruit1") == nil, "\(harness.screen)")
        #expect(harness.lines[header].contains("▶"))
        // A click on the triangle opens it again.
        harness.click(x: harness.column(of: "▶", on: header) ?? 0, y: header)
        #expect(harness.produce.fruitsShown, "\(harness.screen)")
        #expect(harness.line(of: "fruit1") == header + 1)
    }

    @Test("A table whose only section is collapsed keeps the header, which expands it again")
    func collapsedOnlySection() throws {
        let harness = Harness {
            $0.collapsible = true
            $0.onlyFruits = true
        }
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .enter))
        #expect(!harness.produce.fruitsShown)
        let header = try #require(harness.line(of: "Fruits"), "the collapsed section lost its header:\n\(harness.screen)")
        #expect(harness.lines[header].contains("▶"), "\(harness.lines[header])")
        #expect(harness.line(of: "No items") == nil, "\(harness.screen)")
        // The keyboard still holds the header's control: Return opens it again.
        harness.key(KeyEvent(key: .enter))
        #expect(harness.produce.fruitsShown, "\(harness.screen)")
        #expect(harness.line(of: "fruit1") == header + 1, "\(harness.screen)")
        // And collapsed again, a click on the triangle opens it.
        harness.key(KeyEvent(key: .enter))
        #expect(!harness.produce.fruitsShown)
        harness.click(x: harness.column(of: "▶", on: header) ?? 0, y: header)
        #expect(harness.produce.fruitsShown, "\(harness.screen)")
    }

    @Test("A table whose sections have no rows draws their headers, not its placeholder")
    func rowlessSections() throws {
        let harness = Harness { $0.noRows = true }
        let fruits = try #require(harness.line(of: "Fruits"), "\(harness.screen)")
        #expect(harness.line(of: "Vegetables") == fruits + 1, "\(harness.screen)")
        #expect(harness.line(of: "Last") == fruits + 2, "\(harness.screen)")
        #expect(harness.line(of: "No items") == nil, "\(harness.screen)")
        // Drawn where the rows would be, in line with the first column.
        let title = try #require(harness.line(of: "Name"))
        #expect(fruits == title + 1)
        #expect(harness.column(of: "Fruits", on: fruits) == harness.column(of: "Name", on: title))
    }

    @Test("A header that grows is drawn at the height it is measured at, not the table's")
    func flexibleHeader() throws {
        let harness = Harness { $0.flexibleHeader = true }
        let vegetables = try #require(harness.line(of: "Vegetables"), "\(harness.screen)")
        let veg = try #require(harness.line(of: "veg11"), "the header pushed its rows away:\n\(harness.screen)")
        #expect(veg - vegetables <= 2, "\(harness.screen)")
        let belowVeg12: Int = (harness.line(of: "veg12") ?? -1) + 1
        #expect(harness.line(of: "Last") == belowVeg12, "\(harness.screen)")
        // A click lands on the row it is drawn on: the bands count the header
        // as many lines as it draws.
        harness.click(x: 6, y: veg + 1)
        #expect(harness.produce.selection == [12], "\(harness.produce.selection)\n\(harness.screen)")
    }

    @Test("A header is not raised with the focused, selected row it is carried by")
    func headerIsNotRaised() throws {
        let harness = Harness {
            $0.prominenceHeader = true
            $0.selection = [11]
        }
        // The cursor to veg11, the selected first row of the vegetables.
        for _ in 0..<4 { harness.key(KeyEvent(key: .down)) }
        #expect(harness.line(of: "Vegetables") != nil, "\(harness.screen)")
        #expect(harness.line(of: "Vegetables raised") == nil, "\(harness.screen)")
    }

    @Test("A header that changes height, and not number, moves the scrollbar's extent")
    func headerHeightMovesTheExtent() throws {
        let changed = Harness {
            $0.rows = 12
            $0.scrollbar = true
        }
        changed.produce.tallHeader = true
        changed.frame()
        let fresh = Harness {
            $0.rows = 12
            $0.scrollbar = true
            $0.tallHeader = true
        }
        #expect(changed.screen == fresh.screen, "\(changed.screen)\n--- fresh:\n\(fresh.screen)")
    }

    @Test("Scrolled, the headers scroll with their rows and the clicks still land on the rows")
    func scrolledSections() throws {
        let harness = Harness { $0.rows = 12 }
        for _ in 0..<13 { harness.key(KeyEvent(key: .down)) }
        harness.frame()
        let veg = try #require(harness.line(of: "veg12"), "\(harness.screen)")
        #expect(harness.line(of: "Vegetables") != nil, "\(harness.screen)")
        harness.click(x: 6, y: veg)
        #expect(harness.produce.selection == [12], "\(harness.produce.selection)\n\(harness.screen)")
        let header = try #require(harness.line(of: "Vegetables"))
        harness.click(x: 6, y: header)
        #expect(harness.produce.selection == [12])
    }
}
