//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorUndoLayoutTests.swift
//
//  An undo and a redo spliced into the layout as a key's edit is, not the
//  text written whole and laid out again (H-87, TEXTIN-8); and a hidden
//  editor's drawn layout made from the one before, not afresh per key
//  (TEXTIN-18).
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Editor layout: an undo and a redo spliced in as an edit")
struct EditorUndoLayoutTests {
    typealias Frames = EditorLayoutTests.Frames
    typealias Box = EditorLayoutTests.Box

    static let undoKey = KeyEvent(key: .character("z"), ctrl: true)
    static let redoKey = KeyEvent(key: .character("Z"), ctrl: true, shift: true)

    /// Ten thousand lines, each wrapping at the editor's width.
    static let tenThousandLines = (0..<10_000).map { "line \($0) of a document long enough to wrap" }
        .joined(separator: "\n")

    /// How many texts `body` splits into lines whole.
    func layouts(_ body: () -> Void) -> Int {
        let count = Mutex(0)
        EditorLayout.$buildReporter.withValue(TaskLocalReporter { count.withLock { $0 += 1 } }, operation: body)
        return count.withLock { $0 }
    }

    /// Typing, two undos and two redos in a large text, a frame after each
    /// key, laying nothing out whole: before H-87 an undo or a redo wrote the
    /// text whole, and the next frame split all ten thousand lines again and
    /// wrapped every one.
    @Test("Typing, undo and redo in ten thousand lines lay nothing out whole", arguments: [false, true])
    func typeUndoRedoLayNothingOut(hidden: Bool) throws {
        let frames = Frames(width: 30, height: 8)
        let box = Box(Self.tenThousandLines)
        let original = box.value
        let page = EditorLayoutTests.Beside(text: box).redacted(reason: hidden ? .placeholder : [])
        for _ in 0..<2 { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        let handler = try #require(frames.handler)
        handler.moveCursor(toLine: 5_000, column: 4)
        func play(_ keys: [KeyEvent]) {
            for key in keys {
                _ = handler.handleKeyEvent(key)
                _ = frames.pass { renderToBuffer(page, context: frames.context) }
            }
        }
        let built = layouts {
            play("abc".map { KeyEvent(character: $0) })
            play([KeyEvent(key: .left)])
            play("de".map { KeyEvent(character: $0) })
            let typed = box.value
            play([Self.undoKey, Self.undoKey])
            #expect(box.value == original)
            play([Self.redoKey, Self.redoKey])
            #expect(box.value == typed)
            play([Self.undoKey])
        }
        #expect(built == 0, "the document was laid out whole again")
        let layout = handler.layout()
        #expect(layout.text == box.value)
        #expect(layout.wrapsMade == 0, "the undo's layout kept the rows of every line it did not change")
        if hidden {
            #expect(handler.displayLayout().wrapsMade == 0, "the hidden layout kept its rows")
        }
    }

    /// The texts the random runs start from: each kind of line break, empty
    /// lines, characters of more than one byte, a combining mark at a line's
    /// start, a flag; and one that mixes breaks, which is written whole.
    nonisolated static let startingTexts = [
        "one two\n\nthree é\n🇦🇺 four\n\u{301}five", "a\r\nbé\r\n\r\nc 語 d\r\ne", "x\ry z\r\rw",
        "", "mixed\nbreaks\r\nhere\rend",
    ]

    /// A random key: typing (a combining mark and half a flag on their own
    /// among them), line breaks, deletions, pastes, kills, moves and
    /// selections, and undo and redo most of all.
    private static func key(_ random: inout SplitMix) -> KeyEvent {
        let pieces: [Character] = ["a", "b", " ", "é", "\u{301}", "🇦", "🇺", "語"]
        let pastes = ["p", "two\nlines", "\n", "q\r\nr", "\r", "é\u{301}"]
        switch Int.random(in: 0..<20, using: &random) {
        case 0..<5: return KeyEvent(character: pieces.randomElement(using: &random)!)
        case 5: return KeyEvent(key: .enter)
        case 6: return KeyEvent(key: .backspace)
        case 7: return KeyEvent(key: .delete)
        case 8: return KeyEvent(key: .paste(pastes.randomElement(using: &random)!))
        case 9: return KeyEvent(key: .character("k"), ctrl: true)
        case 10:
            let keys: [Key] = [.left, .right, .up, .down, .home, .end]
            return KeyEvent(key: keys.randomElement(using: &random)!, shift: Bool.random(using: &random))
        case 11..<16: return undoKey
        default: return redoKey
        }
    }

    /// Two editors played the same random keys, one writing each undo and
    /// redo whole, as before H-87 — its kept layout dropped before each, so
    /// the step finds none to splice into — and the other splicing them. At
    /// every key their texts, byte for byte, carets and selections are the
    /// same, and the splicing editor's layout is the text's made afresh: its
    /// lines, their starts in bytes and in characters, and its rows at two
    /// widths, kept through the edits. Hidden, so is the layout it draws: the
    /// reference's made afresh at every key, as before TEXTIN-18, and the
    /// other's carried through each edit.
    @Test(
        "Undo and redo spliced in leave what writing them whole did",
        arguments: startingTexts.indices, [false, true])
    func splicedStepsMatchWholeWrites(textIndex: Int, hidden: Bool) {
        let start = Self.startingTexts[textIndex]
        var random = SplitMix(state: 0x4887 &+ UInt64(textIndex))
        let (spliced, whole) = (Box(start), Box(start))
        let editor = TextEditorHandler(focusID: "s", text: Binding(get: { spliced.value }, set: { spliced.value = $0 }))
        let reference = TextEditorHandler(focusID: "w", text: Binding(get: { whole.value }, set: { whole.value = $0 }))
        let glyph: Character? = hidden ? "•" : nil
        (editor.hidingGlyph, reference.hidingGlyph) = (glyph, glyph)
        let widths = [7, 3]
        var (built, wholeSteps) = (0, 0)
        for step in 0..<600 {
            let key = Self.key(&random)
            for width in widths {
                _ = editor.layout().wrapped(width: width, tabWidth: .periodic(4))
                _ = editor.displayLayout().wrapped(width: width, tabWidth: .periodic(4))
            }
            let isStep = key == Self.undoKey || key == Self.redoKey
            if isStep { reference.cachedLayout = nil }
            reference.cachedDisplayLayout = nil
            let ending = editor.layout().lineEnding
            built += layouts {
                _ = editor.handleKeyEvent(key)
                _ = (editor.layout(), editor.displayLayout())
            }
            _ = reference.handleKeyEvent(key)
            // A step that leaves one line of a CRLF or CR text is written
            // whole, as a layout made afresh gives it an LF.
            if isStep, ending != "\n", EditorLayout(text: spliced.value).lines.count == 1 { wholeSteps += 1 }
            let comment: Comment = "text \(textIndex) hidden \(hidden) step \(step): \(key)"
            #expect(Array(spliced.value.utf8) == Array(whole.value.utf8), comment)
            #expect(editor.cursor == reference.cursor, comment)
            #expect(editor.selectionAnchor == reference.selectionAnchor, comment)
            Self.expectFresh(editor.layout(), of: spliced.value, widths: widths, comment)
            Self.expectFresh(editor.displayLayout(), of: reference.displayLayout().text, widths: widths, comment)
        }
        // A text of one kind of line break laid out whole only by those: every
        // other undo and redo spliced in, and the hidden layout carried
        // through them. (A hidden layout is laid out afresh once after each.)
        if EditorLayout(text: start).hasOneLineEnding { #expect(built <= wholeSteps * (hidden ? 2 : 1)) }
    }

    /// `layout` is the layout of `text` made afresh: its text byte for byte,
    /// its lines, their starts in bytes and in characters, and its rows at
    /// `widths`.
    private static func expectFresh(_ layout: EditorLayout, of text: String, widths: [Int], _ comment: Comment) {
        let fresh = EditorLayout(text: text)
        #expect(Array(layout.text.utf8) == Array(fresh.text.utf8), comment)
        #expect(layout.lines.map(\.string) == fresh.lines.map(\.string), comment)
        #expect(layout.lines == fresh.lines, comment)
        #expect(layout.lineStarts == fresh.lineStarts, comment)
        #expect(layout.characterStarts == fresh.characterStarts, comment)
        for width in widths {
            let kept = layout.wrapped(width: width, tabWidth: .periodic(4))
            let anew = fresh.wrapped(width: width, tabWidth: .periodic(4))
            #expect(kept.lines == anew.lines, "\(comment) at \(width)")
            #expect(kept.rowStarts == anew.rowStarts, "\(comment) at \(width)")
        }
    }
}
