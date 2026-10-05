//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModifierKeyAlternateTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// SwiftUI's `modifierKeyAlternate(_:_:)`, where a terminal speaking the kitty
/// keyboard protocol reports the modifier keys.
@MainActor
@Suite("modifierKeyAlternate")
struct ModifierKeyAlternateTests {

    private func text(_ buffer: FrameBuffer) -> String {
        buffer.lines.map(\.stripped).joined(separator: "\n").trimmingCharacters(in: .whitespaces)
    }

    private func hold(_ harness: InputChainHarness, _ state: ModifierKeyState) {
        harness.tui.modifierKeys.record(state)
    }

    @Test("The alternate is drawn while its keys are held, and the view the rest of the time")
    func swapsWhileHeld() {
        let harness = InputChainHarness(keyboard: .requested)
        let view = { Text("Forward").modifierKeyAlternate(.option) { Text("Go to…") } }
        #expect(text(harness.frame(view())) == "Forward")
        hold(harness, ModifierKeyState(option: true))
        #expect(text(harness.frame(view())) == "Go to…")
        hold(harness, ModifierKeyState(shift: true, option: true, capsLock: true))
        #expect(text(harness.frame(view())) == "Go to…", "more keys held still include Option")
        hold(harness, ModifierKeyState(shift: true))
        #expect(text(harness.frame(view())) == "Forward")
    }

    @Test("Of several alternates, the one on the most held keys prevails, in either order")
    func mostSpecificPrevails() {
        let innerSpecific = {
            Text("Save")
                .modifierKeyAlternate([.option, .shift]) { Text("Save a Copy") }
                .modifierKeyAlternate(.option) { Text("Save All") }
        }
        let outerSpecific = {
            Text("Save")
                .modifierKeyAlternate(.option) { Text("Save All") }
                .modifierKeyAlternate([.option, .shift]) { Text("Save a Copy") }
        }
        for view in [innerSpecific, outerSpecific] {
            let harness = InputChainHarness(keyboard: .requested)
            #expect(text(harness.frame(view())) == "Save")
            hold(harness, ModifierKeyState(option: true))
            #expect(text(harness.frame(view())) == "Save All")
            hold(harness, ModifierKeyState(shift: true, option: true))
            #expect(text(harness.frame(view())) == "Save a Copy")
        }
    }

    @Test("A frame that drew an alternate asks for another when the keys change")
    func keyChangeAsksForAFrame() {
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(Text("A").modifierKeyAlternate(.control) { Text("B") })
        #expect(harness.tui.modifierKeys.record(ModifierKeyState(control: true)))
    }

    @Test("The alternate's own button is the one Return activates while it is shown")
    func alternateIsLive() {
        let harness = InputChainHarness(keyboard: .requested)
        var fired: [String] = []
        let view = {
            Button("Forward") { fired.append("forward") }
                .modifierKeyAlternate(.option) { Button("Page") { fired.append("page") } }
        }
        harness.frame(view())
        harness.frame(view())
        harness.press(KeyEvent(key: .enter))
        hold(harness, ModifierKeyState(option: true))
        harness.frame(view())
        harness.frame(view())
        harness.press(KeyEvent(key: .enter))
        #expect(fired == ["forward", "page"])
    }

    @Test("Where modifier keys are not reported, the view is always drawn")
    func legacyTerminal() {
        let harness = InputChainHarness()
        hold(harness, ModifierKeyState(option: true))
        #expect(text(harness.frame(Text("Forward").modifierKeyAlternate(.option) { Text("Go to…") })) == "Forward")
    }
}
