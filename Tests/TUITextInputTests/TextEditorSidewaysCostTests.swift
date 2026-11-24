//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorSidewaysCostTests.swift
//
//  What a frame of an editor that scrolls sideways costs over long lines, in
//  characters stepped over to find their cells (H-88, TEXTIN-7): about the
//  window's, not the lines'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("TextEditor: a sideways frame's cost")
struct TextEditorSidewaysCostTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    /// The characters stepped over, as `TabLayout.walkReporter` is told of them.
    final class Steps: @unchecked Sendable {
        var count = 0
    }

    static let (width, height, lineLength) = (80, 20, 10_000)

    struct Page: View {
        let text: Box
        var body: some View {
            TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                .frame(width: TextEditorSidewaysCostTests.width, height: TextEditorSidewaysCostTests.height)
                .textEditorWrapsLines(false)
        }
    }

    /// `height` lines of `lineLength` characters: words, with tabs, wide CJK,
    /// or combining accents and a ZWJ emoji between them, by line.
    static func document() -> String {
        let between = [" ", "\t", " 漢字 ", " cafe\u{301} 👩‍💻\t"]
        return (0..<height).map { line in
            var text = ""
            var count = 0
            while count < lineLength {
                let token = ("word" + between[line % between.count]).prefix(lineLength - count)
                text += token
                count += token.count
            }
            return text
        }.joined(separator: "\n")
    }

    /// The characters `body` stepped over.
    func steps(_ body: () -> Void) -> Int {
        let steps = Steps()
        TabLayout.$walkReporter.withValue(TaskLocalReporter { steps.count += $0 }) { body() }
        return steps.count
    }

    @Test("A frame scrolled far along 20 lines of 10,000 characters steps over about its window's characters")
    func frameCost() throws {
        let harness = InputChainHarness(width: 100, height: 30)
        let page = Page(text: Box(Self.document()))
        harness.frame(page)
        harness.frame(page)
        let handler = try #require(harness.focusManager.currentFocused as? TextEditorHandler)
        handler.moveCursor(toLine: 3, column: 8_000)
        harness.frame(page)
        #expect(handler.scrollColumn > 8_000)
        // Each row walks from a sample before its window to its window's end;
        // the caret's column from its sample. Today 20 × 10,000 and more.
        let bound = Self.height * (Self.width + 2 * 64)
        let drawn = steps { harness.frame(page) }
        #expect(drawn <= bound, "a frame stepped over \(drawn) characters")
        let moved = steps {
            harness.press(KeyEvent(key: .right))
            harness.frame(page)
        }
        #expect(moved <= bound, "a move and its frame stepped over \(moved) characters")
        // The edited line is walked once more, to sample it again.
        let typed = steps {
            harness.press(KeyEvent(key: .character("x")))
            harness.frame(page)
        }
        #expect(typed <= Self.lineLength + 1 + bound, "a key and its frame stepped over \(typed) characters")
    }
}
