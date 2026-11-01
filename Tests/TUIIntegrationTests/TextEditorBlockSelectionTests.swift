//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorBlockSelectionTests.swift
//
//  A TextEditor's rectangular selection: Option-drag selects the same columns
//  of every row, Copy takes them row by row, an edit takes them out of every
//  row, and Shift partway through swaps which corner the pointer moves.
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
@Suite("TextEditor block selection")
struct TextEditorBlockSelectionTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private struct EditorApp: App {
        let board: FakeClipboard?
        let text: Box<String>?
        let wraps: Bool

        init() {
            board = nil
            text = nil
            wraps = true
        }

        init(board: FakeClipboard, text: Box<String>, wraps: Bool) {
            self.board = board
            self.text = text
            self.wraps = wraps
        }

        var body: some Scene {
            WindowGroup {
                if let board, let text {
                    TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                        .frame(width: 20, height: 4)
                        .textEditorWrapsLines(wraps)
                        .environment(\.clipboardAccess, board.access)
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let board = FakeClipboard()
        let text: Box<String>
        let app: TestApp
        private var now: Int64 = 0
        /// The screen cell of the editor's first character.
        private(set) var origin = CellPoint.zero

        init(wraps: Bool = true) throws {
            text = Box("alpha\nbravo\ncharlie")
            app = TestApp(EditorApp(board: board, text: text, wraps: wraps), width: 40, height: 10)
            frame()
            frame()
            let lines = app.screen.lines
            let y = try #require(lines.firstIndex { $0.contains("alpha") })
            origin = CellPoint(x: try #require(lines[y].range(of: "alpha")).lowerBound.utf16Offset(in: lines[y]), y: y)
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
        func mouse(_ phase: MousePhase, _ x: Int, _ y: Int, meta: Bool = false, shift: Bool = false) {
            app.send(MouseEvent(button: .left, phase: phase, x: origin.x + x, y: origin.y + y, shift: shift, meta: meta))
            frame()
        }

        /// Option-drags from (`x0`, `y0`) to (`x1`, `y1`).
        func block(_ x0: Int, _ y0: Int, to x1: Int, _ y1: Int) {
            mouse(.pressed, x0, y0, meta: true)
            mouse(.dragged, x1, y1, meta: true)
            mouse(.released, x1, y1, meta: true)
        }

        func key(_ event: KeyEvent) {
            app.send(event)
            frame()
        }
    }

    @Test("Option-drag selects the same columns of every row, and Ctrl-C copies them row by row", arguments: [
        true, false,
    ])
    func copies(wraps: Bool) throws {
        let harness = try Harness(wraps: wraps)
        harness.block(1, 0, to: 3, 2)
        harness.key(KeyEvent(key: .character("c"), ctrl: true))
        #expect(harness.board.writes == ["lp\nra\nha"])
        #expect(harness.text.value == "alpha\nbravo\ncharlie", "copying changes nothing")
    }

    @Test("Backspace takes the columns out of every row, and Ctrl-Z puts them back")
    func deletes() throws {
        let harness = try Harness()
        harness.block(1, 0, to: 3, 2)
        harness.key(KeyEvent(key: .backspace))
        #expect(harness.text.value == "aha\nbvo\ncrlie")
        harness.key(KeyEvent(key: .character("z"), ctrl: true))
        #expect(harness.text.value == "alpha\nbravo\ncharlie")
    }

    @Test("Typing replaces the block once, at its top-left corner")
    func typingReplaces() throws {
        let harness = try Harness()
        harness.block(1, 0, to: 3, 2)
        harness.key(KeyEvent(character: "X"))
        #expect(harness.text.value == "aXha\nbvo\ncrlie")
    }

    @Test("Cut from the context menu copies and takes out the block")
    func menuCut() throws {
        let harness = try Harness()
        harness.block(1, 0, to: 3, 2)
        harness.app.send(MouseEvent(button: .right, phase: .pressed, x: harness.origin.x + 1, y: harness.origin.y))
        harness.app.send(MouseEvent(button: .right, phase: .released, x: harness.origin.x + 1, y: harness.origin.y))
        harness.frame()
        let lines = harness.app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains("Cut") })
        let x = try #require(lines[y].range(of: "Cut")).lowerBound.utf16Offset(in: lines[y])
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
        harness.frame()
        #expect(harness.board.writes == ["lp\nra\nha"])
        #expect(harness.text.value == "aha\nbvo\ncrlie")
    }

    @Test("Shift partway through swaps which corner the pointer moves")
    func cornerSwap() throws {
        let harness = try Harness()
        harness.mouse(.pressed, 1, 0, meta: true)
        harness.mouse(.dragged, 3, 2, meta: true)
        // Shift down: the press's corner follows the pointer; moving it one
        // column right leaves columns 2..<3.
        harness.mouse(.dragged, 3, 2, meta: true, shift: true)
        harness.mouse(.dragged, 4, 2, meta: true, shift: true)
        harness.mouse(.released, 4, 2, meta: true, shift: true)
        harness.key(KeyEvent(key: .character("c"), ctrl: true))
        #expect(harness.board.writes == ["p\na\na"])
    }

    @Test("An Option-click selects nothing, and a click drops a block")
    func clicks() throws {
        let harness = try Harness()
        harness.block(2, 1, to: 2, 1)
        harness.key(KeyEvent(key: .character("c"), ctrl: true))
        #expect(harness.board.writes.isEmpty)
        harness.block(1, 0, to: 3, 2)
        harness.pause()
        harness.mouse(.pressed, 0, 0)
        harness.mouse(.released, 0, 0)
        harness.key(KeyEvent(key: .character("c"), ctrl: true))
        #expect(harness.board.writes.isEmpty)
    }
}
