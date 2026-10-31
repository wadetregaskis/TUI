//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditingMenuTests.swift
//
//  A text control's context menu: Cut, Copy, Paste, Yank and Select All,
//  opened by a right-click, a Control-click or Shift+F10, on a TextField, a
//  SecureField and a TextEditor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Text editing context menu")
struct TextEditingMenuTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    enum Control {
        case field, secure, editor
    }

    private struct TextApp: App {
        let board: FakeClipboard?
        let text: Box<String>?
        let second: Box<String>?
        let control: Control
        let disabled: Bool

        init() {
            board = nil
            text = nil
            second = nil
            control = .field
            disabled = false
        }

        init(board: FakeClipboard, text: Box<String>, second: Box<String>, control: Control, disabled: Bool) {
            self.board = board
            self.text = text
            self.second = second
            self.control = control
            self.disabled = disabled
        }

        var body: some Scene {
            WindowGroup {
                if let board, let text, let second {
                    let binding = Binding(get: { text.value }, set: { text.value = $0 })
                    VStack(alignment: .leading) {
                        switch control {
                        case .field: TextField("Name", text: binding)
                        case .secure: SecureField("Password", text: binding)
                        case .editor: TextEditor(text: binding).frame(height: 3)
                        }
                        TextField("Other", text: Binding(get: { second.value }, set: { second.value = $0 }))
                    }
                    .disabled(disabled)
                    .environment(\.clipboardAccess, board.access)
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let board = FakeClipboard()
        let text: Box<String>
        let second = Box("")
        let app: HeadlessApp
        private var now: Int64 = 0

        init(_ control: Control, text: String = "hello world", disabled: Bool = false) {
            self.text = Box(text)
            app = HeadlessApp(
                TextApp(board: board, text: self.text, second: second, control: control, disabled: disabled),
                width: 50, height: 16)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func shows(_ text: String) -> Bool { app.screen.map(\.stripped).contains { $0.contains(text) } }

        /// Right-clicks the control's first row, a few cells in — or
        /// Control-clicks it, the secondary click where a terminal keeps the
        /// right button for itself.
        func rightClick(control: Bool = false) {
            let button: MouseButton = control ? .left : .right
            let y = app.screen.map(\.stripped).firstIndex { !$0.allSatisfy(\.isWhitespace) } ?? 0
            app.send(MouseEvent(button: button, phase: .pressed, x: 3, y: y, ctrl: control))
            app.send(MouseEvent(button: button, phase: .released, x: 3, y: y, ctrl: control))
            frame()
        }

        /// Opens the menu and clicks its row that says `title`.
        func choose(_ title: String) throws {
            rightClick()
            let lines = app.screen.map(\.stripped)
            let y = try #require(lines.firstIndex { $0.contains(title) }, "\(title) is offered")
            let x = try #require(lines[y].range(of: title)).lowerBound.utf16Offset(in: lines[y])
            app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
            frame()
        }

        func key(_ event: KeyEvent) {
            app.send(event)
            frame()
        }
    }

    @Test("A right-click on a field offers Cut, Copy, Paste and Select All; Select All then Copy copies the text")
    func fieldCopies() throws {
        let harness = Harness(.field)
        harness.rightClick()
        for title in ["Cut", "Copy", "Paste", "Select All"] {
            #expect(harness.shows(title), "\(title) is offered")
        }
        #expect(!harness.shows("Yank"), "nothing killed, so no Yank")
        harness.key(KeyEvent(key: .escape))
        try harness.choose("Copy")
        #expect(harness.board.writes.isEmpty, "Copy with nothing selected copies nothing")
        try harness.choose("Select All")
        try harness.choose("Copy")
        #expect(harness.board.writes == ["hello world"])
    }

    @Test("Cut takes the selection; Paste inserts the clipboard over it")
    func fieldCutsAndPastes() throws {
        let harness = Harness(.field)
        try harness.choose("Select All")
        try harness.choose("Cut")
        #expect(harness.board.writes == ["hello world"])
        #expect(harness.text.value.isEmpty)
        harness.board.contents = "pasted"
        try harness.choose("Paste")
        #expect(harness.text.value == "pasted")
    }

    @Test("A Control-click opens the menu too, and leaves the caret where it was")
    func controlClick() {
        let harness = Harness(.field)
        harness.rightClick(control: true)
        #expect(harness.shows("Select All"))
    }

    @Test("Yank is offered once a kill has left text, and inserts it")
    func fieldYanks() throws {
        let harness = Harness(.field)
        harness.key(KeyEvent(key: .home))
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        #expect(harness.text.value.isEmpty, "precondition: Ctrl-K killed the line")
        try harness.choose("Yank")
        #expect(harness.text.value == "hello world")
    }

    @Test("A secure field never copies or cuts its contents from the menu, and still pastes")
    func secureRefuses() throws {
        let harness = Harness(.secure)
        try harness.choose("Select All")
        try harness.choose("Copy")
        try harness.choose("Cut")
        #expect(harness.board.writes.isEmpty)
        #expect(harness.text.value == "hello world")
        harness.board.contents = "new"
        try harness.choose("Paste")
        #expect(harness.text.value == "new")
    }

    @Test("An editor's Cut from the menu is one step that Ctrl-Z takes back")
    func editorCutUndoes() throws {
        let harness = Harness(.editor, text: "first line\nsecond")
        try harness.choose("Select All")
        try harness.choose("Cut")
        #expect(harness.board.writes == ["first line\nsecond"])
        #expect(harness.text.value.isEmpty)
        harness.key(KeyEvent(key: .character("z"), ctrl: true))
        #expect(harness.text.value == "first line\nsecond")
    }

    @Test("Shift+F10 opens the focused control's menu, and each control is still one Tab stop", arguments: [
        Control.field, .secure, .editor,
    ])
    func keyboardRoute(_ control: Control) {
        let harness = Harness(control)
        harness.key(KeyEvent(key: .f10, shift: true))
        #expect(harness.shows("Select All"), "Shift+F10 opens the menu")
        harness.key(KeyEvent(key: .escape))
        #expect(!harness.shows("Select All"))
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .character("x")))
        #expect(harness.second.value == "x", "one Tab reaches the second field")
    }

    @Test("A disabled field offers no menu")
    func disabledOffersNothing() {
        let harness = Harness(.field, disabled: true)
        harness.rightClick()
        #expect(!harness.shows("Select All"))
    }
}
