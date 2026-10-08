//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoHintKeepingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStrings

/// The status bar's undo and redo hints are worked out once and kept
/// (`AppUndoKeys.hint(for:)`): asked for on every render, each answer built
/// the whole dispatch table. Kept, an answer must still follow each of its
/// inputs — the table, the ⌘ binding, what the terminal reports — and the
/// space bar's name, the one localized word, is never kept.
///
/// What the bar shows is pinned by `AppUndoTests` (`keyNames`,
/// `letterHintsAreWrittenAsTheBarWritesItsItems` and the rest), which change
/// the table and the reporting under one `AppUndoKeys` between reads.
@MainActor
@Suite("The status bar's undo and redo hints, kept between renders")
struct UndoHintKeepingTests {

    @Test("The same inputs return the kept hints, worked out once for both commands")
    func sameInputsKeep() {
        let keys = AppUndoKeys()
        #expect(keys.hint(for: .undo) == "⌃-")
        #expect(keys.hint(for: .redo) == "⌥_")
        #expect(keys.hint(for: .undo) == "⌃-")
        #expect(keys.hintResolutions == 1, "both hints from one resolution")
        // The run loop publishes the scene's table every frame, and the
        // reporting is written as it is: equal values are no change.
        keys.publish(.default, commandKey: .control)
        keys.reporting = .legacy
        #expect(keys.hint(for: .redo) == "⌥_")
        #expect(keys.hintResolutions == 1)
    }

    @Test("A change to the table changes the hint")
    func tableChangesTheHint() {
        let keys = AppUndoKeys()
        #expect(keys.hint(for: .undo) == "⌃-")
        keys.publish(UndoShortcuts([.undo: .only(KeyboardShortcut("z", modifiers: .control))]), commandKey: .control)
        #expect(keys.hint(for: .undo) == "⌃Z")
        keys.publish(.default, commandKey: .control)
        #expect(keys.hint(for: .undo) == "⌃-")
        #expect(keys.hintResolutions == 3)
    }

    @Test("A change to the ⌘ binding changes the hint")
    func commandKeyChangesTheHint() {
        let keys = AppUndoKeys()
        let table = UndoShortcuts([.undo: .only(KeyboardShortcut("u", modifiers: .command))])
        keys.publish(table, commandKey: .control)
        #expect(keys.hint(for: .undo) == "⌃U")
        keys.publish(table, commandKey: .option)
        #expect(keys.hint(for: .undo) == "⌥U")
        keys.publish(table, commandKey: .unavailable)
        #expect(keys.hint(for: .undo) == nil, "⌘ stands for nothing, so no key reaches undo")
    }

    @Test("A change to what the terminal reports changes the hint")
    func reportingChangesTheHint() {
        let keys = AppUndoKeys()
        // A legacy terminal sends Ctrl-_ as Ctrl-minus, so redo names Option-_;
        // the kitty protocol with shifted keys sends it as itself.
        #expect(keys.hint(for: .redo) == "⌥_")
        keys.reporting = KeyboardReporting(flags: .requested)
        #expect(keys.hint(for: .redo) == "⌃_")
        keys.reporting = .legacy
        #expect(keys.hint(for: .redo) == "⌥_")
    }

    /// The space bar's name is a word in the app's language (`KeySymbols.spaceBar`),
    /// which can change with no input to the hint changing — so its name is
    /// written on each read, and only the shortcut is kept. A test cannot
    /// switch the shared service's language under the parallel suite (it
    /// assumes English), so this pins the text and that the table is not
    /// worked out again.
    @Test("A hint on the space bar keeps its shortcut and writes the word afresh")
    func spaceBarHintIsWrittenOnRead() {
        let keys = AppUndoKeys()
        keys.publish(
            UndoShortcuts([.undo: .only(KeyboardShortcut(.space, modifiers: .option))]), commandKey: .control)
        let space = LocalizationService.shared.string(for: "key.space")
        #expect(keys.hint(for: .undo) == "⌥" + space)
        #expect(keys.hint(for: .undo) == "⌥" + space)
        #expect(keys.hint(for: .redo) == "⌥_")
        #expect(keys.hintResolutions == 1)
    }

    private final class Model {
        var value = 0
    }

    /// One undo step, whose undo registers the redo — as `AppUndoTests`'s.
    private func set(_ model: Model, to value: Int, on manager: UndoManager) {
        let old = model.value
        model.value = value
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: model) { [self] model in self.set(model, to: old, on: manager) }
        manager.endUndoGrouping()
    }

    @Test("The bar asks once across renders, and shows what it showed")
    func statusBarAsksOnce() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let model = Model()
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        manager.undo()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        let hints = {
            statusBar.currentSystemItems.filter { $0.order == .undo || $0.order == .redo }.map(\.shortcut)
        }
        #expect(hints() == ["⌃-", "⌥_"])
        #expect(hints() == ["⌃-", "⌥_"])
        #expect(hints() == ["⌃-", "⌥_"])
        #expect(statusBar.undoKeys.hintResolutions == 1)
    }
}
