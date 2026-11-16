//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppAnimationOutsideEventTests.swift
//
//  A test's own `withAnimation`, made in its body rather than in an event the
//  app handles, animates as one made in an event does: SwiftUI animates a
//  change made under a transaction wherever the change is made.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUITesting

/// What the page reads, written by the test.
@Observable
@MainActor
private final class Model {
    var showing = false
    var isAcross = false
}

/// A row that arrives, and a glyph that moves.
private struct ArrivingPage: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "row")
            if model.showing { Text(verbatim: "more") }
            Text(verbatim: "@").padding(.leading, model.isAcross ? 10 : 0)
        }
    }
}

@MainActor
@Suite("A test's withAnimation animates as an event's does")
struct TestAppAnimationOutsideEventTests {
    @Test("Content that arrives under a test's withAnimation is drawn once it has arrived")
    func arrivingContentDraws() {
        let model = Model()
        let app = TestApp(width: 20, height: 5) { ArrivingPage(model: model) }
        #expect(!app.screen.contains("more"))
        withAnimation(.linear(duration: 0.5)) { model.showing = true }
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("more"), "\(app.screen.text)")
    }

    @Test("A value changed under a test's withAnimation moves over the animation's time")
    func changedValueAnimates() {
        let model = Model()
        let app = TestApp(width: 20, height: 5) { ArrivingPage(model: model) }
        #expect(app.screen.location(of: "@")?.x == 0)
        // Straight on, with nothing read or drawn between: the change's frame
        // is the one the clock starts the animation at.
        withAnimation(.linear(duration: 1)) { model.isAcross = true }
        app.advance(by: .milliseconds(500))
        let halfWay = app.screen.location(of: "@")?.x ?? 0
        #expect(halfWay > 2 && halfWay < 8, "\(app.screen.text)")
        app.advance(by: .milliseconds(500))
        #expect(app.screen.location(of: "@")?.x == 10, "\(app.screen.text)")
    }
}
