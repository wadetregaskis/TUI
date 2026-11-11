//  🖥️ TUI — A Terminal UI framework for Swift
//  RedactedTextEditorTests.swift
//
//  A TextEditor under `.redacted(reason:)` drew its text as it was and let it
//  out every other way: copy and cut, the kill ring, word motions and
//  double-clicks that show where its words break, rows wrapped at its word
//  breaks, and a find bar whose matches light up where a word is. The owner's
//  ruling (2026-11-10): hidden text "should not reveal its contents in any
//  way". A redacted editor now behaves as a SecureField does, as a redacted
//  TextField does (`RedactedTextFieldTests`), with its line breaks kept.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUITextInput

/// The string an editor is bound to, read back after the keys.
@MainActor
private final class Bound {
    var value: String
    init(_ value: String) { self.value = value }
}

private struct EditorPage: View {
    let hiding: FieldHiding
    let width: Int
    let text: Bound
    let board: FakeClipboard

    var body: some View {
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        let editor = TextEditor(text: binding).frame(width: width, height: 3)
        Group {
            switch hiding {
            case .placeholder: editor.redacted(reason: .placeholder)
            case .privacy: editor.privacySensitive().redacted(reason: .privacy)
            case .privacyUnmarked: editor.redacted(reason: .privacy)
            case .unredacted: editor.unredacted().redacted(reason: .placeholder)
            case .none: editor
            }
        }
        .environment(\.clipboardAccess, board.access)
    }
}

/// One editor on an otherwise empty page, so it takes the focus on the first
/// frame and every key goes to it. Its caret starts at the beginning.
@MainActor
private func editorApp(
    _ hiding: FieldHiding, _ initial: String, width: Int = 20
) -> (TestApp, Bound, FakeClipboard) {
    let text = Bound(initial)
    let board = FakeClipboard()
    let app = TestApp(width: 30, height: 8) {
        EditorPage(hiding: hiding, width: width, text: text, board: board)
    }
    return (app, text, board)
}

@MainActor
@Suite("A redacted TextEditor hides its text as a SecureField does")
struct RedactedTextEditorTests {
    @Test("Its text is drawn a glyph a character, its line breaks kept", arguments: FieldHiding.allCases)
    func drawsNoText(hiding: FieldHiding) {
        let (app, _, _) = editorApp(hiding, "hi 世界\nok")
        let screen = app.screen.text
        if hiding.hides {
            #expect(!screen.contains("hi") && !screen.contains("世") && !screen.contains("ok"), "\(screen)")
            // Five characters, five cells, then the line break; the screen's
            // text drops a row's trailing blanks.
            let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.first == String(repeating: hiding.glyph, count: 5), "\(screen)")
            #expect(lines.dropFirst().first == String(repeating: hiding.glyph, count: 2), "\(screen)")
        } else {
            #expect(screen.contains("hi 世界") && screen.contains("ok"), "\(screen)")
        }
    }

    @Test("Its rows wrap where the mask does, not at a hidden word's end", arguments: FieldHiding.allCases)
    func wrapsByCharacter(hiding: FieldHiding) {
        // Six cells wide: "ab cdefgh" wraps after "ab " where it is read, and
        // where it is not, after as many glyphs as the row holds.
        let (app, _, _) = editorApp(hiding, "ab cdefgh", width: 6)
        let first = app.screen.text.split(separator: "\n").first.map(String.init) ?? ""
        if hiding.hides {
            #expect(first.count >= 5 && first.allSatisfy { $0 == hiding.glyph }, "\(app.screen.text)")
        } else {
            // The row ends at the space, which the screen's text drops.
            #expect(first.hasPrefix("ab") && !first.contains("c"), "\(app.screen.text)")
        }
    }

    @Test("Copy and cut put nothing on the clipboard and take nothing away", arguments: FieldHiding.allCases)
    func noCopyOrCut(hiding: FieldHiding) {
        let (app, text, board) = editorApp(hiding, "hunter2")
        app.press(.end, modifiers: .shift)
        app.press(.character("c"), modifiers: .control)
        app.press(.character("x"), modifiers: .control)
        if hiding.hides {
            #expect(board.writes.isEmpty, "\(board.writes)")
            #expect(text.value == "hunter2")
        } else {
            #expect(board.writes == ["hunter2", "hunter2"])
            #expect(text.value.isEmpty)
        }
    }

    @Test("Ctrl-K, Ctrl-U and Ctrl-W keep no kill for Ctrl-Y", arguments: FieldHiding.allCases)
    func noKill(hiding: FieldHiding) {
        let (app, text, _) = editorApp(hiding, "hunter2")
        app.press(.right, times: 4)
        app.press(.character("k"), modifiers: .control)
        app.press(.home)
        app.press(.character("y"), modifiers: .control)
        #expect(text.value == (hiding.hides ? "hunt" : "er2hunt"))

        let (other, otherText, _) = editorApp(hiding, "ab cd")
        other.press(.end)
        other.press(.character("w"), modifiers: .control)
        other.press(.home)
        other.press(.character("y"), modifiers: .control)
        // Ctrl-W takes one character where the text is hidden.
        #expect(otherText.value == (hiding.hides ? "ab c" : "cdab "))
    }

    @Test("A word motion and a word deletion go one character", arguments: FieldHiding.allCases)
    func wordMotionByCharacter(hiding: FieldHiding) {
        let (app, text, _) = editorApp(hiding, "hunter2 abc")
        app.press(.end)
        app.press(.left, modifiers: .option)
        app.type("X")
        #expect(text.value == (hiding.hides ? "hunter2 abXc" : "hunter2 Xabc"))

        let (deleting, deleted, _) = editorApp(hiding, "hunter2 abc")
        deleting.press(.end)
        deleting.press(.backspace, modifiers: .option)
        #expect(deleted.value == (hiding.hides ? "hunter2 ab" : "hunter2 "))
    }

    @Test("A double-click selects the line, not the word under it", arguments: FieldHiding.allCases)
    func doubleClickSelectsLine(hiding: FieldHiding) throws {
        let (app, text, _) = editorApp(hiding, "hunter2 abc\nnext")
        let first = try #require(app.screen.location(of: hiding.hides ? String(hiding.glyph) : "h"))
        app.click(at: first)
        app.click(at: first)
        app.type("X")
        #expect(text.value == (hiding.hides ? "Xnext" : "X abc\nnext"))
    }

    @Test("Ctrl-F opens no find bar to light up where a word is", arguments: FieldHiding.allCases)
    func noFind(hiding: FieldHiding) {
        let (app, text, _) = editorApp(hiding, "hunter2")
        app.press(.character("f"), modifiers: .control)
        app.type("Z")
        // Without a find bar, Ctrl-F is a character forward, so Z lands in the
        // text; with one, Z is the bar's query.
        #expect(text.value == (hiding.hides ? "hZunter2" : "hunter2"), "\(app.screen.text)")
    }
}
