//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorStyledRowsTests.swift
//
//  An editor's rows drawn in its lines' own styles (G3 L2, B-ATTRED-2, 5):
//  colours and decoration by stretches of a line, under the selection, read
//  once a line and kept until an edit changes the line.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Text editor: rows drawn in their lines' styles")
struct TextEditorStyledRowsTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// Each visible cell of `line` with the SGR state in force on it.
    private func cells(_ line: String) -> [(character: Character, state: SGRState)] {
        var state = SGRState()
        var result: [(character: Character, state: SGRState)] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): result.append((character, state))
            }
        }
        return result
    }

    private static let red = Color.rgb(200, 30, 30)

    /// The ink a cell drawn in `colour` states.
    private static func ink(_ colour: Color) -> SGRState {
        var style = TextStyle()
        style.foregroundColor = colour.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// "abcd" bold and red, "efgh" italic and underlined, the rest plain.
    private static func styler(_ line: Int) -> [EditorStyledRun] {
        var bold = CellDecoration()
        bold.isBold = true
        var italic = CellDecoration()
        italic.isItalic = true
        italic.underline = .single
        return [
            EditorStyledRun(columns: 0..<4, foreground: red, decoration: bold),
            EditorStyledRun(columns: 4..<8, decoration: italic),
        ]
    }

    /// An editor over `text`, rendered once so its handler exists, the
    /// styler given to it, and rendered again: its handler and buffer.
    private func editor(
        _ box: Box, styler: ((Int) -> [EditorStyledRun])?, select: Range<Int>? = nil
    ) -> (handler: TextEditorHandler, buffer: FrameBuffer, render: () -> FrameBuffer) {
        let context = makeRenderContext(width: 20, height: 3)
        let view = TextEditor(text: box.binding).frame(width: 20, height: 3)
        _ = renderToBuffer(view, context: context)
        let handler = context.environment.focusManager!.activeSection!.focusables
            .compactMap { $0 as? TextEditorHandler }.first!
        handler.replaceLineStyler(styler)
        if let select {
            handler.moveCursor(toLine: 0, column: select.lowerBound)
            handler.selectionAnchor = handler.cursor
            handler.startOrExtendSelection()
            handler.moveCursor(toLine: 0, column: select.upperBound)
        }
        return (handler, renderToBuffer(view, context: context), { renderToBuffer(view, context: context) })
    }

    @Test("A line's runs draw their colours and attributes; the rest of the row is the editor's own")
    func runsAreDrawn() throws {
        let drawn = editor(Box("abcdefghij\nxyz"), styler: Self.styler)
        let row = cells(try #require(drawn.buffer.lines.first))
        let plain = cells(try #require(editor(Box("abcdefghij\nxyz"), styler: nil).buffer.lines.first))
        // Cell 0 is the caret's, which draws in its own colours, as on any cell.
        for cell in row[1..<4] {
            #expect(cell.state.isBold, "\(cell.character) bold")
            #expect(cell.state.foregroundColour == Self.ink(Self.red).foregroundColour, "\(cell.character) red")
        }
        for cell in row[4..<8] {
            #expect(cell.state.isItalic && cell.state.isOn(4), "\(cell.character) italic and underlined")
            #expect(!cell.state.isBold)
        }
        // Past the runs, drawn as an editor with no styles draws them.
        for (styled, own) in zip(row[8...], plain[8...]) {
            #expect(styled.state == own.state, "\(styled.character)")
        }
    }

    @Test("No styler draws the row byte for byte as before")
    func noStylerIsUnchanged() throws {
        let box = Box("abc\tdef")
        let first = editor(box, styler: nil)
        let empty = editor(box, styler: { _ in [] })
        #expect(first.buffer.lines == empty.buffer.lines)
    }

    @Test("A selection's colours win over a run's, and its attributes stay")
    func selectionOverRun() throws {
        let drawn = editor(Box("abcdefghij"), styler: Self.styler, select: 1..<3)
        let row = cells(try #require(drawn.buffer.lines.first))
        #expect(row[1].state.isBold && row[2].state.isBold, "the bold stays under the selection")
        #expect(row[1].state.foregroundColour != Self.ink(Self.red).foregroundColour, "the selection's ink wins")
        #expect(row[0].state.foregroundColour == Self.ink(Self.red).foregroundColour)
    }

    @Test("A line is read once, and again only after an edit changes it; lines after an edit move with it")
    func cacheKeepsLinesUntilEdited() throws {
        let reads = Box("")
        let box = Box("one\ntwo\nthree")
        let drawn = editor(box, styler: { line in
            reads.value += "\(line)"
            return []
        })
        #expect(reads.value == "012")
        _ = drawn.render()
        #expect(reads.value == "012", "kept between frames")
        // An edit on line 1 reads line 1 again, and nothing else.
        drawn.handler.moveCursor(toLine: 1, column: 0)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("X")))
        _ = drawn.render()
        #expect(reads.value == "0121")
        // A new line after line 0 moves "Xtwo" and "three" down one: only the
        // new line is read, since line 0 is the characters it was.
        drawn.handler.moveCursor(toLine: 0, column: 3)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .enter))
        _ = drawn.render()
        #expect(box.value == "one\n\nXtwo\nthree")
        #expect(reads.value == "01211", "the new line 1 alone")
        #expect(drawn.handler.lineStyleCache.count == 4)
        // A text the app replaces is styled afresh.
        box.value = "fresh"
        _ = drawn.render()
        #expect(reads.value == "012110")
        #expect(drawn.handler.lineStyleCache.count == 1)
    }

    @Test("A cache moves the lines after a replacement and drops those it replaced")
    func cacheReplaceLines() {
        var cache = EditorLineStyleCache()
        for line in 0..<5 { _ = cache.runs(ofLine: line) { [EditorStyledRun(columns: 0..<$0 + 1)] } }
        cache.replaceLines(1..<3, withCount: 1)
        #expect(cache.count == 3)
        var read: [Int] = []
        for line in 0..<4 {
            _ = cache.runs(ofLine: line) { line in
                read.append(line)
                return []
            }
        }
        #expect(read == [1])
        // The old line 3 is now line 2, its runs with it.
        #expect(cache.runs(ofLine: 2) { _ in [] } == [EditorStyledRun(columns: 0..<4)])
    }

    @Test("Hidden text is drawn in none of its styles")
    func hiddenTextIsUnstyled() throws {
        let box = Box("abcdefgh")
        let drawn = editor(box, styler: Self.styler)
        drawn.handler.hidingGlyph = "•"
        #expect(drawn.handler.styles(ofLine: 0).isEmpty)
    }
}
