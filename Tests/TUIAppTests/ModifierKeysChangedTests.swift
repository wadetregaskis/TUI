//  🖥️ TUI — A Terminal UI framework for Swift
//  ModifierKeysChangedTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// SwiftUI's `onModifierKeysChanged(mask:initial:_:)`, fed by the modifier-key
/// reports a terminal speaking the kitty keyboard protocol sends.
@MainActor
@Suite("onModifierKeysChanged")
struct ModifierKeysChangedTests {

    private final class Log { var entries: [String] = [] }

    private static func describe(_ modifiers: EventModifiers) -> String {
        var names: [String] = []
        if modifiers.contains(.shift) { names.append("⇧") }
        if modifiers.contains(.control) { names.append("⌃") }
        if modifiers.contains(.option) { names.append("⌥") }
        if modifiers.contains(.command) { names.append("⌘") }
        if modifiers.contains(.capsLock) { names.append("⇪") }
        return names.isEmpty ? "-" : names.joined()
    }

    private func view(_ log: Log, mask: EventModifiers = .all, initial: Bool = true) -> some View {
        Text("x").onModifierKeysChanged(mask: mask, initial: initial) { old, new in
            log.entries.append("\(Self.describe(old))→\(Self.describe(new))")
        }
    }

    @Test("Each change of the held keys runs the action with the old and new state")
    func changesReachTheAction() {
        let log = Log()
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(view(log))
        harness.tui.modifierKeys.record(ModifierKeyState(shift: true))
        harness.tui.modifierKeys.record(ModifierKeyState(shift: true, option: true))
        harness.tui.modifierKeys.record(ModifierKeyState(option: true))
        harness.tui.modifierKeys.record(ModifierKeyState())
        #expect(log.entries == ["-→⇧", "⇧→⇧⌥", "⇧⌥→⌥", "⌥→-"])
    }

    @Test("Only changes inside the mask run it, and with the masked state")
    func mask() {
        let log = Log()
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(view(log, mask: .option))
        harness.tui.modifierKeys.record(ModifierKeyState(shift: true))
        harness.tui.modifierKeys.record(ModifierKeyState(shift: true, option: true))
        harness.tui.modifierKeys.record(ModifierKeyState(option: true))
        harness.tui.modifierKeys.record(ModifierKeyState(command: true))
        #expect(log.entries == ["-→⌥", "⌥→-"])
    }

    @Test("Command and Caps Lock are reported as SwiftUI's modifiers")
    func commandAndCapsLock() {
        let log = Log()
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(view(log))
        harness.tui.modifierKeys.record(ModifierKeyState(command: true))
        harness.tui.modifierKeys.record(ModifierKeyState(capsLock: true))
        #expect(log.entries == ["-→⌘", "⌘→⇪"])
    }

    @Test("On appearing, the held keys run the action once when initial is true")
    func initialState() {
        for initial in [true, false] {
            let log = Log()
            let harness = InputChainHarness(keyboard: .requested)
            harness.tui.modifierKeys.record(ModifierKeyState(shift: true))
            harness.frame(view(log, initial: initial))
            harness.frame(view(log, initial: initial))
            #expect(log.entries == (initial ? ["-→⇧"] : []), "initial: \(initial)")
        }
    }

    @Test("Nothing held on appearing runs nothing")
    func initialWithNothingHeld() {
        let log = Log()
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(view(log))
        #expect(log.entries.isEmpty)
    }

    @Test("Each walk registers the observer afresh, so a change runs it once")
    func oneObserverPerWalk() {
        let log = Log()
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(view(log))
        harness.frame(view(log))
        #expect(harness.tui.modifierKeys.observerCount == 1)
        harness.tui.modifierKeys.record(ModifierKeyState(control: true))
        #expect(log.entries == ["-→⌃"])
    }

    @Test("Where the terminal does not report modifier keys, nothing listens")
    func legacyTerminal() {
        let log = Log()
        let harness = InputChainHarness()
        harness.frame(view(log))
        #expect(harness.tui.modifierKeys.observerCount == 0)
        harness.tui.modifierKeys.record(ModifierKeyState(shift: true))
        #expect(log.entries.isEmpty)
    }

    @Test("A change asks for a frame only when the frame on screen drew from the state")
    func frameOnlyWhenDrawnFrom() {
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(view(Log()))
        #expect(!harness.tui.modifierKeys.record(ModifierKeyState(shift: true)))
        harness.tui.modifierKeys.noteDrawnFrom()
        #expect(harness.tui.modifierKeys.record(ModifierKeyState()))
        #expect(!harness.tui.modifierKeys.record(ModifierKeyState()), "no change, no frame")
    }
}
