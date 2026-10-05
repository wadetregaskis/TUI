//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoManagerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// `TextField` and `TextEditor` register their edits with the app's undo
/// manager (decisions A1), so undo means something by default: Ctrl-minus and
/// the status bar undo typing, a control's Ctrl-Z undoes the app's newest
/// step, and redo puts it back.
@MainActor
@Suite("Text controls and the app's undo manager")
struct TextUndoManagerTests {

    private final class TextBox {
        var value = ""
    }

    /// Steps are explicit groups here, so a test does not depend on a run
    /// loop turning: each registration is its own step, as each event's are
    /// in a running app.
    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    private func typed(_ text: String) -> [KeyEvent] {
        text.map { KeyEvent(character: $0) }
    }

    private static let undoKey = KeyEvent.parse([0x1F])!
    private static let redoKey = KeyEvent(key: .character("Z"), ctrl: true, shift: true)
    private static let controlZ = KeyEvent(key: .character("z"), ctrl: true)

    private func field(_ box: TextBox) -> some View {
        TextField("Name", text: Binding(get: { box.value }, set: { box.value = $0 }))
    }

    @Test("A field's typing is the app's to undo, and its undo the app's to redo")
    func fieldTypingUndoesAndRedoes() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("ab") + [Self.undoKey]) { field(box) }
        #expect(box.value == "a")
        #expect(manager.canUndo && manager.canRedo)
        harness.play([Self.undoKey, Self.redoKey, Self.redoKey]) { field(box) }
        #expect(box.value == "ab")
        #expect(!manager.canRedo)
    }

    @Test("A field's Ctrl-Z undoes the app's newest step, as ⌘Z undoes a window's")
    func fieldControlZIsTheAppsUndo() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("x")) { field(box) }
        // The app registers something after the typing.
        final class Flag { var on = true }
        let flag = Flag()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: flag) { $0.on = false }
        manager.endUndoGrouping()
        harness.play([Self.controlZ]) { field(box) }
        #expect(!flag.on, "the app's step was newest")
        #expect(box.value == "x")
        harness.play([Self.controlZ]) { field(box) }
        #expect(box.value.isEmpty)
    }

    @Test("A field's undo stays in the app's history when it loses the focus, as its own history always did")
    func fieldKeepsUndoOnFocusLoss() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                self.field(box)
                Button("Other") {}
            }
        }
        harness.play(typed("ab") + [KeyEvent(key: .tab), Self.undoKey], page)
        #expect(box.value == "a")
        harness.play([KeyEvent(key: .tab, shift: true), Self.controlZ], page)
        #expect(box.value.isEmpty, "and the field's own Ctrl-Z after it")
    }

    private final class Flag {
        var on = true
    }

    @Test("A control that leaves the screen takes its steps out of the app's history", arguments: [false, true])
    func removedControlForgetsItsSteps(editor: Bool) {
        let manager = makeManager()
        let box = TextBox()
        let shown = Flag()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                if shown.on {
                    if editor {
                        TextEditor(text: Binding(get: { box.value }, set: { box.value = $0 }))
                    } else {
                        self.field(box)
                    }
                }
                Button("Other") {}
            }
        }
        harness.play(typed("abc") + [Self.undoKey], page)
        #expect(box.value == "ab")
        #expect(manager.canUndo && manager.canRedo)
        shown.on = false
        harness.frame(page())
        harness.frame(page())
        #expect(!manager.canUndo && !manager.canRedo, "no step left whose control is gone")
        harness.play([Self.undoKey, Self.redoKey], page)
        #expect(box.value == "ab")
    }

    @Test("A step the control's own history let go of past its limit leaves the app's history with it")
    func droppedPastTheLimit() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed(String(repeating: "x", count: 53))) { field(box) }
        harness.play(Array(repeating: Self.undoKey, count: 50)) { field(box) }
        #expect(box.value == "xxx", "the fifty newest steps undone")
        #expect(!manager.canUndo, "the three oldest, whose states the field let go of, are not offered")
        #expect(manager.canRedo)
    }

    @Test("An editor's edits are the app's to undo, across a change of focus")
    func editorEdits() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                TextEditor(text: Binding(get: { box.value }, set: { box.value = $0 }))
                Button("Other") {}
            }
        }
        harness.play(typed("hi") + [KeyEvent(key: .tab), Self.undoKey], page)
        #expect(box.value == "h")
        harness.play([Self.redoKey], page)
        #expect(box.value == "hi")
    }

    @Test("Text the app replaced is not brought back, and its steps are forgotten")
    func replacementForgetsSteps() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("ab")) { field(box) }
        box.value = "other"
        harness.play([KeyEvent(key: .end)] + typed("!")) { field(box) }
        #expect(box.value == "other!")
        harness.play([Self.undoKey, Self.undoKey]) { field(box) }
        #expect(box.value == "other")
        #expect(!manager.canUndo)
    }

    @Test("Without an app, a field's Ctrl-Z and Ctrl-Shift-Z work on its own history")
    func fieldWithoutAnApp() {
        let box = TextBox()
        let harness = InputChainHarness()
        harness.play(typed("ab") + [Self.controlZ, Self.controlZ, Self.redoKey]) { field(box) }
        #expect(box.value == "a")
    }

    @Test("A secure field's typing stays out of the app's history")
    func secureFieldStaysOut() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("pw")) {
            SecureField("Password", text: Binding(get: { box.value }, set: { box.value = $0 }))
        }
        #expect(box.value == "pw")
        #expect(!manager.canUndo)
    }
}
