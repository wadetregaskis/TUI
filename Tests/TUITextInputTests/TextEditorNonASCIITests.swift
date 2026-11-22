//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorNonASCIITests.swift
//
//  A TextEditor's keys over characters of more than one byte: emoji ZWJ
//  sequences, flags, combining marks, CJK, CRLF line breaks, tabs and
//  right-to-left text. Each moves, deletes, selects, wraps and finds a whole
//  character, as the editor did while its lines were arrays of `Character`s:
//  the guards for their storage as UTF-8 (EDMEM-1), written to pass before it
//  and after.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("TextEditor keys over characters of more than one byte")
struct TextEditorNonASCIITests {
    final class Sink {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// A family (ZWJ), a flag, an e with a combining acute, a CJK character
    /// and Hebrew after an "a": six characters, 35 bytes.
    static let mixed = "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F1EF}\u{1F1F5}e\u{301}\u{4E2D}\u{05E9}"

    private func editor(_ text: String) -> (Sink, TextEditorHandler) {
        let sink = Sink(text)
        return (sink, TextEditorHandler(focusID: "editor", text: sink.binding))
    }

    private func press(_ handler: TextEditorHandler, _ key: Key, times: Int = 1, alt: Bool = false, shift: Bool = false) {
        for _ in 0..<times { _ = handler.handleKeyEvent(KeyEvent(key: key, alt: alt, shift: shift)) }
    }

    @Test("Right steps a whole character at a time, to the line's end in as many steps as it has characters")
    func rightByCharacter() {
        let (sink, handler) = editor(Self.mixed)
        press(handler, .right, times: 3)
        #expect(handler.cursorColumn == 3)
        press(handler, .right, times: 10)
        #expect(handler.cursorColumn == 6)
        press(handler, .left, times: 2)
        #expect(handler.cursorColumn == 4)
        #expect(sink.value == Self.mixed)
    }

    @Test("Backspace and Delete take out a whole character: a family, a flag, an accented letter")
    func deletionByCharacter() {
        let (sink, handler) = editor(Self.mixed)
        press(handler, .right)
        press(handler, .delete)
        #expect(sink.value == "a\u{1F1EF}\u{1F1F5}e\u{301}\u{4E2D}\u{05E9}")
        press(handler, .right, times: 2)
        press(handler, .backspace)
        #expect(sink.value == "a\u{1F1EF}\u{1F1F5}\u{4E2D}\u{05E9}")
        press(handler, .backspace)
        #expect(sink.value == "a\u{4E2D}\u{05E9}")
        #expect(handler.cursorColumn == 1)
    }

    @Test("A selection over wide and joined characters is their text; typing replaces it whole")
    func selection() {
        let (sink, handler) = editor(Self.mixed)
        press(handler, .right)
        press(handler, .right, times: 3, shift: true)
        let span = (TextEditorPosition(line: 0, column: 1), TextEditorPosition(line: 0, column: 4))
        #expect(handler.selectedText(span) == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F1EF}\u{1F1F5}e\u{301}")
        _ = handler.handleKeyEvent(KeyEvent(character: "Z"))
        #expect(sink.value == "aZ\u{4E2D}\u{05E9}")
        #expect(handler.cursorColumn == 2)
    }

    @Test("A combining mark typed after a letter joins it: the caret stays one past the letter")
    func combiningMarkJoins() {
        let (sink, handler) = editor("xe\ny")
        press(handler, .right, times: 2)
        handler.insert("\u{301}")
        #expect(sink.value == "xe\u{301}\ny")
        #expect(handler.cursorColumn == 2)
        handler.insert("!")
        #expect(sink.value == "xe\u{301}!\ny")
    }

    @Test("Word motion over right-to-left and CJK text stops where the words do")
    func wordMotion() {
        let (_, handler) = editor("\u{05E9}\u{05DC}\u{05D5}\u{05DD} \u{05E2}\u{05D5}\u{05DC}\u{05DD} \u{4E2D}\u{6587}")
        press(handler, .right, alt: true)
        #expect(handler.cursorColumn == 4)
        press(handler, .right, alt: true)
        #expect(handler.cursorColumn == 9)
        press(handler, .left, alt: true)
        #expect(handler.cursorColumn == 5)
    }

    @Test("A CRLF document keeps its line breaks through an edit, a line a CRLF")
    func crlfDocument() {
        let (sink, handler) = editor("ab\r\n\u{4E2D}\u{6587}\r\nc")
        #expect(handler.lineCount == 3)
        press(handler, .down)
        press(handler, .right, times: 2)
        #expect(handler.cursorColumn == 2)
        handler.insert("X")
        #expect(sink.value == "ab\r\n\u{4E2D}\u{6587}X\r\nc")
        press(handler, .delete)
        #expect(sink.value == "ab\r\n\u{4E2D}\u{6587}Xc")
    }

    @Test("Up and Down keep the visual column past tabs, emoji and CJK")
    func verticalColumns() {
        let (_, handler) = editor("\tx\n\u{1F1EF}\u{1F1F5}\u{4E2D}ab\nabcdefgh")
        press(handler, .right)
        // The tab ends at cell 4: on the line below, after the flag and the
        // CJK character (two cells each), and on the next, after "abcd".
        press(handler, .down)
        #expect(handler.cursorColumn == 2)
        press(handler, .down)
        #expect(handler.cursorColumn == 4)
    }

    @Test("Replace All finds and replaces emoji, CJK and accented matches by their bytes")
    func replaceAll() {
        let text = "\u{4E2D}\u{1F1EF}\u{1F1F5}e\u{301}\n\u{1F1EF}\u{1F1F5}\u{05E9}"
        let (sink, handler) = editor(text)
        let flag = Array("\u{1F1EF}\u{1F1F5}".utf8)
        let bytes = Array(text.utf8)
        let matches = bytes.indices.filter { Array(bytes[$0...].prefix(flag.count)) == flag }.map { $0..<($0 + flag.count) }
        #expect(matches.count == 2)
        handler.replace(matches, with: "\u{65E5}")
        #expect(sink.value == "\u{4E2D}\u{65E5}e\u{301}\n\u{65E5}\u{05E9}")
    }

    @Test("A wrapping editor breaks CJK and emoji at their cells, never inside a character")
    func wrapping() {
        let app = TestApp(width: 9, height: 4) {
            TextEditor(text: .constant("\u{4E2D}\u{6587}\u{4E2D}\u{6587}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}x"))
        }
        let rows = app.screen.lines.prefix(3).map { String($0.filter { $0 != " " }) }
        #expect(rows.first == "\u{4E2D}\u{6587}\u{4E2D}\u{6587}")
        #expect(rows.joined() == "\u{4E2D}\u{6587}\u{4E2D}\u{6587}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}x")
    }
}
