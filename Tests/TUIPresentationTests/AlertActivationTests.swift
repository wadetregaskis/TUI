//  🖥️ TUI — A Terminal UI framework for Swift
//  AlertActivationTests.swift
//
//  Escape on an alert closes it, through a status-bar item's action, which the
//  run loop draws before reading on (`ActivationHold`). So a second Escape read
//  right behind the first finds the alert gone, and runs no cancel action twice.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("An alert's activations", .rendersEnglishUI)
struct AlertActivationTests {
    private final class Shown { var value = true }

    private func escapeActivates<Actions: View>(@ViewBuilder _ actions: @escaping () -> Actions) -> Bool {
        let appState = AppState()
        let harness = InputChainHarness(width: 60, height: 20)
        let shown = Shown()
        let binding = Binding(get: { shown.value }, set: { shown.value = $0 })
        func view() -> some View {
            Text("base").alert("Warning", isPresented: binding, actions: actions)
        }
        return AmbientApp.$renderState.withValue(appState) {
            harness.frame(view())
            harness.frame(view())
            harness.press(KeyEvent(key: .escape))
            #expect(!shown.value)
            return appState.consumeControlActivated()
        }
    }

    @Test("Escape counts, with a cancel button whose action it runs")
    func cancelButton() {
        #expect(
            escapeActivates {
                Button("OK") {}
                Button("Cancel", role: .cancel) {}
            })
    }

    @Test("Escape counts with none, as it closes the alert all the same")
    func noCancelButton() {
        #expect(escapeActivates { Button("OK") {} })
    }
}
