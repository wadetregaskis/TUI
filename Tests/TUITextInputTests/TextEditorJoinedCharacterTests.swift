//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorJoinedCharacterTests.swift
//
//  An edit in a TextEditor that brings two halves of a character together —
//  Backspace or Delete joining "e" to a line that starts with a combining
//  acute, a character taken out from between two regional indicators — leaves
//  the line as its string's characters. The editor kept the halves apart in
//  its lines while the text held one character, so the caret sat between
//  them, and the next key typed went in there: the accent moved to the "Y"
//  typed after the "e", and the "Y" split the flag.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
import TUICore
import TUIFoundation
import TUITesting
import TUITextInput

private struct Probe: View {
    @State private var text: String
    init(text: String) { _text = State(initialValue: text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text).frame(width: 20, height: 3)
            Text(verbatim: "[\(text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))]")
        }
    }
}

@MainActor
@Suite("A TextEditor edit that joins the halves of a character")
struct TextEditorJoinedCharacterTests {
    /// What the probe prints for `text`: its scalars, in hexadecimal.
    private func scalars(_ text: String) -> String {
        "[\(text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))]"
    }

    private func run(_ text: String, _ keys: (TestApp) -> Void) -> String {
        let app = TestApp(width: 30, height: 4) { Probe(text: text) }
        keys(app)
        app.type("Y")
        return app.screen.lines[3]
    }

    @Test("Backspace joining a line that starts with a combining mark: what is typed goes after the accented letter")
    func backspaceJoin() {
        let drawn = run("e\n\u{301}x") { app in
            app.press(.home)
            app.press(.down)
            app.press(.backspace)
        }
        #expect(drawn == scalars("e\u{301}Yx"))
    }

    @Test("Delete joining the same lines from the end of the first")
    func deleteJoin() {
        let drawn = run("e\n\u{301}x") { app in
            app.press(.home)
            app.press(.right)
            app.press(.delete)
        }
        #expect(drawn == scalars("e\u{301}Yx"))
    }

    @Test("Backspace taking out a character between two regional indicators: what is typed goes after the flag")
    func flagJoin() {
        let drawn = run("\u{1F1FA}X\u{1F1F8}") { app in
            app.press(.home)
            app.press(.right, times: 2)
            app.press(.backspace)
        }
        #expect(drawn == scalars("\u{1F1FA}\u{1F1F8}Y"))
    }

    /// The regional indicators pair afresh: "🇺" and "🇸🇬" are "🇺🇸" and "🇬",
    /// as many characters as before the edit, cut in other places.
    @Test("Backspace taking out a character before a flag that a lone indicator then pairs with")
    func flagPairsAfresh() {
        let drawn = run("\u{1F1FA}X\u{1F1F8}\u{1F1EC}") { app in
            app.press(.home)
            app.press(.right, times: 2)
            app.press(.backspace)
        }
        #expect(drawn == scalars("\u{1F1FA}\u{1F1F8}Y\u{1F1EC}"))
    }
}
