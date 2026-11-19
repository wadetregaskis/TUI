//  🖥️ TUI — A Terminal UI framework for Swift
//  PastedLineBreakTests.swift
//
//  A field on one line keeps a pasted line break, as SwiftUI's does, and draws
//  it as a mark in its row. Measured on macOS 15.8.3: SwiftUI's TextField and
//  SecureField bind a pasted "ab\ncd" as "ab\ncd", U+2028 and U+2029 as
//  themselves, and no paste submits (`Tools/SwiftUIProbes/Pasted line breaks
//  and drops (1117)/paste.out`). TUI dropped the break ("abcd"), joining the
//  words on either side of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput
@testable import TUIView

@MainActor
@Suite("A pasted line break in a field on one line")
struct PastedLineBreakTests {
    private final class Box {
        var text = ""
        var submits = 0
    }

    /// What a paste of `pasted` binds in an empty field on one line, a
    /// TextField or a SecureField with an `onSubmit`, through the input chain
    /// as a terminal's bracketed paste arrives, how many times it submitted,
    /// and the row the field draws on the frame after.
    private func paste(_ pasted: String, secure: Bool) -> (text: String, submits: Int, row: String) {
        let box = Box()
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let harness = InputChainHarness()
        func view() -> some View {
            Group {
                if secure {
                    SecureField("Password", text: binding).onSubmit { box.submits += 1 }
                } else {
                    TextField("Name", text: binding).onSubmit { box.submits += 1 }
                }
            }
        }
        harness.frame(view())
        harness.frame(view())
        _ = harness.press(KeyEvent(key: .paste(pasted)))
        let row = harness.frame(view()).lines.first?.stripped ?? ""
        return (box.text, box.submits, row)
    }

    /// Pasted, then bound: each break as one newline whatever convention it
    /// came in (a terminal sends a pasted break as CR), the separators and a
    /// tab as themselves.
    private static let cases: [(pasted: String, bound: String)] = [
        ("ab\ncd", "ab\ncd"),
        ("ab\r\ncd", "ab\ncd"),
        ("ab\rcd", "ab\ncd"),
        ("ab\tcd", "ab\tcd"),
        ("ab\u{2028}cd", "ab\u{2028}cd"),
        ("ab\u{2029}cd", "ab\u{2029}cd"),
        ("abcd\n", "abcd\n"),
    ]

    @Test("A TextField and a SecureField keep a pasted line break, and a paste never submits", arguments: [false, true])
    func pasteKeepsTheBreak(secure: Bool) {
        for (pasted, bound) in Self.cases {
            let result = paste(pasted, secure: secure)
            #expect(result.text == bound, "\(pasted.debugDescription) bound \(result.text.debugDescription)")
            #expect(result.submits == 0, "\(pasted.debugDescription) submitted")
        }
    }

    /// A newline in a field's text drew as a mark before the paste kept one
    /// (it is a control character, which a field always drew as one), so only
    /// a pasted one says anything: until the paste kept it, the row read
    /// "abcd".
    @Test("A pasted newline draws in the field's row as one mark, not as the words run together")
    func pastedNewlineDrawsAsAMark() {
        let row = paste("ab\ncd", secure: false).row
        #expect(row.contains("ab\u{FFFD}cd"), "drew \(row.debugDescription)")
    }

    /// The separators, which are not control characters, drew raw until the
    /// field drew every line break as a mark.
    @Test("A field on one line draws a line separator as one replacement mark, the text after it in view")
    func breakDrawsAsAMark() {
        let context = makeRenderContext(width: 20, height: 1)
        for text in ["ab\u{2028}cd", "ab\u{2029}cd"] {
            let drawn = renderToBuffer(TextField("", text: .constant(text)), context: context)
            let row = drawn.lines.first?.stripped ?? ""
            #expect(row.contains("ab\u{FFFD}cd"), "\(text.debugDescription) drew \(row.debugDescription)")
        }
    }
}
