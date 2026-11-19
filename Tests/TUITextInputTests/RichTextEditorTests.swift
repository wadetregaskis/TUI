//  🖥️ TUI — A Terminal UI framework for Swift
//  RichTextEditorTests.swift
//
//  `TextEditor(text:selection:)` over an `AttributedString` (G3 L4): edits made
//  in the value in place, typing attributes (B-ATTRED-16), undo bringing the
//  attributes back, a value the app writes taken whole (B-ATTRED-4), the
//  selection exchanged, and the runs drawn as `Text` draws them.
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

@MainActor
@Suite("Text editor over an attributed string")
struct RichTextEditorTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private typealias Runs = SelectionTestText

    /// An editor over `text`, rendered once: its handler, and a render.
    private func editor(
        _ text: Box<AttributedString>, selection: Box<AttributedTextSelection>? = nil, width: Int = 30,
        modify: (TextEditor) -> some View = { $0 }
    ) -> (handler: TextEditorHandler, render: () -> FrameBuffer) {
        let context = makeRenderContext(width: width, height: 4)
        let view = modify(TextEditor(text: text.binding, selection: selection?.binding)).frame(width: width, height: 4)
        _ = renderToBuffer(view, context: context)
        let handler = context.environment.focusManager!.activeSection!.focusables
            .compactMap { $0 as? TextEditorHandler }.first!
        return (handler, { renderToBuffer(view, context: context) })
    }

    /// The ink of each character of `text`, in order.
    private func inks(_ text: AttributedString) -> [Color?] {
        text.runs.flatMap { run in Array(repeating: run.foregroundColor, count: text[run.range].characters.count) }
    }

    private func type(_ characters: String, into handler: TextEditorHandler) {
        for character in characters { _ = handler.handleKeyEvent(KeyEvent(key: .character(character))) }
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

    @Test("Typing goes into the value in place: the characters around it keep their attributes")
    func typingKeepsNeighbours() {
        let text = Box(Runs.runs([("aaa", Runs.red), ("bbb", Runs.blue)]))
        let drawn = editor(text)
        drawn.handler.moveCursor(toLine: 0, column: 3)
        type("X", into: drawn.handler)
        #expect(String(text.value.characters) == "aaaXbbb")
        // The character before the caret decides (B-ATTRED-16).
        #expect(inks(text.value) == [Runs.red, Runs.red, Runs.red, Runs.red, Runs.blue, Runs.blue, Runs.blue])
    }

    @Test("At a paragraph's start typing takes its first character's attributes, and at the text's start too")
    func paragraphStart() {
        let text = Box(Runs.measured)
        let drawn = editor(text)
        drawn.handler.moveCursor(toLine: 1, column: 0)
        type("Z", into: drawn.handler)
        drawn.handler.moveCursor(toLine: 0, column: 0)
        type("A", into: drawn.handler)
        #expect(String(text.value.characters) == "Aaaabbb\nZccc")
        let ink = inks(text.value)
        #expect(ink[0] == Runs.red)
        #expect(ink[8] == Runs.green, "the paragraph's first character's, not the line break's")
    }

    @Test("Typed over a selection, the text takes the selection's first character's attributes")
    func typingOverSelection() {
        let text = Box(Runs.runs([("aa", Runs.red), ("bb", Runs.blue), ("cc", Runs.green)]))
        let drawn = editor(text)
        drawn.handler.moveCursor(toLine: 0, column: 2)
        drawn.handler.selectionAnchor = drawn.handler.cursor
        drawn.handler.moveCursor(toLine: 0, column: 5)
        type("X", into: drawn.handler)
        #expect(String(text.value.characters) == "aaXc")
        #expect(inks(text.value) == [Runs.red, Runs.red, Runs.blue, Runs.green])
    }

    @Test("Typing attributes the app gives an insertion point are typed, until the caret moves")
    func appTypingAttributes() {
        let text = Box(Runs.runs([("aaa", Runs.red)]))
        var green = AttributeContainer()
        green.foregroundColor = Runs.green
        let selection = Box(AttributedTextSelection(insertionPoint: Runs.index(3, in: text.value), typingAttributes: green))
        let drawn = editor(text, selection: selection)
        _ = drawn.render()
        type("xy", into: drawn.handler)
        #expect(String(text.value.characters) == "aaaxy")
        #expect(inks(text.value) == [Runs.red, Runs.red, Runs.red, Runs.green, Runs.green])
        // The editor wrote its caret back, in the new value, with no typing attributes of its own.
        #expect(selection.value.indices(in: text.value) == .insertionPoint(text.value.endIndex))
        #expect(selection.value.storedTypingAttributes == nil)
    }

    @Test("Undo brings back the characters with their attributes, and redo takes them again")
    func undoRestoresAttributes() {
        let text = Box(Runs.runs([("aa", Runs.red), ("bb", Runs.blue)]))
        let drawn = editor(text)
        drawn.handler.moveCursor(toLine: 0, column: 4)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .backspace))
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .backspace))
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(String(text.value.characters) == "a")
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(String(text.value.characters) == "aabb")
        #expect(inks(text.value) == [Runs.red, Runs.red, Runs.blue, Runs.blue])
        drawn.handler.redo()
        #expect(String(text.value.characters) == "a")
    }

    @Test("Text moved by a drag keeps its own runs where it lands, and undo puts it back with them")
    func dragMoveKeepsAttributes() {
        let text = Box(Runs.runs([("aaa", Runs.red), ("bbb", Runs.blue)]) + AttributedString("ccc"))
        let drawn = editor(text)
        // "ab", a red character and a blue one, carried to the end of the line.
        drawn.handler.moveCursor(toLine: 0, column: 2)
        drawn.handler.selectionAnchor = drawn.handler.cursor
        drawn.handler.moveCursor(toLine: 0, column: 4)
        #expect(drawn.handler.beginTextDrag(at: TextEditorPosition(line: 0, column: 3)))
        drawn.handler.dragText(to: TextEditorPosition(line: 0, column: 9))
        #expect(drawn.handler.endTextDrag(clickedAt: TextEditorPosition(line: 0, column: 3)))
        #expect(String(text.value.characters) == "aabbcccab")
        #expect(inks(text.value) == [Runs.red, Runs.red, Runs.blue, Runs.blue, nil, nil, nil, Runs.red, Runs.blue])
        // Typed next to it, text takes the typing attributes again, the moved
        // text's no longer held.
        drawn.handler.clearSelection()
        drawn.handler.moveCursor(toLine: 0, column: 4)
        type("x", into: drawn.handler)
        #expect(inks(text.value)[4] == Runs.blue, "the character before the caret's")
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(String(text.value.characters) == "aaabbbccc")
        #expect(inks(text.value) == [Runs.red, Runs.red, Runs.red, Runs.blue, Runs.blue, Runs.blue, nil, nil, nil])
    }

    @Test("Ctrl-T swaps two characters with their own attributes")
    func transposeKeepsAttributes() {
        let text = Box(Runs.runs([("a", Runs.red), ("b", Runs.blue)]))
        let drawn = editor(text)
        drawn.handler.moveCursor(toLine: 0, column: 1)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("t"), ctrl: true))
        #expect(String(text.value.characters) == "ba")
        #expect(inks(text.value) == [Runs.blue, Runs.red])
    }

    @Test("The editor's own write is read back as the same value; a value the app writes is taken whole")
    func appValueIsTakenWhole() throws {
        let text = Box(Runs.runs([("aaa", Runs.red), ("\nbbb", Runs.blue)]))
        let drawn = editor(text)
        type("X", into: drawn.handler)
        let source = try #require(drawn.handler.attributedSource)
        #expect(AttributedTextSource.isIdentical(source.value, text.value))
        let layout = drawn.handler.layout()
        _ = drawn.render()
        #expect(drawn.handler.lineStyleCache.count == 2)
        // Recoloured by the app: the characters and the layout stay, the
        // styles are read again, and undo still knows the text.
        var recoloured = text.value
        recoloured.foregroundColor = Runs.green
        text.value = recoloured
        _ = drawn.render()
        #expect(drawn.handler.layout() === layout, "the same characters, the same layout")
        #expect(drawn.handler.styles(ofLine: 1).first?.foreground == Runs.green)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(String(text.value.characters) == "aaa\nbbb", "undo survives a recolour")
        // Characters the app replaced: laid out afresh, and the history forgotten.
        text.value = AttributedString("new")
        _ = drawn.render()
        #expect(drawn.handler.readLines() == [Array("new")])
    }

    @Test("The selection is written as the caret moves and after every edit, and the app's moves the caret")
    func selectionIsExchanged() {
        let text = Box(AttributedString("hello\nworld"))
        let selection = Box(AttributedTextSelection(range: Runs.index(1, in: text.value)..<Runs.index(3, in: text.value)))
        let drawn = editor(text, selection: selection)
        #expect(drawn.handler.selectionRange != nil)
        #expect(drawn.handler.cursor == TextEditorPosition(line: 0, column: 3))
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .right))
        #expect(selection.value.indices(in: text.value) == .insertionPoint(Runs.index(3, in: text.value)))
        // Delete forward leaves the caret's offset where it was; the selection
        // is still written anew, in the new value.
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .delete))
        #expect(String(text.value.characters) == "helo\nworld")
        #expect(selection.value.indices(in: text.value) == .insertionPoint(Runs.index(3, in: text.value)))
        selection.value = AttributedTextSelection(insertionPoint: Runs.index(7, in: text.value))
        _ = drawn.render()
        #expect(drawn.handler.cursor == TextEditorPosition(line: 1, column: 2))
    }

    @Test("Runs draw as Text draws them: colour, bold and faint from a font's weight, italic, a link underlined")
    func runsAreDrawn() throws {
        var text = AttributedString("RBLIU plain")
        let at = { (offset: Int) in Runs.index(offset, in: text) }
        text[at(0)..<at(1)].foregroundColor = Runs.red
        text[at(1)..<at(2)].font = .body.weight(.semibold)
        text[at(2)..<at(3)].font = .body.weight(.light)
        text[at(3)..<at(4)].font = .body.italic()
        text[at(4)..<at(5)].link = URL(string: "https://example.com")
        let drawn = editor(Box(text))
        let row = cells(try #require(drawn.render().lines.first))
        // Cell 0 is the caret's.
        #expect(row[1].state.isBold)
        #expect(row[2].state.isOn(2), "light is faint")
        #expect(row[3].state.isItalic)
        #expect(row[4].state.isOn(4), "a link is underlined")
        #expect(!row[6].state.isBold && !row[6].state.isItalic && !row[6].state.isOn(4))
        #expect(drawn.handler.styles(ofLine: 0).first?.foreground == Runs.red)
    }

    @Test("Plain text draws as a String editor draws it, under .foregroundStyle too")
    func plainValueDrawsAsString() {
        for styled in [false, true] {
            let context = makeRenderContext(width: 20, height: 3)
            func draw(_ editor: TextEditor) -> [String] {
                let view = editor.frame(width: 20, height: 3)
                return styled
                    ? renderToBuffer(view.foregroundStyle(.red), context: context).lines
                    : renderToBuffer(view, context: context).lines
            }
            let attributed = draw(TextEditor(text: .constant(AttributedString("one\ntwo"))))
            let plain = draw(TextEditor(text: .constant("one\ntwo")))
            #expect(attributed == plain)
        }
    }

    @Test(".disabled makes an attributed editor no focus stop, drawn as a disabled String editor")
    func disabled() {
        let context = makeRenderContext(width: 20, height: 3)
        let attributed = renderToBuffer(
            TextEditor(text: .constant(AttributedString("one"))).disabled().frame(width: 20, height: 3), context: context)
        let editors = context.environment.focusManager!.activeSection?.focusables.compactMap { $0 as? TextEditorHandler }
        #expect(editors?.allSatisfy { !$0.canBeFocused } != false, "no focus stop")
        let plain = renderToBuffer(TextEditor(text: .constant("one")).disabled().frame(width: 20, height: 3), context: context)
        #expect(attributed.lines == plain.lines)
        let viaModifier = renderToBuffer(
            TextEditor(text: .constant(AttributedString("one"))).frame(width: 20, height: 3).disabled(true),
            context: makeRenderContext(width: 20, height: 3))
        #expect(viaModifier.lines == plain.lines)
    }

    @Test("An AttributedString is one reference, which the editor's identity test reads")
    func layoutIsOneReference() {
        #expect(MemoryLayout<AttributedString>.size == MemoryLayout<UnsafeRawPointer>.size)
        let text = AttributedString("abc")
        var copy = text
        #expect(AttributedTextSource.isIdentical(text, copy))
        copy.foregroundColor = Runs.red
        #expect(!AttributedTextSource.isIdentical(text, copy))
        #expect(!AttributedTextSource.isIdentical(text, AttributedString("abc")), "equal, but other storage")
    }

    /// Every character of the value carries an ink of its own, and the test
    /// keeps the straightforward model beside the editor: an array of
    /// characters and inks, a typed character taking the ink of the one
    /// before it (B-ATTRED-16; the caret is never put at a paragraph's start,
    /// where another rule picks), a Backspace taking one out. After every key
    /// the value must be the model, character for character and ink for ink,
    /// and the lines drawn from the styles the editor read must be the
    /// model's: what an edit made in the value in place, or a layout spliced
    /// from the one before, gets wrong shows up as a character in the wrong
    /// ink or in the wrong place.
    @Test("Random keys keep every character's own attributes, as a model of the value does")
    func randomKeysKeepAttributes() {
        var random = SplitMix(state: 0xA77E)
        let inkCount = 64
        func ink(_ index: Int) -> Color { .rgb(UInt8(index % 251), UInt8((index / 251) % 251), 7) }
        var lines: [String] = []
        for line in 0..<12 {
            let word = String("abcdefgh".prefix(1 + line % 8))
            lines.append(String(repeating: word, count: 1 + line % 3))
        }
        var model: [(character: Character, ink: Color)] = []
        for (offset, character) in lines.joined(separator: "\n").enumerated() {
            model.append((character, ink(offset % inkCount)))
        }
        var start = AttributedString()
        for part in model {
            var piece = AttributedString(String(part.character))
            piece.foregroundColor = part.ink
            start += piece
        }
        let text = Box(start)
        let drawn = editor(text, width: 40)
        for step in 0..<400 {
            // The caret after a character that is not a line break.
            let places = model.indices.filter { model[$0].character != "\n" }.map { $0 + 1 }
            let offset = places.randomElement(using: &random)!
            let breaks: [Int] = model[..<offset].indices.filter { model[$0].character == "\n" }
            let lead: Int = (breaks.last ?? -1) + 1
            let line: Int = breaks.count
            drawn.handler.moveCursor(toLine: line, column: offset - lead)
            switch Int.random(in: 0..<10, using: &random) {
            case 0..<6:
                let typed: Character = ["x", "y", " ", "é"].randomElement(using: &random)!
                _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character(typed)))
                model.insert((typed, model[offset - 1].ink), at: offset)
            case 6..<9:
                _ = drawn.handler.handleKeyEvent(KeyEvent(key: .backspace))
                model.remove(at: offset - 1)
            default:
                _ = drawn.handler.handleKeyEvent(KeyEvent(key: .enter))
                model.insert(("\n", model[offset - 1].ink), at: offset)
            }
            _ = drawn.render()
            let characters = String(model.map(\.character))
            let modelInks: [Color?] = model.map(\.ink)
            #expect(String(text.value.characters) == characters, "step \(step)")
            #expect(inks(text.value) == modelInks, "step \(step)")
            let layout = drawn.handler.layout()
            #expect(layout.text == characters, "step \(step)")
            // The styles every line is drawn in, as the editor keeps them read:
            // a run's ink in each of its columns, every column covered.
            for index in layout.lines.indices {
                var drawnInks: [Color?] = Array(repeating: nil, count: layout.lines[index].count)
                for run in drawn.handler.styles(ofLine: index) {
                    for column in run.columns where column < drawnInks.count { drawnInks[column] = run.foreground }
                }
                let first: Int = layout.characterStarts[index]
                let expected: [Color?] = Array(modelInks[first..<(first + layout.lines[index].count)])
                #expect(drawnInks == expected, "step \(step) line \(index)")
            }
        }
    }
}
