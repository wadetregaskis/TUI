//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonStyleBodyStateTests.swift
//
//  A `ButtonStyle`'s body is drawn at the button's own identity, so the
//  button's own slots there must stay out of the indices a composite's
//  `@State` takes (`StateStorage.StateKey`'s reserved ranges). At `0…3` they
//  were the body's first `@State`: of another type, the two replaced each
//  other's box every frame and the style's state reset; of the same type, a
//  debug build's assertion fired.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// Where a test reaches the style body's state from outside.
@MainActor
private final class StateProbe {
    var count: Binding<Int>?
}

/// A style body with state of its own, the SwiftUI idiom for a style that
/// needs some.
private struct CountingBody: View {
    let configuration: ButtonStyleConfiguration
    let probe: StateProbe
    @State private var count = 0

    var body: some View {
        probe.count = $count
        return HStack(spacing: 0) {
            configuration.label
            Text(verbatim: "#\(count)")
        }
    }
}

private struct CountingStyle: ButtonStyle {
    let probe: StateProbe

    func makeBody(configuration: Configuration) -> some View {
        CountingBody(configuration: configuration, probe: probe)
    }
}

@MainActor
@Suite("A button style's body keeps its own state")
struct ButtonStyleBodyStateTests {
    @Test("A style body's @State is kept from frame to frame, and the button's focus id with it")
    func styleBodyStateIsKept() throws {
        let probe = StateProbe()
        let app = TestApp(width: 30, height: 3) {
            Button("Go") {}.buttonStyle(CountingStyle(probe: probe))
        }
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        let focused = app.focusedID
        #expect(focused?.hasPrefix("button-") == true, "\(String(describing: focused))")
        let binding = try #require(probe.count)
        binding.wrappedValue = 7
        frame()
        frame()
        #expect(app.screen.lines.contains { $0.contains("Go#7") }, "\(app.screen.lines)")
        #expect(app.focusedID == focused)
    }
}
