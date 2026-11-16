//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayoutFirstFrameTests.swift
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

/// tuitree's M5 feedback, item 1: in the frame a `TextEditor` first appears,
/// before its render has made its handler, every measure of it laid the whole
/// text out afresh, and the render once more — six layouts of a 3.2 MB file in
/// its pane, 658 ms of a 786 ms open.
@MainActor
@Suite("Editor layout: the first frame lays the text out once")
struct EditorLayoutFirstFrameTests {
    typealias Frames = EditorLayoutTests.Frames
    typealias Box = EditorLayoutTests.Box

    /// The pane's shape: the editor beside other content and under a
    /// heading, so its stacks measure it more than once before drawing it.
    struct Pane: View {
        let text: Box
        let wraps: Bool
        var body: some View {
            HStack(spacing: 1) {
                Text("Tree")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Source")
                    TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                        .textEditorWrapsLines(wraps)
                }
            }
        }
    }

    /// How many texts `body` splits into lines whole.
    func layouts(_ body: () -> Void) -> Int {
        let count = Mutex(0)
        EditorLayout.$buildReporter.withValue({ count.withLock { $0 += 1 } }, operation: body)
        return count.withLock { $0 }
    }

    @Test("The frame an editor first appears in lays its text out once", arguments: [false, true])
    func firstFrameLaysOutOnce(wraps: Bool) {
        let frames = Frames(width: 40, height: 12)
        let page = Pane(text: Box(EditorLayoutTests.longDocument), wraps: wraps)
        let first = layouts { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        #expect(first == 1)
        let next = layouts { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        #expect(next == 0)
    }

    @Test("A redacted editor's first frame lays its hidden text out once")
    func redactedFirstFrameLaysOutOnce() {
        let frames = Frames(width: 40, height: 12)
        let page = Pane(text: Box(EditorLayoutTests.longDocument), wraps: true).redacted(reason: .placeholder)
        let first = layouts { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        // The hidden text, as drawn, once (six times before); and the text
        // itself, once, by the render, whose caret is placed in its lines.
        #expect(first == 2)
    }

    /// The layout kept for the render is the text the measure saw: a text
    /// changed between the measure and the render is laid out again rather
    /// than drawn from the measure's.
    @Test("A text changed between the first measure and the first render is laid out afresh")
    func changedTextIsLaidOutAgain() throws {
        let frames = Frames(width: 40, height: 12)
        let box = Box("one")
        let editor = TextEditor(text: Binding(get: { box.value }, set: { box.value = $0 }))
        _ = frames.pass {
            _ = measureChild(editor, proposal: ProposedViewSize(width: 40, height: nil), context: frames.context)
            box.value = "two\nlines"
            return renderToBuffer(editor, context: frames.context)
        }
        #expect(try #require(frames.handler).layout().lines == [["t", "w", "o"], ["l", "i", "n", "e", "s"]])
    }
}
