//  🖥️ TUI — A Terminal UI framework for Swift
//  InsertionPointCursorTests.swift
//
//  Where a frame leaves the terminal's hidden cursor: on the focused text
//  control's insertion point, where a terminal draws what an input method is
//  composing (Apple Terminal's pending accent after ⌥E).
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
@Suite("The terminal's cursor rests on the insertion point")
struct InsertionPointCursorTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    enum Control {
        case field, vertical, editor, button
    }

    private struct InputApp: App {
        let text: Box<String>?
        let control: Control

        init() {
            text = nil
            control = .field
        }

        init(text: Box<String>, control: Control) {
            self.text = text
            self.control = control
        }

        var body: some Scene {
            WindowGroup {
                if let text {
                    let binding = Binding(get: { text.value }, set: { text.value = $0 })
                    VStack(alignment: .leading) {
                        Text("Above")
                        switch control {
                        case .field: TextField("Name", text: binding)
                        case .vertical: TextField("Name", text: binding, axis: .vertical).frame(width: 12)
                        case .editor: TextEditor(text: binding).frame(height: 4)
                        case .button: Button("Press") {}
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let text: Box<String>
        let app: TestApp
        private var now: Int64 = 0

        init(_ control: Control, text: String) {
            self.text = Box(text)
            app = TestApp(InputApp(text: self.text, control: control), width: 40, height: 12)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func type(_ character: Character) {
            app.send(KeyEvent(character: character))
            frame()
        }

        /// The cell just after `text` on the screen.
        func cell(after text: String) throws -> CellPoint {
            let lines = app.screen.lines
            let y = try #require(lines.firstIndex { $0.contains(text) }, "\(text) is on screen")
            let start = try #require(lines[y].range(of: text)).upperBound
            return CellPoint(x: lines[y][..<start].count, y: y)
        }
    }

    @Test("A focused field leaves the cursor on its caret, and moves it as the caret moves")
    func field() throws {
        let harness = Harness(.field, text: "abc")
        #expect(harness.app.cursor == (try harness.cell(after: "abc")))
        harness.type("d")
        #expect(harness.app.cursor == (try harness.cell(after: "abcd")))
        harness.app.send(KeyEvent(key: .left))
        harness.frame()
        #expect(harness.app.cursor == (try harness.cell(after: "abc")))
    }

    @Test("A frame that writes nothing writes nothing to park the cursor either")
    func idleFrame() {
        let harness = Harness(.field, text: "abc")
        let before = harness.app.bytesWritten
        let cursor = harness.app.cursor
        // A frame inside the caret's blink phase, with nothing else moving.
        harness.app.frame(atNanos: 33_333_335)
        #expect(harness.app.bytesWritten == before)
        #expect(harness.app.cursor == cursor)
    }

    @Test("A vertical field's caret is on the row it wrapped to")
    func vertical() throws {
        let harness = Harness(.vertical, text: "one two three")
        #expect(harness.app.cursor == (try harness.cell(after: "three")))
    }

    @Test("An editor's caret is on its line")
    func editor() throws {
        let harness = Harness(.editor, text: "first\nsecond")
        harness.app.send(KeyEvent(key: .down))
        harness.frame()
        harness.app.send(KeyEvent(key: .end))
        harness.frame()
        #expect(harness.app.cursor == (try harness.cell(after: "second")))
    }

    @Test("With no text control focused the cursor is not parked")
    func noTextControl() {
        let harness = Harness(.button, text: "")
        #expect(harness.app.cursor == nil)
    }
}
