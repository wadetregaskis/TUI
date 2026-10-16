//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoHintKeepingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

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
        #expect(keys.hint(for: .undo) == "⌃Z")
        #expect(keys.hint(for: .redo) == "⌥_")
        #expect(keys.hint(for: .undo) == "⌃Z")
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
        #expect(keys.hint(for: .undo) == "⌃Z")
        keys.publish(UndoShortcuts([.undo: .only(KeyboardShortcut("-", modifiers: .control))]), commandKey: .control)
        #expect(keys.hint(for: .undo) == "⌃-")
        keys.publish(.default, commandKey: .control)
        #expect(keys.hint(for: .undo) == "⌃Z")
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
        // A legacy terminal sends Ctrl-Shift-Z as Ctrl-Z and Ctrl-_ as
        // Ctrl-minus, so redo names Option-_; the kitty protocol sends
        // Ctrl-Shift-Z as itself.
        #expect(keys.hint(for: .redo) == "⌥_")
        keys.reporting = KeyboardReporting(flags: .requested)
        #expect(keys.hint(for: .redo) == "⌃⇧Z")
        keys.reporting = .legacy
        #expect(keys.hint(for: .redo) == "⌥_")
    }

    /// The space bar's name is a word in the app's language (`KeySymbols.spaceBar`),
    /// which can change with no input to the hint changing — so its name is
    /// written on each read, and only the shortcut is kept. This pins the
    /// text the bar's own writer gives under the shared service, and that
    /// the table is not worked out again; the language switch itself is
    /// `spaceBarHintFollowsTheLanguage`.
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

    /// The review's case (2026-10-08): the language changes under a kept
    /// ⌥Space undo hint, and the bar must follow it, from ⌥Space to
    /// ⌥Leertaste. The shared service's language cannot be switched under the
    /// parallel suite, so the bar's writer is given a service of the test's
    /// own (`AppUndoKeys(writingNamesWith:)`): the real spelling, with the
    /// space bar's word read from that service.
    @Test("A hint on the space bar follows the app's language, with the table kept")
    func spaceBarHintFollowsTheLanguage() {
        let directory = NSTemporaryDirectory() + "tuikit-undo-hint-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let service = LocalizationService(configDirectoryPath: directory)
        service.pinLanguageForTesting(.english)
        var written: [String] = []
        let keys = AppUndoKeys(writingNamesWith: { shortcut in
            let word = service.string(for: LocalizationKey.KeyName.space.rawValue)
            let name = KeySymbols.statusBarName(of: shortcut)?.replacingOccurrences(of: KeySymbols.spaceBar, with: word)
            written.append(name ?? "nil")
            return name
        })
        keys.publish(
            UndoShortcuts([.undo: .only(KeyboardShortcut(.space, modifiers: .option))]), commandKey: .control)
        #expect(keys.hint(for: .undo) == "⌥Space")
        #expect(keys.hint(for: .redo) == "⌥_")
        service.pinLanguageForTesting(.german)
        #expect(keys.hint(for: .undo) == "⌥Leertaste", "the word is the language of the moment")
        #expect(keys.hint(for: .redo) == "⌥_")
        #expect(keys.hintResolutions == 1, "the table is worked out once")
        // Redo's name was written once, when the hints were worked out; the
        // space bar's on each read of it.
        #expect(written == ["⌥_", "⌥Space", "⌥Leertaste"])
    }

    private final class Model {
        var value = 0
    }

    /// One undo step, whose undo registers the redo — as `AppUndoTests`'s.
    private func set(_ model: Model, to value: Int, on manager: UndoManager) {
        let old = model.value
        model.value = value
        manager.beginUndoGrouping()
        // The manager runs the handler on the main actor; the macOS 15 SDK's
        // handler is only `@Sendable`, so the manager and the model cross into
        // it as the framework's do (`MainActorUndoManager`).
        let reference = MainActorUndoManager(manager)
        manager.registerUndo(withTarget: model) { [self] model in
            nonisolated(unsafe) let model = model
            MainActor.assumeIsolated { self.set(model, to: old, on: reference.manager) }
        }
        manager.endUndoGrouping()
    }

    /// The bar asks for both hints each time it draws (`StatusBar` reads
    /// `currentSystemItems`): three frames of the real bar show the same
    /// hints, worked out once.
    @Test("The bar works its hints out once across three frames, and shows what it showed")
    func statusBarAsksOnce() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let model = Model()
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        manager.undo()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        let frame = {
            let context = makeRenderContext(width: 60, height: 1) { environment, _ in
                environment.statusBar = statusBar
            }
            return renderToBuffer(StatusBar(), context: context).lines.joined().stripped
        }
        for _ in 0..<3 {
            let line = frame()
            #expect(line.contains("⌃Z") && line.contains("⌥_"), "both hints on the bar: '\(line)'")
        }
        let hints = statusBar.currentSystemItems.filter { $0.order == .undo || $0.order == .redo }.map(\.shortcut)
        #expect(hints == ["⌃Z", "⌥_"])
        #expect(statusBar.undoKeys.hintResolutions == 1)
    }
}
