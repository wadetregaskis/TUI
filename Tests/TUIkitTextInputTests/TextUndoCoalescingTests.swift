//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoCoalescingTests.swift
//
//  A run of typing is one undo step, as the macOS text system makes it
//  (decisions-D1K B-D1K-6). Measured on macOS 15.8 with an offscreen
//  `NSTextView` (the INPUT lane's probe): typed characters — a space and a
//  newline among them — and Backspace, each at the caret the edit before it
//  left, undo together, however long the pauses between them; a caret moved
//  elsewhere ends the run, one moved away and back does not; Delete, a word's
//  deletion and a paste are steps of their own and end it; typing or Backspace
//  over a selection starts a new run, which the typing after it continues.
//  Every case below is one the probe measured, in a field and in an editor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

@MainActor
@Suite("Text controls: a run of typing is one undo step")
struct TextUndoCoalescingTests {
    private final class TextBox: @unchecked Sendable {
        var text: String
        init(_ text: String) { self.text = text }
    }

    /// The two text controls, behind one interface: keys in, text out.
    enum Control: CaseIterable, Sendable {
        case field, editor
    }

    /// A control of `kind` over empty text.
    private func make(_ kind: Control) -> (handle: (KeyEvent) -> Void, text: () -> String) {
        let box = TextBox("")
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        switch kind {
        case .field:
            let field = TextFieldHandler(focusID: "field", text: binding)
            return ({ _ = field.handleKeyEvent($0) }, { box.text })
        case .editor:
            let editor = TextEditorHandler(focusID: "editor", text: binding)
            return ({ _ = editor.handleKeyEvent($0) }, { box.text })
        }
    }

    private static let undo = KeyEvent(key: .character("z"), ctrl: true)
    private static let backspace = KeyEvent(key: .backspace)
    private static let left = KeyEvent(key: .left)
    private static let right = KeyEvent(key: .right)
    private static let home = KeyEvent(key: .home)
    private static let forwardDelete = KeyEvent(key: .delete)
    private static let wordDelete = KeyEvent(key: .backspace, alt: true)
    private static let selectLeft = KeyEvent(key: .left, shift: true)

    private func type(_ text: String, into handle: (KeyEvent) -> Void) {
        for character in text {
            handle(character == " " ? KeyEvent(key: .space) : KeyEvent(key: .character(character)))
        }
    }

    /// Undoes once, and reads the text.
    private func undone(_ control: (handle: (KeyEvent) -> Void, text: () -> String)) -> String {
        control.handle(Self.undo)
        return control.text()
    }

    @Test("A run of typing, spaces and all, is one step", arguments: Control.allCases)
    func typingRun(kind: Control) {
        let control = make(kind)
        type("ab cd", into: control.handle)
        #expect(undone(control).isEmpty)
    }

    @Test("Backspace in a run of typing is part of it", arguments: Control.allCases)
    func backspaceInARun(kind: Control) {
        let control = make(kind)
        type("abc", into: control.handle)
        control.handle(Self.backspace)
        type("de", into: control.handle)
        #expect(control.text() == "abde", "precondition")
        #expect(undone(control).isEmpty)
    }

    @Test("A newline in a run of typing is part of it")
    func newlineInARun() {
        let control = make(.editor)
        type("ab", into: control.handle)
        control.handle(KeyEvent(key: .enter))
        type("cd", into: control.handle)
        #expect(undone(control).isEmpty)
    }

    @Test("A caret moved elsewhere ends the run", arguments: Control.allCases)
    func caretMovedElsewhere(kind: Control) {
        let control = make(kind)
        type("ab", into: control.handle)
        control.handle(Self.home)
        type("cd", into: control.handle)
        #expect(control.text() == "cdab", "precondition")
        #expect(undone(control) == "ab")
        #expect(undone(control).isEmpty)
    }

    @Test("A caret moved away and back does not end the run", arguments: Control.allCases)
    func caretAwayAndBack(kind: Control) {
        let control = make(kind)
        type("ab", into: control.handle)
        control.handle(Self.left)
        control.handle(Self.right)
        type("cd", into: control.handle)
        #expect(undone(control).isEmpty)
    }

    @Test("Delete is a step of its own, and the typing after it another", arguments: Control.allCases)
    func forwardDeleteEndsTheRun(kind: Control) {
        let control = make(kind)
        type("abc", into: control.handle)
        control.handle(Self.left)
        control.handle(Self.forwardDelete)
        type("Z", into: control.handle)
        #expect(control.text() == "abZ", "precondition")
        #expect(undone(control) == "ab")
        #expect(undone(control) == "abc")
        #expect(undone(control).isEmpty)
    }

    @Test("A word's deletion is a step of its own", arguments: Control.allCases)
    func wordDeleteEndsTheRun(kind: Control) {
        let control = make(kind)
        type("ab cd", into: control.handle)
        control.handle(Self.wordDelete)
        type("ef", into: control.handle)
        #expect(control.text() == "ab ef", "precondition")
        #expect(undone(control) == "ab ")
        #expect(undone(control) == "ab cd")
    }

    @Test("A paste is a step of its own", arguments: Control.allCases)
    func pasteEndsTheRun(kind: Control) {
        let control = make(kind)
        type("ab", into: control.handle)
        control.handle(KeyEvent(key: .paste("PP")))
        type("cd", into: control.handle)
        #expect(control.text() == "abPPcd", "precondition")
        #expect(undone(control) == "abPP")
        #expect(undone(control) == "ab")
        #expect(undone(control).isEmpty)
    }

    @Test("Typing over a selection starts a new run, which the typing after it continues")
    func typingOverASelection() {
        let control = make(.field)
        type("abcd", into: control.handle)
        control.handle(Self.selectLeft)
        control.handle(Self.selectLeft)
        type("XY", into: control.handle)
        #expect(control.text() == "abXY", "precondition")
        #expect(undone(control) == "abcd")
        #expect(undone(control).isEmpty)
    }

    @Test("Backspace over a selection starts a new run, which the typing after it continues")
    func backspaceOverASelection() {
        let control = make(.field)
        type("abcd", into: control.handle)
        control.handle(Self.selectLeft)
        control.handle(Self.selectLeft)
        control.handle(Self.backspace)
        type("XY", into: control.handle)
        #expect(control.text() == "abXY", "precondition")
        #expect(undone(control) == "abcd")
        #expect(undone(control).isEmpty)
    }

    @Test("After an undo, typing starts a new run", arguments: Control.allCases)
    func undoEndsTheRun(kind: Control) {
        let control = make(kind)
        type("ab", into: control.handle)
        #expect(undone(control).isEmpty)
        type("cd", into: control.handle)
        #expect(undone(control).isEmpty)
    }

    /// In a running app the run is one step in the app's undo manager too:
    /// the first key registers it, and the rest register nothing.
    @Test("A run of typing is one step of the app's undo manager")
    func oneStepInTheApp() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let box = TextBox("")
        let harness = InputChainHarness(undoManager: manager)
        let field = { TextField("Name", text: Binding(get: { box.text }, set: { box.text = $0 })) }
        harness.play("hello".map { KeyEvent(character: $0) }, field)
        #expect(box.text == "hello", "precondition")
        harness.play([KeyEvent.parse([0x1F])!], field)
        #expect(box.text.isEmpty)
        #expect(!manager.canUndo && manager.canRedo)
    }
}
