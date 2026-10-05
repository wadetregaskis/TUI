//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppUndoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The app's undo manager (decisions A1): in the environment, undone and
/// redone by the keys the owner chose, and offered in the status bar.
@MainActor
@Suite("The app's undo manager")
struct AppUndoTests {

    private final class Model {
        var value = 0
    }

    /// An undo manager whose steps are its explicit groups, so a test does not
    /// depend on a run loop turning; each `set` below is one.
    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    private func set(_ model: Model, to value: Int, on manager: UndoManager) {
        let old = model.value
        model.value = value
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: model) { [self] model in self.set(model, to: old, on: manager) }
        manager.endUndoGrouping()
    }

    // MARK: - The keys

    @Test("Which keys undo, and which redo")
    func undoKeys() {
        let control = { (character: Character, shift: Bool) in
            KeyEvent(key: .character(character), ctrl: true, shift: shift)
        }
        // Undo: Ctrl-minus (0x1F, from every terminal), Ctrl-/ (kitty).
        #expect(UndoKey(KeyEvent.parse([0x1F])!) == .undo)
        #expect(UndoKey(control("-", false)) == .undo)
        #expect(UndoKey(control("/", false)) == .undo)
        // Redo: Ctrl-Shift-Z, Ctrl-_ with and without the shifted key, Option-_.
        #expect(UndoKey(control("Z", true)) == .redo)
        #expect(UndoKey(control("z", true)) == .redo)
        #expect(UndoKey(control("_", true)) == .redo)
        #expect(UndoKey(control("-", true)) == .redo)
        #expect(UndoKey(KeyEvent.parse([0x1B, 0x5F])!) == .redo)
        // Neither: Ctrl-Z is the suspend key, Ctrl-Y the yank; a release is
        // not a press.
        #expect(UndoKey(control("z", false)) == nil)
        #expect(UndoKey(control("y", false)) == nil)
        #expect(UndoKey(KeyEvent(key: .character("-"), ctrl: true, phase: .release)) == nil)
        #expect(UndoKey(KeyEvent(character: "-")) == nil)
    }

    @Test("Ctrl-minus undoes and Ctrl-Shift-Z redoes, through the input chain")
    func keysThroughTheChain() {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(undoManager: manager)
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        let consumed = harness.play([
            KeyEvent.parse([0x1F])!, KeyEvent.parse([0x1F])!, KeyEvent.parse([0x1F])!,
            KeyEvent(key: .character("Z"), ctrl: true, shift: true),
        ]) { Text("page") }
        #expect(model.value == 1)
        #expect(consumed == [true, true, false, true], "with nothing to undo, the key is not taken")
    }

    @Test("Ctrl-Shift-Z with nothing to redo does nothing; Ctrl-Z still suspends")
    func redoKeyNeverSuspends() {
        let harness = InputChainHarness(undoManager: makeManager())
        harness.play([KeyEvent(key: .character("Z"), ctrl: true, shift: true)]) { Text("page") }
        #expect(harness.suspends == 0)
        harness.play([KeyEvent(key: .character("z"), ctrl: true)]) { Text("page") }
        #expect(harness.suspends == 1)
    }

    @Test("An app's own shortcut on Ctrl-minus keeps the key")
    func appShortcutWins() {
        let manager = makeManager()
        let model = Model()
        var zoomed = 0
        let harness = InputChainHarness(undoManager: manager)
        set(model, to: 1, on: manager)
        harness.play([KeyEvent(key: .character("-"), ctrl: true)]) {
            Button("Zoom Out") { zoomed += 1 }.keyboardShortcut("-", modifiers: .control)
        }
        #expect(zoomed == 1)
        #expect(model.value == 1, "the undo stayed put")
    }

    // MARK: - The environment

    @Test("The environment carries the app's undo manager, and nil outside an app")
    func environment() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        #expect(environment.undoManager == nil)
        let manager = makeManager()
        tui.undoManager = manager
        environment.applyRuntimeServices(from: tui)
        #expect(environment.undoManager === manager)
    }

    // MARK: - The status bar

    private func labels(_ statusBar: StatusBarState) -> [String] {
        statusBar.currentSystemItems.map(\.shortcut)
    }

    @Test("The bar shows undo and redo only while there is a step for each, and a click performs it")
    func statusBarItems() throws {
        let manager = makeManager()
        let model = Model()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        #expect(!labels(statusBar).contains("^-"))
        set(model, to: 1, on: manager)
        #expect(labels(statusBar).contains("^-"))
        #expect(!labels(statusBar).contains("M-_"))

        let undo = try #require(statusBar.currentSystemItems.first { $0.shortcut == "^-" })
        undo.execute()
        #expect(model.value == 0)
        #expect(labels(statusBar) == labels(statusBar).filter { $0 != "^-" })

        let redo = try #require(statusBar.currentSystemItems.first { $0.shortcut == "M-_" })
        redo.execute()
        #expect(model.value == 1)
    }

    @Test("Redo is named Ctrl-_ where the terminal tells it from Ctrl-minus, and Option-_ elsewhere")
    func redoKeyName() {
        let manager = makeManager()
        let model = Model()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        set(model, to: 1, on: manager)
        manager.undo()
        #expect(labels(statusBar).contains("M-_"))
        statusBar.redoIsControlUnderscore = true
        #expect(labels(statusBar).contains("^_"))
    }

    @Test("An app can turn the items off")
    func itemsOff() {
        let manager = makeManager()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        statusBar.showUndoItems = false
        set(Model(), to: 1, on: manager)
        #expect(!labels(statusBar).contains("^-"))
    }
}
