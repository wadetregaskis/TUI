//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutOverlayLayoutTests.swift
//
//  How F1's list lays itself out: in a bordered dialog, centred, its sections
//  in as many columns as the width holds, each kept whole where it can be, a
//  long one carried on into the next column under its heading again, and
//  scrolling only downwards, only when nothing else fits.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
import TUICommands
import TUICore
import TUIFoundation
import TUIPresentation
import TUITesting

// MARK: - The Layout

@Suite("The columns F1's list is laid out in")
struct ShortcutOverlayColumnsTests {
    private func shape(_ columns: ShortcutOverlayColumns) -> [[String]] {
        columns.columns.map { $0.map { "\($0.section):\($0.rows.lowerBound)..<\($0.rows.upperBound)" } }
    }

    @Test("Sections that fit side by side each get a column")
    func sideBySide() {
        let columns = ShortcutOverlayColumns.laidOut(rowCounts: [3, 3, 3], maxColumns: 3, availableHeight: 20)
        #expect(shape(columns) == [["0:0..<3"], ["1:0..<3"], ["2:0..<3"]])
        #expect(columns.height == 4)
    }

    @Test("Short sections share a column beside a long one")
    func shortSectionsShare() {
        let columns = ShortcutOverlayColumns.laidOut(rowCounts: [8, 2, 2], maxColumns: 3, availableHeight: 20)
        #expect(shape(columns) == [["0:0..<8"], ["1:0..<2", "2:0..<2"]])
        #expect(columns.height == 9)
    }

    @Test("A long section is kept whole while the height holds it")
    func longKeptWhole() {
        let columns = ShortcutOverlayColumns.laidOut(rowCounts: [20], maxColumns: 3, availableHeight: 30)
        #expect(shape(columns) == [["0:0..<20"]])
    }

    @Test("A section too tall for the height carries on into the next columns")
    func longSplits() {
        let columns = ShortcutOverlayColumns.laidOut(rowCounts: [20], maxColumns: 3, availableHeight: 10)
        #expect(shape(columns) == [["0:0..<7"], ["0:7..<14"], ["0:14..<20"]])
        #expect(columns.height == 8)
        #expect(columns.splitsASection)
    }

    @Test("A section a column holds is moved, not split, when a long one is")
    func shortNeverSplits() {
        let columns = ShortcutOverlayColumns.laidOut(rowCounts: [10, 3], maxColumns: 2, availableHeight: 6)
        #expect(shape(columns) == [["0:0..<8"], ["0:8..<10", "1:0..<3"]])
    }

    @Test("Short sections are split too where that, and only that, makes the list fit")
    func shortSplitToFit() {
        let fits = ShortcutOverlayColumns.laidOut(rowCounts: [4, 4, 4], maxColumns: 2, availableHeight: 9)
        #expect(shape(fits) == [["0:0..<4", "1:0..<2"], ["1:2..<4", "2:0..<4"]])
        let scrollsAnyway = ShortcutOverlayColumns.laidOut(rowCounts: [4, 4, 4], maxColumns: 2, availableHeight: 8)
        #expect(shape(scrollsAnyway) == [["0:0..<4", "1:0..<4"], ["2:0..<4"]])
    }

    @Test("A heading isn't left at a column's foot over a single row")
    func noLoneHeading() throws {
        // Height 7: section 0 takes 4 rows, leaving room for a heading and
        // one row of section 1 after the gap; it starts the next column.
        let columns = try #require(ShortcutOverlayColumns.flowed([3, 9], height: 7, maxColumns: 3))
        #expect(shape(columns) == [["0:0..<3"], ["1:0..<6"], ["1:6..<9"]])
    }

    @Test("One column never splits, however tall")
    func oneColumn() {
        let columns = ShortcutOverlayColumns.laidOut(rowCounts: [20, 5], maxColumns: 1, availableHeight: 5)
        #expect(shape(columns) == [["0:0..<20", "1:0..<5"]])
    }
}

// MARK: - On the Screen

/// Four menus of five commands each, and a page of four. The app names
/// itself (`aboutPanel`), or its app menu takes the test runner's process
/// name (`TUICommandsTests-test-runner` on Linux with Swift 6.4, too wide
/// for two columns in 80 columns; `xctest` elsewhere, narrow enough for six
/// columns in 200 without splitting).
private struct MenusApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack {
                ForEach(Array("abcd"), id: \.self) { letter in
                    Button("Page " + String(letter)) {}.keyboardShortcut(KeyEquivalent(letter), modifiers: .control)
                }
            }
        }
        .commands {
            CommandMenu("Alpha") { Self.commands("efghi") }
            CommandMenu("Bravo") { Self.commands("jklmn") }
            CommandMenu("Charlie") { Self.commands("oprtu") }
            CommandMenu("Delta") { Self.commands("vwxyz") }
        }
        .aboutPanel(applicationName: "Demo Shortcut Showcase")
    }

    @ViewBuilder private static func commands(_ letters: String) -> some View {
        ForEach(Array(letters), id: \.self) { letter in
            Button("Command " + String(letter)) {}.keyboardShortcut(KeyEquivalent(letter), modifiers: .control)
        }
    }
}

@MainActor
@Suite("F1's list on the screen", .serialized)
struct KeyboardShortcutOverlayScreenTests {
    private let headings = ["Alpha", "Bravo", "Charlie", "Delta", "On This Screen", "General"]

    private func shown(width: Int, height: Int) -> TestApp {
        let app = TestApp(MenusApp(), width: width, height: height)
        app.advance(by: .milliseconds(40))
        app.press(KeyEvent(key: .f1))
        app.advance(by: .milliseconds(40))
        return app
    }

    /// The rows of the dialog where two or more of the sections' headings
    /// start together (excluding the menu bar row behind it, which carries
    /// the menu names `Alpha`, `Bravo`, …).
    private func rowsWithSeveralHeadings(_ app: TestApp) -> Int {
        app.screen.lines.filter { line in
            line.contains("│") && headings.filter { line.contains($0 + " ") || line.hasSuffix($0) }.count > 1
        }
        .count
    }

    private func everyCommandShows(_ app: TestApp) -> Bool {
        Array("abcdefghijklmnoprtuvwxyz").allSatisfy { letter in
            app.screen.lines.contains { $0.contains("Command \(letter)") || $0.contains("Page \(letter)") }
        }
    }

    @Test("It's a bordered dialog, centred", arguments: [(80, 40), (120, 40), (200, 50)])
    func borderedAndCentred(size: (width: Int, height: Int)) throws {
        let app = shown(width: size.width, height: size.height)
        let lines = app.screen.lines
        let top = try #require(lines.firstIndex { $0.contains("Keyboard Shortcuts") }, "\(app.screen)")
        let border = lines[top]
        let left = try #require(border.firstIndex { "╭┌╔┏".contains($0) }, "\(app.screen)")
        let right = try #require(border.lastIndex { "╮┐╗┓".contains($0) }, "\(app.screen)")
        // The screen's lines end at their last drawn cell.
        let leading = border.distance(from: border.startIndex, to: left)
        let trailing = size.width - 1 - border.distance(from: border.startIndex, to: right)
        #expect(abs(leading - trailing) <= 1, "\(leading) and \(trailing) cells either side: \(app.screen)")
        #expect(leading > 0, "\(app.screen)")
    }

    @Test("Wide, its sections sit side by side and nothing scrolls", arguments: [(120, 40), (200, 50)])
    func wide(size: (width: Int, height: Int)) {
        let app = shown(width: size.width, height: size.height)
        #expect(rowsWithSeveralHeadings(app) > 0, "\(app.screen)")
        #expect(everyCommandShows(app), "\(app.screen)")
        #expect(!app.screen.contains("(cont.)"), "\(app.screen)")
    }

    @Test("At 80 columns it takes two or more columns")
    func eighty() {
        let app = shown(width: 80, height: 40)
        #expect(rowsWithSeveralHeadings(app) > 0, "\(app.screen)")
        #expect(everyCommandShows(app), "\(app.screen)")
    }

    @Test("Wide and short, sections carry on into the next column rather than scroll")
    func wideAndShort() {
        let app = shown(width: 200, height: 18)
        #expect(everyCommandShows(app), "\(app.screen)")
        #expect(app.screen.contains("(cont.)"), "\(app.screen)")
    }

    @Test("At 40 columns it's one column, which scrolls downwards")
    func narrow() {
        let app = shown(width: 40, height: 16)
        #expect(rowsWithSeveralHeadings(app) == 0, "\(app.screen)")
        #expect(app.screen.contains("On This Screen"), "\(app.screen)")
        #expect(!app.screen.contains("Next Control"), "\(app.screen)")
        for _ in 0..<8 {
            app.press(KeyEvent(key: .pageDown))
            app.advance(by: .milliseconds(40))
        }
        #expect(app.screen.contains("Next Control"), "\(app.screen)")
    }
}
