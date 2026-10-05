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

    /// A view with state of its own, for the tests of what an alternate keeps.
    private struct Counter: View {
        @State private var count = 0
        var body: some View {
            Button("n=\(count)") { count += 1 }
        }
    }

    @Test("The modified view keeps its @State through a frame of its alternate")
    func keepsState() {
        let harness = InputChainHarness(keyboard: .requested)
        let view = { Counter().modifierKeyAlternate(.option) { Text("alt") } }
        harness.play([KeyEvent(key: .enter), KeyEvent(key: .enter), KeyEvent(key: .enter)], view)
        #expect(text(harness.frame(view())).contains("n=3"))
        hold(harness, ModifierKeyState(option: true))
        #expect(text(harness.frame(view())) == "alt")
        hold(harness, ModifierKeyState())
        #expect(text(harness.frame(view())).contains("n=3"))
    }

    /// Two buttons and a third, the first with an alternate that has no control
    /// of its own, each named so a test can ask where the focus is.
    private func focusPage() -> some View {
        VStack {
            Button("Forward") {}.focusID("forward")
                .modifierKeyAlternate(.option) { Text("Go to…") }
            Button("Other") {}.focusID("other")
            Button("Third") {}.focusID("third")
        }
    }

    @Test("The focus goes back to the modified view when the keys are released", arguments: [1, 3])
    func focusReturns(framesHeld: Int) {
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(focusPage())
        harness.frame(focusPage())
        #expect(harness.focusManager.currentFocusedID == "forward")
        hold(harness, ModifierKeyState(option: true))
        for _ in 0..<framesHeld { harness.frame(focusPage()) }
        #expect(harness.focusManager.currentFocusedID == "other", "the recovery moves it off the hidden control")
        hold(harness, ModifierKeyState())
        harness.frame(focusPage())
        #expect(harness.focusManager.currentFocusedID == "forward")
    }

    @Test("The focus comes back after a frame the run loop walked twice", arguments: [1, 3])
    func focusReturnsAfterACorrectedFrame(framesHeld: Int) {
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(focusPage())
        harness.frame(focusPage())
        hold(harness, ModifierKeyState(option: true))
        for _ in 0..<framesHeld { harness.frame(focusPage(), walks: 2) }
        #expect(harness.focusManager.currentFocusedID == "other")
        hold(harness, ModifierKeyState())
        harness.frame(focusPage(), walks: 2)
        #expect(harness.focusManager.currentFocusedID == "forward")
    }

    @Test("A focus the user moved while the alternate showed stays where they put it")
    func movedFocusStays() {
        let harness = InputChainHarness(keyboard: .requested)
        harness.frame(focusPage())
        harness.frame(focusPage())
        hold(harness, ModifierKeyState(option: true))
        harness.frame(focusPage())
        harness.frame(focusPage())
        harness.press(KeyEvent(key: .tab))
        harness.frame(focusPage())
        #expect(harness.focusManager.currentFocusedID == "third")
        hold(harness, ModifierKeyState())
        harness.frame(focusPage())
        #expect(harness.focusManager.currentFocusedID == "third")
    }

    /// A row a value memo can keep, whose alternate is wider than itself.
    private struct Row: View, Equatable {
        let name: String
        var body: some View {
            Text(name).modifierKeyAlternate(.option) { Text(name + " (all)") }
        }
    }

    @Test("A memoised ancestor measures the alternate, not the size it kept for the modified view")
    func memoisedSizeFollowsTheKeys() {
        let harness = InputChainHarness(keyboard: .requested)
        let view = { HStack(spacing: 0) { Row(name: "ab").equatable(); Text("|") } }
        #expect(text(harness.frame(view())) == "ab|")
        #expect(text(harness.frame(view())) == "ab|")
        hold(harness, ModifierKeyState(option: true))
        #expect(text(harness.frame(view())) == "ab (all)|")
    }

    @Test("Where modifier keys are not reported, the view is always drawn")
    func legacyTerminal() {
        let harness = InputChainHarness()
        hold(harness, ModifierKeyState(option: true))
        #expect(text(harness.frame(Text("Forward").modifierKeyAlternate(.option) { Text("Go to…") })) == "Forward")
    }
}
