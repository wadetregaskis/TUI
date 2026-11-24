//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorSidewaysRowTests.swift
//
//  A row of an editor that scrolls sideways is drawn from the character its
//  window starts in, found from the line's sampled cells (`LineCells`), and
//  stops at the window's end (H-88). What it draws must be what the walk of
//  the whole line drew (`referenceStyledRow`): over random lines of tabs, wide,
//  combining, zero-width and control characters, emoji ZWJ sequences and
//  flags, at random scroll columns, mid-character ones among them, with a
//  caret, a selection, find matches and style runs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("TextEditor: a sideways row drawn from its window")
struct TextEditorSidewaysRowTests {
    typealias RowCaret = _TextEditorCore.RowCaret
    typealias RowStyling = _TextEditorCore.RowStyling

    /// What a line is made of: one-cell ASCII, a tab, wide CJK, a combining
    /// accent, a ZWJ emoji, a flag, a ZWSP (drawn as a one-cell U+FFFD), an ESC.
    static let pieces = ["a", "b", "z", " ", "\t", "漢", "한", "e\u{301}", "x\u{308}\u{301}", "👩‍💻", "🇯🇵", "\u{200B}", "\u{1B}"]

    static let tabWidths: [TabWidth] = [.periodic(4), .periodic(8), .periodic(1), .fixed(3), .fixed(1)]

    /// A line of up to 700 pieces: every fourth of ASCII and tabs alone, every
    /// fourth of letters alone (one cell a character), the rest of anything.
    static func line(_ random: inout SplitMix, trial: Int) -> TextCharacters {
        let pieces = trial.isMultiple(of: 4) ? ["a", "b", " ", "\t"] : trial % 4 == 1 ? ["a", "b", " "] : Self.pieces
        var text = ""
        for _ in 0..<Int.random(in: 0...700, using: &random) { text += pieces.randomElement(using: &random)! }
        return TextCharacters(text)
    }

    @Test("A line's sampled cells say what a walk from its start says, at every character and column")
    func cellsMatchTheWalk() {
        var random = SplitMix(state: 0x88)
        for trial in 0..<200 {
            let line = Self.line(&random, trial: trial)
            let tabWidth = Self.tabWidths.randomElement(using: &random)!
            let cells = LineCells(line, tabWidth: tabWidth)
            var wrong: [String] = []
            for index in 0...line.count {
                let column = cells.column(of: index, in: line)
                let walked = TabLayout.displayColumn(ofCharIndex: index, in: line, tabWidth: tabWidth)
                if column != walked { wrong.append("column(of: \(index)) \(column), not \(walked)") }
            }
            if cells.total != TabLayout.displayColumn(ofCharIndex: line.count, in: line, tabWidth: tabWidth) {
                wrong.append("total \(cells.total)")
            }
            for column in -3...(cells.total + 3) {
                let index = cells.index(atColumn: column, in: line)
                let walked = TabLayout.charIndex(forDisplayColumn: column, in: line, tabWidth: tabWidth)
                if index != walked { wrong.append("index(atColumn: \(column)) \(index), not \(walked)") }
                // A walk may start there: a character at or before the one
                // the column is in, at its own column.
                let start = cells.start(atOrBefore: column)
                if start.index > walked || start.column > max(0, column)
                    || start.column != TabLayout.displayColumn(ofCharIndex: start.index, in: line, tabWidth: tabWidth)
                {
                    wrong.append("start(atOrBefore: \(column)) \(start)")
                }
            }
            #expect(wrong.isEmpty, "trial \(trial), \(tabWidth): \(wrong.prefix(5))")
        }
    }

    @Test("A row drawn from its window's sample is the row the whole line's walk drew")
    func rowsMatchTheWholeWalk() {
        let core = _TextEditorCore(
            text: .constant(""), focusID: nil, isDisabled: false, menuTarget: TextEditingMenuTarget())
        let environment = EnvironmentValues()
        let palette = environment.palette
        let field = palette.fieldBackground.resolve(with: palette)
        let stylings = [
            RowStyling(palette: palette, isDisabled: false, background: field),
            RowStyling(palette: palette, isDisabled: false, background: nil),
            RowStyling(palette: palette, isDisabled: true, background: field),
        ]
        // The caret as the editor sets it up (`rowCaret(column:styling:background:context:)`).
        let setup = TextFieldContentRenderer.caretSetup(
            palette: palette, background: field, textForeground: stylings[0].text,
            cursorStyle: environment.textCursorStyle,
            speed: environment.indicatorAnimationSpeeds.speed(for: .textCursor), cursorTimer: nil, timing: nil,
            appearsActive: true)
        let cycle = RowCaret.Cycle(shape: environment.textCursorStyle.shape, cursor: setup.cycle, colors: setup.colors)
        let inks: [Color] = [.red, .green, .blue]
        var random = SplitMix(state: 0x4888)
        var compared = 0
        for trial in 0..<600 {
            let line = Self.line(&random, trial: trial)
            let tabWidth = Self.tabWidths.randomElement(using: &random)!
            let cells = LineCells(line, tabWidth: tabWidth)
            func column(_ index: Int) -> Int { TabLayout.displayColumn(ofCharIndex: index, in: line, tabWidth: tabWidth) }
            func characters() -> Range<Int> {
                let lower = Int.random(in: 0...line.count, using: &random)
                return lower..<Int.random(in: lower...line.count, using: &random)
            }
            let width = Int.random(in: 1...40, using: &random)
            let leading = Bool.random(using: &random) ? 0 : Int.random(in: 0...12, using: &random)
            // Anywhere, past the end too; every third trial inside a character
            // more than a cell wide, a tab or a wide one, where the window's
            // left edge cuts it.
            var scroll = Int.random(in: 0...(cells.total + 6), using: &random)
            if trial.isMultiple(of: 3), let wide = line.indices.filter({ column($0 + 1) - column($0) > 1 }).randomElement(using: &random) {
                scroll = column(wide) + Int.random(in: 1..<(column(wide + 1) - column(wide)), using: &random) + leading
            }
            let selection = Bool.random(using: &random) ? nil : characters()
            let caret = Bool.random(using: &random) ? nil : Int.random(in: 0...line.count, using: &random)
            let matches = (0..<Int.random(in: 0...3, using: &random)).map { _ in characters() }
                .sorted { $0.lowerBound < $1.lowerBound }.map { column($0.lowerBound)..<column($0.upperBound) }
            var styles: [EditorStyledRun] = []
            var next = 0
            while next < line.count, Bool.random(using: &random) {
                let lower = Int.random(in: next...line.count, using: &random)
                let upper = Int.random(in: lower...line.count, using: &random)
                if lower < upper {
                    styles.append(EditorStyledRun(columns: lower..<upper, foreground: inks.randomElement(using: &random), background: nil))
                }
                next = upper + 1
            }
            let styling = stylings.randomElement(using: &random)!
            let rowCaret = caret.map { RowCaret(column: column($0), cycle: cycle) }
            let selected = selection.map { column($0.lowerBound)..<column($0.upperBound) }
            let drawn = core.styledRow(
                line[...], tabWidth: tabWidth, scrollColumn: scroll, leadingCells: leading, width: width,
                from: cells.start(atOrBefore: scroll - leading), caret: rowCaret, selection: selected,
                matches: matches, styles: styles, styling: styling)
            let walked = core.referenceStyledRow(
                line[...], tabWidth: tabWidth, scrollColumn: scroll, leadingCells: leading, width: width,
                caret: rowCaret, selection: selected, matches: matches, styles: styles, styling: styling)
            #expect(drawn.line == walked.line, "trial \(trial): scroll \(scroll), width \(width), \(tabWidth)")
            #expect(drawn.claims == walked.claims, "trial \(trial)")
            #expect(drawn.caret == walked.caret, "trial \(trial)")
            compared += 1
        }
        #expect(compared == 600)
    }

    /// A focused editor, sideways, `width` × `height`, over `text`.
    struct Page: View {
        let text: TextEditorSidewaysCostTests.Box
        let width: Int
        let height: Int
        var body: some View {
            TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                .frame(width: width, height: height)
                .textEditorWrapsLines(false)
        }
    }

    @Test("Far along long lines, the editor draws the selection as the whole line's walk drew it")
    func selectionFarAlong() throws {
        var random = SplitMix(state: 0x488)
        let lines = (0..<6).map { _ in
            (0..<3_000).map { _ in Self.pieces.randomElement(using: &random)! }.joined()
        }
        let (width, height) = (30, 6)
        let harness = InputChainHarness(width: width, height: height)
        let page = Page(text: .init(lines.joined(separator: "\n")), width: width, height: height)
        harness.frame(page)
        harness.frame(page)
        let handler = try #require(harness.focusManager.currentFocused as? TextEditorHandler)
        handler.moveCursor(toLine: 1, column: 2_400)
        handler.startOrExtendSelection()
        handler.moveCursor(toLine: 4, column: 2_450)
        let frame = harness.frame(page).lines
        #expect(handler.scrollColumn > 2_000)
        let drawnLines = handler.displayLines()
        let environment = harness.context.environment
        let palette = environment.palette
        let styling = RowStyling(
            in: environment, isDisabled: false, background: palette.fieldBackground.resolve(with: palette))
        let core = _TextEditorCore(
            text: .constant(""), focusID: nil, isDisabled: false, menuTarget: TextEditingMenuTarget())
        for row in 0..<height {
            let line = drawnLines[row]
            let selection = handler.selectedColumns(inLine: row, lineLength: line.count).map {
                TabLayout.displayColumn(ofCharIndex: $0.lowerBound, in: line, tabWidth: environment.tabWidth)
                    ..< TabLayout.displayColumn(ofCharIndex: $0.upperBound, in: line, tabWidth: environment.tabWidth)
            }
            let walked = core.referenceStyledRow(
                line[...], tabWidth: environment.tabWidth, scrollColumn: handler.scrollColumn, width: width, caret: nil,
                selection: selection, styling: styling)
            let cells = TextEditorHighlightLayerTests.cells
            #expect(cells(frame[row]).map(\.character) == cells(walked.line).map(\.character), "row \(row)")
            #expect(cells(frame[row]).map(\.state) == cells(walked.line).map(\.state), "row \(row)")
        }
    }
}
