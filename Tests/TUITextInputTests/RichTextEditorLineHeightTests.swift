//  🖥️ TUI — A Terminal UI framework for Swift
//  RichTextEditorLineHeightTests.swift
//
//  An attributed `TextEditor`'s paragraph line height (G3 L4, the owner's
//  rulings A-ATTRED-3 of 2026-11-17 and A-ATTRED-13 (b) of 2026-11-19): a
//  wrapping editor draws blank rows after each row of a paragraph that takes
//  more than one a line; they belong to the row above for a click, the
//  vertical keys step over them, the caret is never on one, and the scroll
//  counts them.
//
//  Each case runs through SwiftUI's `lineHeight` where it exists (macOS 26 on
//  a Mac, which CI's macOS 26 lane runs; Linux, Windows) and, everywhere,
//  through an attribute of the test's own read by the handler's seam
//  (`lineRowRuns`), since a Mac before macOS 26 has no line height at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

/// The rows a line, as a test states them: bounded by paragraphs, as
/// `lineHeight` is.
private enum TestLineRowsAttribute: AttributedStringKey {
    typealias Value = Int
    static let name = "TUITests.LineRows"
    static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
}

/// How a test states a paragraph's rows a line.
enum LineRowsSpelling: String, CaseIterable, Sendable, CustomStringConvertible {
    /// SwiftUI's `lineHeight`, `.multiple(factor:)`: Core Text's on a Mac, so
    /// macOS 26 only there; TUI's own elsewhere.
    case lineHeight
    /// The test's own attribute, read through the handler's seam.
    case testAttribute

    /// The spellings this machine can run: both, but on a Mac before macOS 26,
    /// which has only the test's.
    static var available: [Self] {
        #if canImport(CoreText)
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) { return allCases }
            return [.testAttribute]
        #else
            return allCases
        #endif
    }

    var description: String { rawValue }

    /// Sets the paragraph `range` is in to take `rows` rows a line.
    func set(_ string: inout AttributedString, _ range: Range<AttributedString.Index>, rows: Int) {
        switch self {
        case .lineHeight:
            #if canImport(CoreText)
                guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else {
                    preconditionFailure("SwiftUI's lineHeight needs macOS 26 here; run only `available` spellings")
                }
            #endif
            string[range].lineHeight = .multiple(factor: CGFloat(rows))
        case .testAttribute:
            string[range][TestLineRowsAttribute.self] = rows
        }
    }

    /// Has `handler` read this spelling, and its line heights afresh.
    func prepare(_ handler: TextEditorHandler) {
        guard self == .testAttribute else { return }
        handler.lineRowRuns = Self.testRuns
        handler.keptLineGaps = .unread
    }

    /// The test attribute's stretches, as ``TextEditorHandler/statedLineRows(in:)``
    /// gives `lineHeight`'s.
    static func testRuns(_ text: AttributedSubstring) -> [(range: Range<AttributedString.Index>, rows: Int)] {
        text.runs[TestLineRowsAttribute.self].compactMap { rows, range in rows.map { (range, $0) } }
    }
}

@MainActor
@Suite("Text editor over an attributed string: paragraph line height")
struct RichTextEditorLineHeightTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// An editor 12 cells wide and `height` tall over `text`, its line heights
    /// read `spelling`'s way: its handler, and a render's stripped rows, their
    /// first 11 cells (the twelfth is a scroll bar's, where one is drawn).
    private func editor(
        _ text: Box<AttributedString>, _ spelling: LineRowsSpelling, height: Int = 6, wraps: Bool = true
    ) -> (handler: TextEditorHandler, render: () -> [String]) {
        let context = makeRenderContext(width: 12, height: height)
        let view = TextEditor(text: text.binding).textEditorWrapsLines(wraps).frame(width: 12, height: height)
        _ = renderToBuffer(view, context: context)
        let handler = context.environment.focusManager!.activeSection!.focusables
            .compactMap { $0 as? TextEditorHandler }.first!
        spelling.prepare(handler)
        let render = {
            renderToBuffer(view, context: context).lines.map {
                String($0.stripped.prefix(11)).replacingOccurrences(of: " +$", with: "", options: .regularExpression)
            }
        }
        _ = render()
        return (handler, render)
    }

    /// `paragraphs` joined by line breaks, those given a count taking that
    /// many rows a line.
    private func document(_ paragraphs: [(String, Int?)], _ spelling: LineRowsSpelling) -> Box<AttributedString> {
        var string = AttributedString(paragraphs.map(\.0).joined(separator: "\n"))
        for (words, rows) in paragraphs {
            guard let rows, let range = string.range(of: words) else { continue }
            spelling.set(&string, range, rows: rows)
        }
        return Box(string)
    }

    @Test("A paragraph's rows are each followed by its blank rows", arguments: LineRowsSpelling.available)
    func drawn(_ spelling: LineRowsSpelling) {
        // "alpha beta gamma" wraps at 12 into "alpha beta" and "gamma".
        let drawn = editor(document([("alpha beta gamma", 2), ("hi", nil), ("yo", 3)], spelling), spelling)
        #expect(drawn.render() == ["alpha beta", "", "gamma", "", "hi", "yo"])
        #expect(drawn.handler.wrappedRows()?.rowCount == 6, "none after the last row")
    }

    @Test("The caret is drawn on its row, counting the blank rows above it", arguments: LineRowsSpelling.available)
    func caretCell(_ spelling: LineRowsSpelling) {
        let drawn = editor(document([("alpha", 2), ("hi", 2), ("yo", nil)], spelling), spelling)
        drawn.handler.moveCursor(toLine: 2, column: 1)
        _ = drawn.render()
        #expect(drawn.handler.insertionPoint == CellPoint(x: 1, y: 4))
        // On a paragraph's second row: after the first row's blank one.
        let wrapped = editor(document([("alpha beta gamma", 2), ("hi", nil)], spelling), spelling)
        wrapped.handler.moveCursor(toLine: 0, column: 13)
        _ = wrapped.render()
        #expect(wrapped.handler.insertionPoint == CellPoint(x: 2, y: 2))
        _ = wrapped.handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(wrapped.handler.cursorLine == 0 && wrapped.handler.cursorColumn == 2)
    }

    @Test("Down and Up step over the blank rows", arguments: LineRowsSpelling.available)
    func verticalKeys(_ spelling: LineRowsSpelling) {
        let drawn = editor(document([("alpha", 3), ("hi", nil)], spelling), spelling)
        drawn.handler.moveCursor(toLine: 0, column: 1)
        _ = drawn.render()
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(drawn.handler.cursorLine == 1 && drawn.handler.cursorColumn == 1)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(drawn.handler.cursorLine == 0 && drawn.handler.cursorColumn == 1)
    }

    @Test("A click on a blank row lands on the row above it", arguments: LineRowsSpelling.available)
    func click(_ spelling: LineRowsSpelling) throws {
        let drawn = editor(document([("alpha", 3), ("hi", nil)], spelling), spelling)
        let rows = try #require(drawn.handler.wrappedRows())
        let landed = [1, 2, 3].map { drawn.handler.position(atScreenRow: $0, column: 2, in: rows) }
        #expect(landed.map(\.line) == [0, 0, 1])
        #expect(landed.map(\.column) == [2, 2, 2])
    }

    @Test(
        "The scroll counts the blank rows: the caret's row stays on screen, and the wheel moves a row at a time",
        arguments: LineRowsSpelling.available)
    func scrolling(_ spelling: LineRowsSpelling) {
        // Seven rows: a, blank, b, blank, c, blank, d.
        let paragraphs: [(String, Int?)] = [("a", 2), ("b", 2), ("c", 2), ("d", 2)]
        let drawn = editor(document(paragraphs, spelling), spelling, height: 4)
        #expect(drawn.handler.wrappedRows()?.rowCount == 7)
        drawn.handler.moveCursor(toLine: 3, column: 1)
        #expect(drawn.render() == ["", "c", "", "d"])
        #expect(drawn.handler.insertionPoint == CellPoint(x: 1, y: 3))
        drawn.handler.moveCursor(toLine: 0, column: 0)
        #expect(drawn.render().first == "a")
        #expect(drawn.handler.scrollByWheel(1, height: 4))
        #expect(drawn.render() == ["", "b", "", "c"])
    }

    @Test(
        "Typing keeps a paragraph's rows, a paragraph split from it takes them, and the lines read after an edit are those read whole",
        arguments: LineRowsSpelling.available)
    func typing(_ spelling: LineRowsSpelling) throws {
        let text = document([("alpha", 2), ("hi", nil)], spelling)
        let drawn = editor(text, spelling)
        drawn.handler.moveCursor(toLine: 0, column: 2)
        for key: Key in [.character("!"), .enter, .character("x")] {
            _ = drawn.handler.handleKeyEvent(KeyEvent(key: key))
        }
        #expect(String(text.value.characters) == "al!\nxpha\nhi")
        #expect(drawn.render() == ["al!", "", "xpha", "", "hi", ""])
        // What the edits left, against the whole value read afresh.
        let kept = drawn.handler.lineGaps()
        let layout = drawn.handler.layout()
        let whole = TextEditorHandler.lineGaps(
            in: text.value, lines: layout.lines.indices, characterStarts: layout.characterStarts,
            reading: drawn.handler.lineRowRuns)
        #expect(kept == whole)
        #expect(whole == [1, 1, 0])
    }

    @Test("A block takes no row from the blank ones", arguments: LineRowsSpelling.available)
    func block(_ spelling: LineRowsSpelling) throws {
        let drawn = editor(document([("alpha", 2), ("hi", nil)], spelling), spelling)
        drawn.handler.beginBlock(at: CellPoint(x: 0, y: 0), shift: false)
        drawn.handler.extendBlock(to: CellPoint(x: 2, y: 2), shift: false)
        let block = try #require(drawn.handler.block)
        #expect(drawn.handler.blockText(block) == "al\nhi")
    }

    @Test(
        "Scrolling sideways, each line is followed by its blank rows, and the caret, a click, the keys and the scroll count them",
        arguments: LineRowsSpelling.available)
    func sideways(_ spelling: LineRowsSpelling) {
        let drawn = editor(document([("alpha", 2), ("hi", 3), ("yo", nil)], spelling), spelling, height: 4, wraps: false)
        #expect(drawn.render() == ["alpha", "", "hi", ""])
        drawn.handler.moveCursor(toLine: 1, column: 1)
        _ = drawn.render()
        #expect(drawn.handler.insertionPoint == CellPoint(x: 1, y: 2))
        // The block's grid is the rows drawn, and a blank one holds nothing.
        drawn.handler.beginBlock(at: drawn.handler.gridPoint(atScreenRow: 0, column: 0), shift: false)
        drawn.handler.extendBlock(to: drawn.handler.gridPoint(atScreenRow: 2, column: 2), shift: false)
        #expect(drawn.handler.block.map { drawn.handler.blockText($0) } == "al\nhi")
        drawn.handler.block = nil
        drawn.handler.moveCursor(toLine: 0, column: 3)
        // Down to the last line scrolls it on: six rows, four shown.
        for _ in 0..<2 { _ = drawn.handler.handleKeyEvent(KeyEvent(key: .down)) }
        #expect(drawn.handler.cursorLine == 2)
        #expect(drawn.render() == ["hi", "", "", "yo"])
        #expect(drawn.handler.insertionPoint?.y == 3)
        // The wheel moves a row at a time, blank ones too.
        #expect(drawn.handler.scrollByWheel(-1, height: 4))
        #expect(drawn.render() == ["", "hi", "", ""])
    }

    @Test("A value written whole is read afresh", arguments: LineRowsSpelling.available)
    func takenWhole(_ spelling: LineRowsSpelling) {
        let text = document([("alpha", nil), ("hi", nil)], spelling)
        let drawn = editor(text, spelling)
        #expect(drawn.render().prefix(3) == ["alpha", "hi", ""])
        spelling.set(&text.value, text.value.range(of: "alpha")!, rows: 2)
        #expect(drawn.render().prefix(3) == ["alpha", "", "hi"])
    }
}
