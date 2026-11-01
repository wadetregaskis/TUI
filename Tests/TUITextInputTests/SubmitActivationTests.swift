//  🖥️ TUI — A Terminal UI framework for Swift
//  SubmitActivationTests.swift
//
//  A text field's submit is a control's action, which the run loop draws before
//  reading on (`ActivationHold`), and its editing is not: typing and a paste stay
//  one batch.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput
@testable import TUIView

@MainActor
@Suite("A text field's activations")
struct SubmitActivationTests {
    private final class Text0 { var value = "" }

    private func activates(_ events: [KeyEvent], submits: Bool) -> Bool {
        let appState = AppState()
        let harness = InputChainHarness()
        let text = Text0()
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        func view() -> some View {
            Group {
                if submits {
                    TextField("Name", text: binding).onSubmit {}
                } else {
                    TextField("Name", text: binding)
                }
            }
        }
        return AmbientApp.$renderState.withValue(appState) {
            harness.frame(view())
            harness.frame(view())
            for event in events { harness.press(event) }
            return appState.consumeControlActivated()
        }
    }

    @Test("Return in a field with a submit action counts")
    func submit() {
        #expect(activates([KeyEvent(key: .enter)], submits: true))
    }

    @Test("Return in a field with none, which falls through, does not")
    func noSubmit() {
        #expect(!activates([KeyEvent(key: .enter)], submits: false))
    }

    @Test("Typing, arrow keys and a paste do not")
    func editing() {
        let typing = [KeyEvent(key: .character("a")), KeyEvent(key: .character("b")), KeyEvent(key: .left)]
        #expect(!activates(typing, submits: true))
        #expect(!activates([KeyEvent(key: .paste("pasted\rwords"))], submits: true))
    }
}
