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

    private static let controlZ = KeyEvent(key: .character("z"), ctrl: true)
    private static let controlShiftZ = KeyEvent(key: .character("Z"), ctrl: true, shift: true)
    private static let controlMinus = KeyEvent.parse([0x1F])!

    @Test("Which keys undo, and which redo, by default")
    func undoKeys() {
        let keys = AppUndoKeys()
        let control = { (character: Character) in KeyEvent(key: .character(character), ctrl: true) }
        // Undo: Ctrl-Z, Ctrl-minus (0x1F, which Ctrl-/ and Ctrl-_ also send in
        // a legacy encoding), Ctrl-/ (kitty); and Ctrl-Shift-Z in a legacy
        // encoding, where it is Ctrl-Z's 0x1A.
        #expect(keys.command(for: KeyEvent.parse([0x1A])!) == .undo)
        #expect(keys.command(for: Self.controlMinus) == .undo)
        #expect(keys.command(for: control("-")) == .undo)
        #expect(keys.command(for: control("/")) == .undo)
        // Redo: Ctrl-Shift-Z and Ctrl-_ where the terminal reports them,
        // Option-_ where Option is Meta.
        #expect(keys.command(for: Self.controlShiftZ) == .redo)
        #expect(keys.command(for: control("_")) == .redo)
        #expect(keys.command(for: KeyEvent.parse([0x1B, 0x5F])!) == .redo)
        // Neither: Ctrl-Y is the yank; a release is not a press; a minus is a
        // minus.
        #expect(keys.command(for: control("y")) == nil)
        #expect(keys.command(for: KeyEvent(key: .character("-"), ctrl: true, phase: .release)) == nil)
        #expect(keys.command(for: KeyEvent(character: "-")) == nil)
    }

    @Test("The keys undo and redo through the input chain, and a bound key is taken with nothing to do")
    func keysThroughTheChain() {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(undoManager: manager)
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        let consumed = harness.play([Self.controlZ, Self.controlMinus, Self.controlMinus, Self.controlShiftZ]) {
            Text("page")
        }
        #expect(model.value == 1)
        #expect(consumed == [true, true, true, true], "the third has nothing to undo, and is still undo's")
    }

    @Test("Bound to undo, Ctrl-Z never suspends; taken out of undo, it suspends again")
    func controlZSuspendsOnlyUnbound() {
        let harness = InputChainHarness(undoManager: makeManager())
        harness.play([Self.controlZ, Self.controlShiftZ, KeyEvent.parse([0x1A])!]) { Text("page") }
        #expect(harness.suspends == 0, "nothing to undo or redo, and nothing happens")
        harness.tui.undoKeys.publish(
            UndoShortcuts([
                .undo: .only(KeyboardShortcut("-", modifiers: .control)),
                .redo: .only(KeyboardShortcut("_", modifiers: .option)),
            ]),
            commandKey: .control)
        harness.play([Self.controlZ]) { Text("page") }
        #expect(harness.suspends == 1)
        harness.play([Self.controlShiftZ]) { Text("page") }
        #expect(harness.suspends == 2, "Ctrl-Shift-Z too, which a legacy encoding sends as Ctrl-Z")
        let model = Model()
        let manager = harness.handler.undoManager!
        set(model, to: 1, on: manager)
        harness.play([Self.controlMinus]) { Text("page") }
        #expect(model.value == 0, "the keys left bound still undo")
    }

    @Test("Without an app's undo manager Ctrl-Z suspends, as it always did")
    func noManagerSuspends() {
        let harness = InputChainHarness()
        harness.play([Self.controlZ]) { Text("page") }
        #expect(harness.suspends == 1)
    }

    @Test("An app's table: an override takes a default's chord, and ⌘ resolves through the command key")
    func appTable() {
        let keys = AppUndoKeys()
        // Ctrl-Y for redo, as some editors have it; ⌘Z (Ctrl-Z) for redo too,
        // taken from undo's defaults.
        keys.publish(
            UndoShortcuts([.redo: .default.and(KeyboardShortcut("y", modifiers: .control), KeyboardShortcut("z"))]),
            commandKey: .control)
        #expect(keys.command(for: KeyEvent(key: .character("y"), ctrl: true)) == .redo)
        #expect(keys.command(for: Self.controlZ) == .redo)
        #expect(keys.command(for: Self.controlMinus) == .undo)
        keys.publish(UndoShortcuts([.undo: .unbound]), commandKey: .control)
        #expect(keys.command(for: Self.controlZ) == nil)
        #expect(keys.command(for: Self.controlShiftZ) == .redo)
    }

    @Test("Two overrides on one chord are reported, and undo keeps it")
    func overrideClash() {
        var reports: [String] = []
        let table = UndoShortcuts([
            .undo: [KeyboardShortcut("u", modifiers: .control)],
            .redo: [KeyboardShortcut("u", modifiers: .control)],
        ])
        let lookup = table.lookup(commandKey: .control, onClash: { reports.append($0) })
        #expect(lookup[.key("u", .control)] == .undo)
        #expect(reports == ["undoShortcuts binds ^U to both undo and redo; undo, which UndoCommand declares first, keeps it"])
    }

    @Test("A frame publishes the scene's undo keys to the input chain")
    func framePublishesKeys() {
        let harness = RenderLoopHarness()
        #expect(harness.tuiContext.undoKeys.command(for: Self.controlZ) == .undo)
        harness.loop(SuspendingApp()).render()
        #expect(harness.tuiContext.undoKeys.command(for: Self.controlZ) == nil)
        #expect(harness.tuiContext.undoKeys.command(for: Self.controlMinus) == .undo)
    }

    @Test("The scene modifier writes the table into the root environment")
    func sceneModifier() {
        let table: [UndoCommand: ShortcutSet] = [.undo: .only(KeyboardShortcut("-", modifiers: .control))]
        let scene = WindowGroup { Text("page") }.undoShortcuts(table)
        var environment = EnvironmentValues()
        #expect(environment.undoShortcuts == .default)
        scene.applyingRootEnvironment(to: &environment)
        #expect(environment.undoShortcuts == UndoShortcuts(table))
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

    @Test("The bar names the first key of each the terminal can deliver")
    func keyNames() {
        let manager = makeManager()
        let model = Model()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        manager.undo()
        // A legacy terminal: Ctrl-minus for undo; for redo, Ctrl-_ and
        // Ctrl-Shift-Z cannot be sent apart from Ctrl-minus and Ctrl-Z, so
        // Option-_.
        #expect(labels(statusBar).contains("^-") && labels(statusBar).contains("M-_"))
        // The kitty protocol with shifted keys: Ctrl-_.
        statusBar.undoKeys.reporting = KeyboardReporting(flags: .requested)
        #expect(labels(statusBar).contains("^-") && labels(statusBar).contains("^_"))
        // The app's own keys: Ctrl-Z alone for undo, Ctrl-Shift-Z alone for
        // redo — which a legacy terminal cannot send, so the bar names none.
        statusBar.undoKeys.publish(
            UndoShortcuts([
                .undo: [KeyboardShortcut("z", modifiers: .control)],
                .redo: [KeyboardShortcut("z", modifiers: [.control, .shift])],
            ]),
            commandKey: .control)
        #expect(labels(statusBar).contains("^Z") && labels(statusBar).contains("^S-Z"))
        statusBar.undoKeys.reporting = .legacy
        #expect(labels(statusBar).contains("^Z") && labels(statusBar).contains(""))
    }

    @Test("The bar's items name their keys and bind none: each key goes where it would without them")
    func statusBarItemsBindNoKey() throws {
        let manager = makeManager()
        let model = Model()
        let harness = InputChainHarness(undoManager: manager)
        // Undo on Option-←, whose name has an arrow in it; redo on a bare u,
        // vim's way, a one-character name. (Option-← itself never reaches the
        // undo keys outside a text control: the focus system, ahead of them,
        // takes every arrow.)
        harness.tui.undoKeys.publish(
            UndoShortcuts([
                .undo: .only(KeyboardShortcut(.leftArrow, modifiers: .option)),
                .redo: .only(KeyboardShortcut("u", modifiers: [])),
            ]),
            commandKey: .control)
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        var heard: [Key] = []
        let page = {
            Text("page").onKeyEvent { event in
                guard event.key == .character("u") else { return false }
                heard.append(event.key)
                return true
            }
        }
        let undo = try #require(harness.statusBar.currentSystemItems.first { $0.order == .undo })
        #expect(undo.shortcut == "M-←")
        harness.play([KeyEvent(key: .left)], page)
        #expect(model.value == 2, "a plain ← is not Option-←, whatever the bar prints beside undo")
        manager.undo()
        let redo = try #require(harness.statusBar.currentSystemItems.first { $0.order == .redo })
        #expect(redo.shortcut == "u")
        harness.play([KeyEvent(character: "u")], page)
        #expect(heard == [.character("u")], "the view's handler hears u, as it does with nothing to redo")
        #expect(model.value == 1)
    }

    @Test("Undo and redo with no key to name are still two items")
    func statusBarItemIdentities() {
        let manager = makeManager()
        let model = Model()
        let statusBar = StatusBarState()
        statusBar.undoManager = manager
        // Neither key reaches the app from a legacy terminal, so the bar names
        // none for either.
        statusBar.undoKeys.publish(
            UndoShortcuts([
                .undo: .only(KeyboardShortcut("/", modifiers: .control)),
                .redo: .only(KeyboardShortcut("z", modifiers: [.control, .shift])),
            ]),
            commandKey: .control)
        set(model, to: 1, on: manager)
        set(model, to: 2, on: manager)
        manager.undo()
        let items = statusBar.currentSystemItems.filter { $0.order == .undo || $0.order == .redo }
        #expect(items.map(\.shortcut) == ["", ""])
        #expect(Set(items.map(\.id)).count == 2, "each its own hover")
    }

    @Test("What a terminal can deliver as itself")
    func deliverability() {
        let legacy = KeyboardReporting.legacy
        let kitty = KeyboardReporting(flags: .requested)
        let noShifted = KeyboardReporting(flags: [.disambiguateEscapeCodes])
        let chord = { (key: KeyEquivalent, modifiers: EventModifiers) in KeyboardShortcut(key, modifiers: modifiers) }
        #expect(chord("z", .control).isDeliverable(on: legacy))
        #expect(chord("-", .control).isDeliverable(on: legacy))
        #expect(!chord("/", .control).isDeliverable(on: legacy), "arrives as Ctrl-minus")
        #expect(!chord("_", .control).isDeliverable(on: legacy))
        #expect(!chord("z", [.control, .shift]).isDeliverable(on: legacy), "arrives as Ctrl-Z")
        #expect(!chord("h", .control).isDeliverable(on: legacy), "arrives as Backspace")
        #expect(chord("_", .option).isDeliverable(on: legacy))
        #expect(chord("/", .control).isDeliverable(on: kitty))
        #expect(chord("_", .control).isDeliverable(on: kitty))
        #expect(chord("z", [.control, .shift]).isDeliverable(on: kitty))
        #expect(!chord("_", .control).isDeliverable(on: noShifted), "the shifted key is not reported")
        #expect(chord("z", [.control, .shift]).isDeliverable(on: noShifted), "a letter's capital is always known")
        #expect(!chord("z", .command).isDeliverable(on: kitty))
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

/// An app that wants Ctrl-Z to suspend, as in a shell.
private struct SuspendingApp: App {
    var body: some Scene {
        WindowGroup { Text("page") }
            .undoShortcuts([.undo: .only(KeyboardShortcut("-", modifiers: .control))])
    }
}
