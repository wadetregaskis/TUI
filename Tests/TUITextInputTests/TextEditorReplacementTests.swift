//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorReplacementTests.swift
//
//  Every edit the editor makes is a range of its text replaced (G3,
//  B-ATTRED-1): the replacement made on the lines, and the edits that are
//  made of one, each checked against the text they leave.
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
@Suite("Text editor: every edit a range replaced")
struct TextEditorReplacementTests {
    private static func position(_ line: Int, _ column: Int) -> TextEditorPosition {
        TextEditorPosition(line: line, column: column)
    }

    private static func applied(_ replacement: TextEditorReplacement, to text: String) -> String {
        var lines = EditorLayout(text: text).lines
        replacement.apply(to: &lines)
        return lines.map { String($0) }.joined(separator: "\n")
    }

    @Test("An insertion, a deletion within a line and one across lines")
    func replacementsOnLines() {
        let text = "one\ntwo\nthree"
        #expect(Self.applied(.init(from: Self.position(1, 1), to: Self.position(1, 1), with: [["X"]]), to: text)
            == "one\ntXwo\nthree")
        #expect(Self.applied(.init(from: Self.position(0, 3), to: Self.position(0, 3), with: [[], []]), to: text)
            == "one\n\ntwo\nthree")
        #expect(Self.applied(.init(line: 2, columns: 1..<4), to: text) == "one\ntwo\nte")
        #expect(Self.applied(.init(from: Self.position(0, 2), to: Self.position(2, 1)), to: text) == "onhree")
        #expect(Self.applied(.init(from: Self.position(0, 1), to: Self.position(1, 2), with: [["A"], ["B", "C"]]), to: text)
            == "oA\nBCo\nthree")
        // A replacement given no lines replaces with nothing.
        #expect(Self.applied(.init(from: Self.position(0, 0), to: Self.position(0, 1), with: []), to: text)
            == "ne\ntwo\nthree")
    }

    @Test("The lines a replacement does not reach keep their storage")
    func untouchedLinesShareStorage() {
        // Past 15 bytes, so each line's string has storage of its own.
        let before = EditorLayout(text: "alpha alpha alpha alpha\nbeta\ngamma gamma gamma gamma").lines
        var after = before
        TextEditorReplacement(line: 1, columns: 0..<1).apply(to: &after)
        for index in [0, 2] {
            let shared = before[index].string.utf8.withContiguousStorageIfAvailable { old in
                after[index].string.utf8.withContiguousStorageIfAvailable { new in unsafe old.baseAddress == new.baseAddress }
            }
            #expect(shared == true, "line \(index)")
        }
    }

    /// Runs `keys` in an editor over `text`, the caret first put at `caret`,
    /// and answers the text the binding holds.
    private static func edited(_ text: String, caret: TextEditorPosition, _ keys: [KeyEvent]) -> String {
        let box = Box(text)
        let handler = TextEditorHandler(focusID: "editor", text: box.binding)
        handler.cursor = caret
        for key in keys { _ = handler.handleKeyEvent(key) }
        return box.value
    }

    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    @Test("Each edit key leaves the text its range replaced does")
    func editKeys() {
        let text = "ab cd\nef\tgh\nij"
        let caret = Self.position(1, 2)
        let cases: [(String, [KeyEvent], String)] = [
            ("typing", [KeyEvent(key: .character("Z"))], "ab cd\nefZ\tgh\nij"),
            ("a paste of lines", [KeyEvent(key: .paste("1\n2\n3"))], "ab cd\nef1\n2\n3\tgh\nij"),
            ("Enter", [KeyEvent(key: .enter)], "ab cd\nef\n\tgh\nij"),
            ("Backspace", [KeyEvent(key: .backspace)], "ab cd\ne\tgh\nij"),
            ("Delete", [KeyEvent(key: .delete)], "ab cd\nefgh\nij"),
            ("Ctrl-K", [KeyEvent(key: .character("k"), ctrl: true)], "ab cd\nef\nij"),
            ("Ctrl-K twice", [KeyEvent(key: .character("k"), ctrl: true), KeyEvent(key: .character("k"), ctrl: true)],
                "ab cd\nefij"),
            ("Ctrl-T", [KeyEvent(key: .character("t"), ctrl: true)], "ab cd\ne\tfgh\nij"),
            ("Ctrl-O", [KeyEvent(key: .character("o"), ctrl: true)], "ab cd\nef\n\tgh\nij"),
            ("Ctrl-U", [KeyEvent(key: .character("u"), ctrl: true)], "ab cd\n\tgh\nij"),
            ("Ctrl-W", [KeyEvent(key: .character("w"), ctrl: true)], "ab cd\n\tgh\nij"),
            ("Option-Backspace", [KeyEvent(key: .backspace, alt: true)], "ab cd\n\tgh\nij"),
            ("Option-Delete", [KeyEvent(key: .delete, alt: true)], "ab cd\nef\nij"),
        ]
        for (name, keys, expected) in cases {
            #expect(Self.edited(text, caret: caret, keys) == expected, "\(name)")
        }
        // At a line's edges a deletion joins lines.
        #expect(Self.edited(text, caret: Self.position(1, 0), [KeyEvent(key: .backspace)]) == "ab cdef\tgh\nij")
        #expect(Self.edited(text, caret: Self.position(0, 5), [KeyEvent(key: .delete)]) == "ab cdef\tgh\nij")
    }

    @Test("A selection typed over, and a block deleted, are their ranges replaced")
    func selectionAndBlock() {
        let box = Box("one\ntwo\nthree")
        let handler = TextEditorHandler(focusID: "editor", text: box.binding)
        handler.cursor = Self.position(2, 2)
        handler.selectionAnchor = Self.position(0, 1)
        _ = handler.handleKeyEvent(KeyEvent(key: .character("X")))
        #expect(box.value == "oXree")
        #expect(handler.cursor == Self.position(0, 2))

        let blockBox = Box("abcd\nefgh\nijkl")
        let blocked = TextEditorHandler(focusID: "block", text: blockBox.binding)
        blocked.block = TextEditorBlock(anchor: CellPoint(x: 1, y: 0), head: CellPoint(x: 3, y: 2))
        _ = blocked.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(blockBox.value == "ad\neh\nil")
        #expect(blocked.cursor == Self.position(0, 1))
    }
}
