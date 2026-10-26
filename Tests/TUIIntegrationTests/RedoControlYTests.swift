//  🖥️ TUI — A Terminal UI framework for Swift
//  RedoControlYTests.swift
//
//  ⌃Y is redo app-wide, the one redo key every terminal sends, and a focused
//  text control keeps it as its yank; the redo hint follows the focus, naming
//  another key while a text control has it (the owner's ruling FB9-REDO,
//  2026-10-23).
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
@testable import TUITestSupport

@MainActor
@Suite("⌃Y redoes, but in a text field")
struct RedoControlYTests {
    private final class Model {
        var value = 0
    }

    private final class TextBox {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private static let controlY = KeyEvent(key: .character("y"), ctrl: true)
    private static let controlK = KeyEvent(key: .character("k"), ctrl: true)

    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    /// One undo step, whose undo registers the redo — as `AppUndoTests`'s.
    private func set(_ model: Model, to value: Int, on manager: UndoManager) {
        let old = model.value
        model.value = value
        manager.beginUndoGrouping()
        let reference = MainActorUndoManager(manager)
        manager.registerUndo(withTarget: model) { [self] model in
            nonisolated(unsafe) let model = model
            MainActor.assumeIsolated { self.set(model, to: old, on: reference.manager) }
        }
        manager.endUndoGrouping()
    }

    /// The redo item's key on the harness's status bar.
    private func redoHint(_ harness: InputChainHarness) -> String? {
        harness.statusBar.currentSystemItems.first { $0.order == .redo }?.shortcut
    }

    @Test("⌃Y redoes from anywhere but a text control, its legacy byte included")
    func controlYRedoes() {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(undoManager: manager)
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        manager.undo()
        manager.undo()
        let consumed = harness.play([Self.controlY, KeyEvent.parse([0x19])!]) {
            Button("Go") {}
        }
        #expect(model.value == 2)
        #expect(consumed == [true, true])
    }

    @Test("In a focused text field ⌃Y yanks what ⌃K killed, and redoes nothing")
    func textFieldKeepsYank() {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(undoManager: manager)
        set(model, to: 1, on: manager)
        manager.undo()
        let text = TextBox("")
        // The caret starts at the end; Home, then ⌃K kills it all, ⌃Y yanks it.
        text.value = "abc"
        harness.play([KeyEvent(key: .home), Self.controlK, Self.controlY]) {
            TextField("Field", text: Binding(get: { text.value }, set: { text.value = $0 }))
        }
        #expect(text.value == "abc")
        #expect(model.value == 0, "no redo")
    }

    @Test("The redo hint names ⌃Y, and another key while a text field has the focus")
    func hintFollowsTheFocus() {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(undoManager: manager)
        set(model, to: 1, on: manager)
        manager.undo()
        harness.frame(Button("Go") {})
        #expect(redoHint(harness) == "⌃Y")
        harness.frame(TextField("Field", text: .constant("")))
        harness.frame(TextField("Field", text: .constant("")))
        #expect(redoHint(harness) == "⌥_", "a legacy terminal sends neither ⌃⇧Z nor ⌃_ apart")
    }

    @Test("Under the kitty protocol the redo hint is ⌃⇧Z, focus or no focus")
    func kittyHintIsControlShiftZ() {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(keyboard: .requested, undoManager: manager)
        set(model, to: 1, on: manager)
        manager.undo()
        harness.frame(Button("Go") {})
        #expect(redoHint(harness) == "⌃⇧Z")
        harness.frame(TextField("Field", text: .constant("")))
        harness.frame(TextField("Field", text: .constant("")))
        #expect(redoHint(harness) == "⌃⇧Z")
    }
}
