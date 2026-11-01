//  🖥️ TUI — A Terminal UI framework for Swift
//  ListActivationTests.swift
//
//  A row's primary action is an action, which the run loop draws before reading
//  on (`ActivationHold`), and list navigation is not: arrow keys stay one batch.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A list's activations")
struct ListActivationTests {
    private final class Picked { var value: Int? }

    private func activates(_ event: KeyEvent) -> Bool {
        let appState = AppState()
        let harness = InputChainHarness()
        let picked = Picked()
        let selection = Binding(get: { picked.value }, set: { picked.value = $0 })
        func view() -> some View {
            List(selection: selection) {
                ForEach(0..<5, id: \.self) { Text("row \($0)") }
            }
            .contextMenu(forSelectionType: Int.self) { _ in } primaryAction: { _ in }
        }
        return AmbientApp.$renderState.withValue(appState) {
            harness.frame(view())
            harness.frame(view())
            harness.press(event)
            return appState.consumeControlActivated()
        }
    }

    @Test("Return on a row with a primary action counts")
    func primaryAction() {
        #expect(activates(KeyEvent(key: .enter)))
    }

    @Test("Moving through the rows and selecting one do not", arguments: [Key.down, .up, .pageDown, .space])
    func navigation(key: Key) {
        #expect(!activates(KeyEvent(key: key)))
    }
}
