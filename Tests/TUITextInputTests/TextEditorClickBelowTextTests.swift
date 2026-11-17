//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorClickBelowTextTests.swift
//
//  A click below a TextEditor's last line puts the caret on that line, at the
//  column clicked, whether the editor wraps or scrolls sideways. Scrolling
//  sideways (`.textEditorWrapsLines(false)`), the click read the line below
//  the text as an empty one, and the caret went to the start of the last line
//  wherever the click was.
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
    @State private var text = "hello\nworld"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text).frame(width: 20, height: 5)
            Text(verbatim: "text=\(text.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "|"))")
        }
    }
}

@MainActor
@Suite("A click below a TextEditor's text")
struct TextEditorClickBelowTextTests {
    @Test("Lands on the last line at the column clicked, wrapping or not", arguments: [true, false])
    func lastLineAtTheColumn(wraps: Bool) {
        let app = TestApp(width: 30, height: 7) { Probe().textEditorWrapsLines(wraps) }
        app.click(at: CellPoint(x: 3, y: 4))
        app.type("X")
        #expect(app.screen.lines[5] == "text=hello|worXld", "\(app.screen.lines.joined(separator: "\n"))")
    }
}
