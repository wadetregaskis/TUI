//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusScopeTests.swift
//
//  `.focusScope(_:)`, `.prefersDefaultFocus(_:in:)` and `\.resetFocus`,
//  through the real input chain: the preferred control takes the initial
//  focus without the first control flickering through it, a focus the user
//  already placed is left alone, and a reset puts the focus back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitView

/// What the page's controls did.
private final class Log {
    var pressed: [String] = []
    var focusChanges: [String] = []
    var show = true
    var reset: (() -> Void)?
}

/// A scope of three fields, the second preferred, and a reset button.
private struct Page: View {
    @Namespace private var scope
    @Environment(\.resetFocus) private var resetFocus
    let log: Log
    var prefers = true
    var scoped = true

    var body: some View {
        let scope = scope
        log.reset = { [resetFocus] in resetFocus(in: scope) }
        return VStack {
            Button("outside") { log.pressed.append("outside") }
            if log.show {
                fields
            }
        }
    }

    @ViewBuilder private var fields: some View {
        let inner = VStack {
            Button("first") { log.pressed.append("first") }
            Button("preferred") { log.pressed.append("preferred") }
                .prefersDefaultFocus(prefers, in: scope)
            Button("last") { log.pressed.append("last") }
        }
        if scoped { inner.focusScope(scope) } else { inner }
    }
}

@MainActor
@Suite("Focus scopes and default focus")
struct FocusScopeTests {
    private let enter = KeyEvent(key: .enter)
    private let tab = KeyEvent(key: .tab)

    /// Which button Return presses now.
    private func focused(_ harness: InputChainHarness, _ log: Log, _ page: () -> Page) -> String? {
        let before = log.pressed.count
        harness.press(enter)
        harness.frame(page())
        return log.pressed.count > before ? log.pressed.last : nil
    }

    @Test("At launch the preferred control takes the focus, though a control comes before its scope")
    func initialFocus() {
        let harness = InputChainHarness()
        let log = Log()
        let page = { Page(log: log) }
        harness.frame(page())
        harness.frame(page())
        #expect(
            focused(harness, log, page) == "preferred",
            "the first control's focus was the manager's own choice, not one anybody made")
    }

    @Test("At launch, inside the scope, the preferred control beats the first one")
    func initialFocusInsideScope() {
        let harness = InputChainHarness()
        let log = Log()
        let page = { ScopedOnly(log: log) }
        harness.frame(page())
        harness.frame(page())
        let before = log.pressed.count
        harness.press(enter)
        #expect(log.pressed.count == before + 1 && log.pressed.last == "preferred")
        #expect(log.focusChanges.isEmpty, "the first field never held the focus, not even for a frame")
    }

    @Test("A scope appearing while the focus is elsewhere does not take it")
    func doesNotSteal() {
        let harness = InputChainHarness()
        let log = Log()
        log.show = false
        let page = { Page(log: log) }
        harness.frame(page())
        harness.frame(page())
        #expect(focused(harness, log, page) == "outside")
        log.show = true
        harness.frame(page())
        harness.frame(page())
        #expect(focused(harness, log, page) == "outside")
    }

    @Test("resetFocus moves the focus back to the preferred control from inside the scope")
    func resetFromInside() {
        let harness = InputChainHarness()
        let log = Log()
        let page = { Page(log: log) }
        harness.frame(page())
        harness.frame(page())
        harness.press(tab)  // preferred, the launch focus → last
        harness.frame(page())
        #expect(focused(harness, log, page) == "last")
        log.reset?()
        harness.frame(page())
        #expect(focused(harness, log, page) == "preferred")
    }

    @Test("resetFocus leaves a focus outside the scope where it is")
    func resetFromOutside() {
        let harness = InputChainHarness()
        let log = Log()
        let page = { Page(log: log) }
        harness.frame(page())
        harness.frame(page())
        harness.press(KeyEvent(key: .tab, shift: true))  // preferred → first
        harness.frame(page())
        harness.press(KeyEvent(key: .tab, shift: true))  // → outside
        harness.frame(page())
        #expect(focused(harness, log, page) == "outside")
        log.reset?()
        harness.frame(page())
        #expect(focused(harness, log, page) == "outside")
    }

    @Test("With no preference in the scope, resetFocus goes to the scope's first control")
    func resetWithoutPreference() {
        let harness = InputChainHarness()
        let log = Log()
        let page = { Page(log: log, prefers: false) }
        harness.frame(page())
        harness.press(tab)
        harness.frame(page())
        harness.press(tab)
        harness.frame(page())
        harness.press(tab)
        harness.frame(page())
        #expect(focused(harness, log, page) == "last")
        log.reset?()
        harness.frame(page())
        #expect(focused(harness, log, page) == "first")
    }

    @Test("Without a focus scope, the preference applies to the whole screen")
    func unscopedPreference() {
        let harness = InputChainHarness()
        let log = Log()
        let page = { Page(log: log, scoped: false) }
        harness.frame(page())
        harness.frame(page())
        #expect(focused(harness, log, page) == "preferred", "nothing else held the focus at launch")
    }
}

/// The scope with nothing before it, so it holds the launch focus.
private struct ScopedOnly: View {
    @Namespace private var scope
    let log: Log

    var body: some View {
        VStack {
            // A field, because it says when it takes and loses the focus.
            TextField("first", text: .constant(""))
                .onEditingChanged { log.focusChanges.append($0 ? "first+" : "first-") }
            Button("preferred") { log.pressed.append("preferred") }
                .prefersDefaultFocus(in: scope)
        }
        .focusScope(scope)
    }
}
