//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonRoleLabelTests.swift
//
//  `Button(role:action:)` and the `.close`/`.confirm` roles: a button with a
//  role and no label shows the title its role implies.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

/// Counts presses.
private final class Presses: @unchecked Sendable {
    var count = 0
}

@MainActor
@Suite("Button(role:action:)")
struct ButtonRoleLabelTests {
    private func text<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 2)).lines.first?.stripped ?? ""
    }

    @Test("Each role's button shows the title the role implies")
    func titles() {
        #expect(text(Button(role: .cancel) {}).contains("Cancel"))
        #expect(text(Button(role: .close) {}).contains("Close"))
        #expect(text(Button(role: .confirm) {}).contains("Done"))
        #expect(text(Button(role: .destructive) {}).contains("Delete"))
        #expect(text(DefaultButtonLabel(role: .close)) == "Close")
    }

    @Test("A role-only button acts like any other")
    func acts() {
        let presses = Presses()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .enter)]) { Button(role: .confirm) { presses.count += 1 } }
        #expect(presses.count == 1)
    }
}
