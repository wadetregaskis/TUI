//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorMarkTests.swift
//
//  Marks (lane H3 of the highlighting design's §8.6, B-ATTRED-13): ranges
//  stated with the text they were computed from, drawn where that text is the
//  editor's, carried through the editor's edits since when it is one a few
//  keys old, and hidden when it is one the editor does not know; drawn over
//  highlighting and under the find bar's tint and the selection (B-ATTRED-8);
//  and the find bar's matches, carried as the app's are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@_spi(TextEditorHighlighting) @testable import TUITextInput

@MainActor
@Suite("Text editor: marks")
struct TextEditorMarkTests {
    typealias Box = TextEditorHighlightLayerTests.Box
    typealias Cells = [(character: Character, state: SGRState)]

    nonisolated static let red = Color.rgb(200, 20, 20)
    nonisolated static let blue = Color.rgb(20, 20, 200)

    /// What the tests' marks are drawn in: a red ink.
    static var redInk: AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = red
        return container
    }

    static func ink(_ color: Color) -> SGRState.Colour? {
        TextEditorHighlightLayerTests.drawn(ink: color).foregroundColour
    }

    /// An editor of a bound text, whose app states `marks` of `stated`, each
    /// frame as they are then; the caret parked on the last line, which the
    /// tests leave empty, so no checked cell is the caret's.
    @MainActor
    final class Rig {
        let text: Box<String>
        /// The marks the app states, as character offsets of `stated`.
        var marks: [Range<Int>] = []
        var stated: String
        var attributes = TextEditorMarkTests.redInk
        let context = makeRenderContext(width: 20, height: 4)

        init(_ text: String) {
            self.text = Box(text)
            stated = text
        }

        var view: some View {
            let stated = stated
            let marks = marks.map { range in
                TextEditorMark(
                    stated.index(stated.startIndex, offsetBy: range.lowerBound)
                        ..< stated.index(stated.startIndex, offsetBy: range.upperBound),
                    attributes: attributes)
            }
            return TextEditor(text: text.binding).textEditorMarks(marks, in: stated).frame(width: 20, height: 4)
        }

        @discardableResult
        func draw() -> [Cells] {
            renderToBuffer(view, context: context).lines.map { TextEditorHighlightLayerTests.cells($0) }
        }

        var handler: TextEditorHandler {
            context.environment.focusManager!.activeSection!.focusables.compactMap { $0 as? TextEditorHandler }.first!
        }

        /// Types `string` at `column` of line 0, or over `selecting` there,
        /// as the editor's own edit, and parks the caret again.
        func type(_ string: String, at column: Int, selecting: Int = 0) {
            handler.moveCursor(toLine: 0, column: column)
            if selecting > 0 {
                handler.selectionAnchor = handler.cursor
                handler.startOrExtendSelection()
                handler.moveCursor(toLine: 0, column: column + selecting)
            }
            // A key replaces the selection; `insert(_:)`, a paste's, does not.
            if string.isEmpty || selecting > 0 {
                _ = handler.handleKeyEvent(KeyEvent(key: string.isEmpty ? .backspace : .character(string.first!)))
                if string.count > 1 { handler.insert(String(string.dropFirst())) }
            } else {
                handler.insert(string)
            }
            handler.moveCursor(toLine: handler.lineCount - 1, column: 0)
        }

        /// The columns of line 0 drawn in the marks' red, as drawn now.
        func marked() -> [Int] {
            let row = draw()[0]
            return row.indices.filter { row[$0].state.foregroundColour == TextEditorMarkTests.ink(TextEditorMarkTests.red) }
        }
    }

    // MARK: - Stated with the editor's text

    @Test("A mark of the editor's own text draws its range, and nothing else")
    func drawnWhereStated() {
        let rig = Rig("abc def ghi\n")
        rig.marks = [4..<7]
        #expect(rig.marked() == [4, 5, 6])
        rig.marks = []
        #expect(rig.marked().isEmpty, "stated again as none")
    }

    // MARK: - Stale

    @Test("Marks of a text one key old are carried through that key")
    func oneKeyStale() {
        let rig = Rig("abc def\n")
        rig.marks = [0..<3]
        rig.draw()
        let parsed = rig.text.value
        rig.type("XY", at: 0)
        // The app's parse of the text before the key arrives after it.
        rig.marks = [4..<7]
        rig.stated = parsed
        #expect(rig.marked() == [6, 7, 8])
    }

    @Test("Marks of a text two keys old are carried through both")
    func twoKeysStale() {
        let rig = Rig("abc def ghi\n")
        rig.marks = [0..<3]
        rig.draw()
        let parsed = rig.text.value
        rig.type("X", at: 0)
        rig.draw()
        rig.type("", at: 6)  // a backspace: "Xabc ef ghi"
        rig.marks = [4..<7, 8..<11]
        rig.stated = parsed
        #expect(rig.marked() == [5, 6, 8, 9, 10], "\"def\" lost its d; \"ghi\" moved by none")
    }

    @Test("Marks a frame keeps stating, unchanged, stay carried through each key")
    func keptMarksAreCarried() {
        let rig = Rig("abc def\n")
        rig.marks = [4..<7]
        #expect(rig.marked() == [4, 5, 6])
        rig.type("X", at: 0)
        #expect(rig.marked() == [5, 6, 7])
        rig.type("Y", at: 0)
        #expect(rig.marked() == [6, 7, 8])
    }

    // MARK: - Unknown

    @Test("Marks of a text the editor does not know are not drawn until stated again")
    func unknownTextHides() {
        let rig = Rig("abc def\n")
        rig.marks = [4..<7]
        rig.stated = "abc dex\n"
        #expect(rig.marked().isEmpty, "a text the editor never had")
        rig.stated = rig.text.value
        #expect(rig.marked() == [4, 5, 6])
        // The app writes a text of its own: the marks stated before are of
        // a text the editor did not edit into this one.
        let before = rig.text.value
        rig.text.value = "zz abc def\n"
        #expect(rig.marked().isEmpty, "the app's own text")
        rig.stated = before
        #expect(rig.marked().isEmpty, "stated again, still of the text before")
    }

    @Test("Marks of a text more keys old than the editor keeps are not drawn")
    func tooOldHides() {
        let rig = Rig("abc def\n")
        rig.marks = [0..<3]
        rig.draw()
        let parsed = rig.text.value
        for _ in 0...EditorMarkStore.carriedEdits { rig.type("X", at: 0) }
        rig.marks = [4..<7]
        rig.stated = parsed
        #expect(rig.marked().isEmpty)
        // As many keys old as it keeps: drawn.
        let recent = Rig("abc def\n")
        recent.marks = [0..<3]
        recent.draw()
        let kept = recent.text.value
        for _ in 0..<EditorMarkStore.carriedEdits { recent.type("X", at: 0) }
        recent.marks = [4..<7]
        recent.stated = kept
        #expect(recent.marked() == Array((4 + EditorMarkStore.carriedEdits)..<(7 + EditorMarkStore.carriedEdits)))
    }

    // MARK: - Through an edit

    @Test("An edit after a mark leaves it; before it, moves it; inside it, grows it")
    func editsAroundAMark() {
        let rig = Rig("abc def ghi\n")
        rig.marks = [4..<7]
        rig.draw()
        rig.type("XX", at: 9)
        #expect(rig.marked() == [4, 5, 6], "after: left as it was")
        rig.type("Y", at: 1)
        #expect(rig.marked() == [5, 6, 7], "before: moved")
        rig.type("ZZ", at: 6)
        #expect(rig.marked() == [5, 6, 7, 8, 9], "inside: grown")
        rig.type("", at: 7)
        #expect(rig.marked() == [5, 6, 7, 8], "a character inside deleted: shrunk")
    }

    @Test("Text typed at a mark's ends goes outside it")
    func typedAtTheEnds() {
        let rig = Rig("abc def\n")
        rig.marks = [4..<7]
        rig.draw()
        rig.type("X", at: 4)
        #expect(rig.marked() == [5, 6, 7], "at its start: before it")
        rig.type("Y", at: 8)
        #expect(rig.marked() == [5, 6, 7], "at its end: after it")
    }

    @Test("A mark an edit replaces whole is gone; one it replaces in part keeps the rest")
    func replacedMarks() {
        let rig = Rig("abc def ghi\n")
        rig.marks = [4..<7, 8..<11]
        rig.draw()
        // "c def g" gives way to "Q": the first mark whole, the second's g.
        rig.type("Q", at: 2, selecting: 7)
        #expect(rig.text.value == "abQhi\n")
        #expect(rig.marked() == [3, 4])
        // And stated again, unchanged, it stays as carried.
        #expect(rig.marked() == [3, 4])
    }

    // MARK: - Composition (B-ATTRED-8)

    @Test("A mark is drawn over highlighting: what it sets wins, what it leaves is the highlight's")
    func overHighlighting() {
        let rig = Rig("abcdef\n")
        rig.draw()
        rig.handler.replaceHighlightLayer(TextEditorHighlightLayerTests.layer([0: [(0, .key), (3, .bold)]]))
        let highlighted = rig.draw()[0]
        rig.marks = [2..<5]
        let row = rig.draw()[0]
        #expect(row[1].state == highlighted[1].state, "the highlight's alone")
        #expect(row[2].state.foregroundColour == Self.ink(Self.red), "the mark's ink over the highlight's")
        for column in 3..<5 {
            #expect(row[column].state.foregroundColour == Self.ink(Self.red), "\(column)")
            #expect(row[column].state.isBold, "the highlight's bold stays: \(column)")
        }
        #expect(row[5].state == highlighted[5].state, "past the mark")
    }

    @Test("The selection is drawn over a mark, and the find bar's tint over its field")
    func underSelectionAndFind() {
        withColorDepth(.truecolor) {
            let rig = Rig("one two one\n")
            rig.draw()
            var plate = AttributeContainer()
            plate.backgroundColor = Self.blue
            plate.foregroundColor = Self.red
            let text = rig.text.value
            // The whole line marked red on blue, and "one" found, twice.
            rig.handler.noteMarks(
                app: EditorMarkStatement(
                    text: text, ranges: [text.startIndex..<text.index(text.startIndex, offsetBy: 11)],
                    attributes: [plate]),
                find: EditorMarkStatement(text: text, ranges: FindMatches.matches(of: "one", in: text), attributes: nil),
                environment: rig.context.environment)
            let core = _TextEditorCore(
                text: rig.text.binding, focusID: nil, isDisabled: false, menuTarget: TextEditingMenuTarget())
            let styling = _TextEditorCore.RowStyling(
                palette: rig.context.environment.palette, isDisabled: false, background: nil)
            let row = TextEditorHighlightLayerTests.cells(
                core.styledRow(
                    Array("one two one"), tabWidth: rig.context.environment.tabWidth, scrollColumn: 0, width: 20,
                    caret: nil, selection: 4..<7, matches: rig.handler.findColumns(ofLine: 0),
                    styles: rig.handler.styles(ofLine: 0), styling: styling
                ).line)
            #expect(row[3].state == TextEditorHighlightLayerTests.drawn(ink: Self.red, field: Self.blue), "the mark alone")
            #expect(row[0].state.foregroundColour == Self.ink(Self.red), "a match keeps the mark's ink")
            let drawn = TextEditorHighlightLayerTests.drawn
            #expect(row[0].state.backgroundColour == drawn(nil, styling.match, false).backgroundColour, "the find bar's tint")
            #expect(row[4].state.foregroundColour == drawn(styling.selection.foreground, nil, false).foregroundColour, "selected ink")
            #expect(row[4].state.backgroundColour == drawn(nil, styling.selection.background, false).backgroundColour, "selected field")
        }
    }

    @Test("Where two marks overlap, the later is drawn over the earlier")
    func laterOverEarlier() {
        let rig = Rig("abcdef\n")
        var blueInk = AttributeContainer()
        blueInk.foregroundColor = Self.blue
        let text = rig.text.value
        func range(_ offsets: Range<Int>) -> Range<String.Index> {
            text.index(text.startIndex, offsetBy: offsets.lowerBound)..<text.index(text.startIndex, offsetBy: offsets.upperBound)
        }
        let view = TextEditor(text: rig.text.binding)
            .textEditorMarks(
                [TextEditorMark(range(0..<4), attributes: Self.redInk), TextEditorMark(range(2..<6), attributes: blueInk)],
                in: text
            ).frame(width: 20, height: 4)
        let row = TextEditorHighlightLayerTests.cells(renderToBuffer(view, context: rig.context).lines[0])
        #expect(row[1].state.foregroundColour == Self.ink(Self.red))
        #expect(row[2].state.foregroundColour == Self.ink(Self.blue))
        #expect(row[5].state.foregroundColour == Self.ink(Self.blue))
    }

    @Test("A mark across a line break, and one inside a wide character, draw whole characters")
    func linesAndCharacters() {
        let rig = Rig("ab👍cd\nefgh\n")
        // From inside the thumb to the second line's "f".
        let text = rig.text.value
        let utf8 = text.utf8
        let inside = utf8.index(utf8.startIndex, offsetBy: 3)
        let view = TextEditor(text: rig.text.binding)
            .textEditorMarks(
                [TextEditorMark(inside..<text.index(text.startIndex, offsetBy: 8), attributes: Self.redInk)], in: text
            ).frame(width: 20, height: 4)
        let rows = renderToBuffer(view, context: rig.context).lines.map { TextEditorHighlightLayerTests.cells($0) }
        let red = Self.ink(Self.red)
        #expect(rows[0].indices.filter { rows[0][$0].state.foregroundColour == red } == [2, 3, 4], "the thumb (one character of two cells), c, d")
        #expect(rows[1].indices.filter { rows[1][$0].state.foregroundColour == red } == [0, 1], "e, f")
    }

    // MARK: - The find bar's matches

    @Test("The find bar's matches are carried through an edit made before they are found again")
    func findMatchesCarried() {
        let rig = Rig("one two one\n")
        rig.draw()
        let text = rig.text.value
        rig.handler.noteMarks(
            app: nil,
            find: EditorMarkStatement(text: text, ranges: FindMatches.matches(of: "one", in: text), attributes: nil),
            environment: rig.context.environment)
        #expect(rig.handler.findColumns(ofLine: 0) == [0..<3, 8..<11])
        rig.type("X", at: 4)
        #expect(rig.handler.findColumns(ofLine: 0) == [0..<3, 9..<12])
        // Found again by the next frame: none, since the bar is down.
        rig.draw()
        #expect(rig.handler.findColumns(ofLine: 0).isEmpty)
    }

    @Test("Edits, as marks are carried through them, are found to the byte")
    func editSpans() {
        let before = EditorLayout(text: "abc\ndef\nghi")
        func edit(_ line: Int, to new: String) -> EditorMarkEdit? {
            var lines = EditedLines(before.lines)
            lines.apply(TextEditorReplacement(line: line, columns: 0..<before.lines[line].count, with: Array(new)))
            return before.replacing(lines).map { EditorMarkEdit($0, from: before) }
        }
        #expect(edit(1, to: "dXef") == EditorMarkEdit(start: 5, oldEnd: 5, newEnd: 6))
        #expect(edit(2, to: "") == EditorMarkEdit(start: 8, oldEnd: 11, newEnd: 8))
        #expect(edit(0, to: "ab") == EditorMarkEdit(start: 2, oldEnd: 3, newEnd: 2))
    }
}
