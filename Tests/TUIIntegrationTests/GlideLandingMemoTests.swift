//  🖥️ TUI — A Terminal UI framework for Swift
//  GlideLandingMemoTests.swift
//
//  The frame a glide lands on is not one a memo keeps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A card memoized by its value, whose last row glides as its detail comes.
private struct LandingCard: View, @MainActor Equatable {
    let open: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.open == rhs.open }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "card")
            if open { Text(verbatim: "detail") }
            Text(verbatim: "END")
        }
    }
}

private struct LandingPage: View {
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") { withAnimation(.linear(duration: 0.1)) { open.toggle() } }
            LandingCard(open: open).equatable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LandingApp: App {
    var body: some Scene {
        WindowGroup { LandingPage() }
    }
}

@MainActor
@Suite("The frame a glide lands on is not one a memo keeps")
struct GlideLandingMemoTests {
    /// Its render asked the store about what had just landed, as no render
    /// after it does, so a memo stored from it declared those records again on
    /// every hit (`AnimationStore.declareAgain(_:)`). Kept past a layout change
    /// nothing animates, such a record says the child is where it was, and the
    /// next animated change back there does not move it: `session/glides` drew
    /// a card's row in a different place from its cache-cleared twin, once
    /// updates between frames moved which frame a glide landed on. Before that,
    /// the next frame happened to be an animated change's, which served nothing.
    @Test("What a memo serves after a glide lands registers what a fresh render does")
    func servedAfterLanding() {
        let was = RenderCache.verifiesRenderMemo
        defer { RenderCache.verifiesRenderMemo = was }
        RenderCache.verifiesRenderMemo = true
        let app = HeadlessApp(LandingApp(), width: 40, height: 8)
        var tick: Int64 = 0
        func step(_ frames: Int) {
            for _ in 0..<frames {
                app.frame(atNanos: AnimationClock.nanoseconds(atTick: tick))
                tick += 1
            }
        }
        step(2)
        #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        step(20)
        #expect(app.renderCache.renderMemoMismatches.isEmpty, "\(app.renderCache.renderMemoMismatches)")
    }
}
