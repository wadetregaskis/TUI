//  🖥️ TUI — A Terminal UI framework for Swift
//  ConditionalStateUnderRetentionTests.swift
//
//  A view an `if` removes loses its `@State`, as SwiftUI's does, even under a
//  container that keeps its subtree's state while rows are windowed out — a
//  lazy stack, a `List`. The prune at a pass's end took a removed view's
//  state everywhere else; under such a container the view came back with it:
//  an `if`/`else` kept the state its branch's own view held at the branch's
//  identity, and an `if` without an `else` kept all of it (found by lane
//  MODALS's probe, 2026-10-19).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUITestSupport

@MainActor
private final class Shown {
    var isShown = true
}

/// A button that counts its presses in its own `@State`.
private struct Counter: View {
    @State private var count = 0
    var body: some View {
        Button("count \(count)") { count += 1 }
    }
}

/// An `if` drawn as a view's body: the `if` hands its view its own identity.
private struct BodyIf: View {
    let shown: Shown
    var body: some View {
        if shown.isShown { Counter() }
    }
}

/// An `if`/`else` drawn as a view's body: the conditional draws its arm
/// itself, under the arm's own identity.
private struct BodyIfElse: View {
    let shown: Shown
    var body: some View {
        if shown.isShown { Counter() } else { Text("other") }
    }
}

@MainActor
@Suite("A view an `if` removes loses its @State, under a container that keeps its subtree's")
struct ConditionalStateUnderRetentionTests {
    private func screen(_ harness: InputChainHarness, _ view: some View) -> String {
        harness.frame(view).lines.map(\.stripped).joined(separator: "\n")
    }

    /// Presses the counter, hides it for two frames, shows it again, and
    /// returns what it reads then.
    private func pressHideShow(_ shown: Shown, _ build: @escaping () -> some View) -> (pressed: String, again: String) {
        let harness = InputChainHarness(width: 40, height: 10)
        harness.play([.init(key: .enter)], build)
        let pressed = screen(harness, build())
        shown.isShown = false
        harness.frame(build())
        harness.frame(build())
        shown.isShown = true
        harness.frame(build())
        return (pressed, screen(harness, build()))
    }

    /// Rows after the `if`, so the stack windows.
    private static func filler() -> some View {
        ForEach(0..<40, id: \.self) { Text("filler \($0)") }
    }

    @Test("An `if` without an `else` in a lazy stack")
    func optionalInLazyStack() {
        let shown = Shown()
        let result = pressHideShow(shown) {
            ScrollView { LazyVStack { if shown.isShown { Counter() }; Self.filler() } }
        }
        #expect(result.pressed.contains("count 1"), "the press counted: \(result.pressed)")
        #expect(result.again.contains("count 0"), "back afresh: \(result.again)")
    }

    @Test("An `if`/`else` in a lazy stack")
    func conditionalInLazyStack() {
        let shown = Shown()
        let result = pressHideShow(shown) {
            ScrollView { LazyVStack { if shown.isShown { Counter() } else { Text("other") }; Self.filler() } }
        }
        #expect(result.pressed.contains("count 1"), "the press counted: \(result.pressed)")
        #expect(result.again.contains("count 0"), "back afresh: \(result.again)")
    }

    @Test("An `if` whose view has a transition of its own, in a lazy stack")
    func transitioningInLazyStack() {
        let shown = Shown()
        let result = pressHideShow(shown) {
            ScrollView { LazyVStack { if shown.isShown { Counter().transition(.opacity) }; Self.filler() } }
        }
        #expect(result.pressed.contains("count 1"), "the press counted: \(result.pressed)")
        #expect(result.again.contains("count 0"), "back afresh: \(result.again)")
    }

    @Test("An `if` drawn as a view's body, at its own identity, in a lazy stack")
    func bodyIfInLazyStack() {
        let shown = Shown()
        let result = pressHideShow(shown) {
            ScrollView { LazyVStack { BodyIf(shown: shown); Self.filler() } }
        }
        #expect(result.pressed.contains("count 1"), "the press counted: \(result.pressed)")
        #expect(result.again.contains("count 0"), "back afresh: \(result.again)")
    }

    @Test("An `if`/`else` drawn as a view's body, in a lazy stack")
    func bodyIfElseInLazyStack() {
        let shown = Shown()
        let result = pressHideShow(shown) {
            ScrollView { LazyVStack { BodyIfElse(shown: shown); Self.filler() } }
        }
        #expect(result.pressed.contains("count 1"), "the press counted: \(result.pressed)")
        #expect(result.again.contains("count 0"), "back afresh: \(result.again)")
    }

    @Test("Inside keepsStateWhileHidden() the view keeps its state, as it asks")
    func keptWhileHidden() {
        let shown = Shown()
        let result = pressHideShow(shown) {
            ScrollView { LazyVStack { if shown.isShown { Counter() }; Self.filler() }.keepsStateWhileHidden() }
        }
        #expect(result.pressed.contains("count 1"), "the press counted: \(result.pressed)")
        #expect(result.again.contains("count 1"), "kept: \(result.again)")
    }
}
