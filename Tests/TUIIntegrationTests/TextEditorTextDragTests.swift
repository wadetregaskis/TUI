//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorTextDragTests.swift
//
//  A TextEditor's selected text dragged somewhere else and moved there, as an
//  NSTextView moves it: one step to undo, the text selected where it landed;
//  a press inside the selection that does not move is a click.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("TextEditor moves dragged text")
struct TextEditorTextDragTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private struct EditorApp: App {
        let text: Box<String>?

        init() { text = nil }
        init(text: Box<String>) { self.text = text }

        var body: some Scene {
            WindowGroup {
                if let text {
                    TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                        .frame(width: 40, height: 4)
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let text: Box<String>
        let app: TestApp
        private var now: Int64 = 0
        /// The screen cell of the editor's first character.
        private(set) var origin = CellPoint.zero

        init(_ initial: String) throws {
            text = Box(initial)
            app = TestApp(EditorApp(text: text), width: 60, height: 10)
            frame()
            frame()
            let lines = app.screen.lines
            let first = String(initial.prefix(5))
            let y = try #require(lines.firstIndex { $0.contains(first) })
            origin = CellPoint(x: try #require(lines[y].range(of: first)).lowerBound.utf16Offset(in: lines[y]), y: y)
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        /// A second with nothing happening: what follows is no multi-click.
        func pause() {
            now += 1_000_000_000
            app.frame(atNanos: now)
        }

        /// A left-button event at the editor's column `x`, row `y`.
        func mouse(_ phase: MousePhase, _ x: Int, _ y: Int = 0) {
            app.send(MouseEvent(button: .left, phase: phase, x: origin.x + x, y: origin.y + y))
            frame()
        }

        /// A plain drag from `x0` to `x1` on row `y0`/`y1`.
        func drag(_ x0: Int, _ y0: Int = 0, to x1: Int, _ y1: Int = 0) {
            mouse(.pressed, x0, y0)
            mouse(.dragged, x1, y1)
            mouse(.released, x1, y1)
            pause()
        }

        func key(_ event: KeyEvent) {
            app.send(event)
            frame()
        }
    }

    @Test("A word dragged to the line's end moves there, selected, and Ctrl-Z puts it back")
    func movesAlongTheLine() throws {
        let harness = try Harness("Click anywhere to move the caret")
        harness.drag(5, to: 14)  // " anywhere"
        harness.drag(9, to: 32)  // carried from inside it to the end
        #expect(harness.text.value == "Click to move the caret anywhere")
        harness.key(KeyEvent(character: "X"))
        #expect(harness.text.value == "Click to move the caretX", "the moved text is what is selected")
        harness.key(KeyEvent(key: .character("z"), ctrl: true))
        harness.key(KeyEvent(key: .character("z"), ctrl: true))
        #expect(harness.text.value == "Click anywhere to move the caret", "the move is one step")
    }

    @Test("Dragged text moves to another line, and back to the start of its own")
    func movesAcrossLines() throws {
        let harness = try Harness("alpha bravo\ncharlie")
        harness.drag(5, to: 11)  // " bravo"
        harness.drag(7, to: 7, 1)  // to the end of "charlie"
        #expect(harness.text.value == "alpha\ncharlie bravo")
        let after = try Harness("alpha bravo")
        after.drag(6, to: 11)  // "bravo"
        after.drag(8, to: 0)
        #expect(after.text.value == "bravoalpha ")
    }

    @Test("A press inside the selection that does not move is a click")
    func pressIsAClick() throws {
        let harness = try Harness("alpha bravo")
        harness.drag(6, to: 11)
        harness.mouse(.pressed, 8)
        harness.mouse(.released, 8)
        harness.key(KeyEvent(character: "X"))
        #expect(harness.text.value == "alpha brXavo", "the caret at the click, nothing selected")
    }

    @Test("Dropped inside itself, the text stays, still selected")
    func dropInsideIsNothing() throws {
        let harness = try Harness("alpha bravo")
        harness.drag(6, to: 11)
        harness.drag(7, to: 9)
        #expect(harness.text.value == "alpha bravo")
        harness.key(KeyEvent(character: "X"))
        #expect(harness.text.value == "alpha X", "still selected")
    }
}
