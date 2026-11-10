//  🖥️ TUI — A Terminal UI framework for Swift
//  RepeatedAnimationEndTests.swift
//
//  An animation repeated an even number of times with `autoreverses` plays
//  out and back, and then the view shows the value the change set, as
//  SwiftUI's does: measured, `delay(0.3).repeatCount(2, autoreverses: true)`
//  comes back to 0.10 and the next sample is 1.00, where it stays
//  (`Tools/SwiftUIProbes/Animation curves, springs and keyframes/p11.out`).
//  TUI's view stayed where the last pass ended, at the value before the
//  change, for good.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

private struct Mover: View {
    let animation: Animation
    @State private var moved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Go") { withAnimation(animation) { moved.toggle() } }
            Text("#").offset(x: moved ? 10 : 0)
        }
    }
}

private struct Arrival: View {
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Go") {
                withAnimation(.linear(duration: 1).repeatCount(2, autoreverses: true)) { shown.toggle() }
            }
            if shown { Text("XXXXXX").transition(.move(edge: .leading)) }
        }
    }
}

@MainActor
@Suite("An animation repeated out and back")
struct RepeatedAnimationEndTests {
    /// The column the marker is drawn at.
    private func column(_ app: TestApp) -> Int? {
        app.screen.location(of: "#")?.x
    }

    @Test("An even count of autoreversing passes plays out and back, then shows the value the change set")
    func evenCountEndsAtTheTarget() {
        let app = TestApp(width: 20, height: 3) {
            Mover(animation: .linear(duration: 1).repeatCount(2, autoreverses: true))
        }
        app.press(.enter)
        app.advance(by: .milliseconds(500))
        #expect(column(app) == 5)
        app.advance(by: .milliseconds(500))
        #expect(column(app) == 10)
        app.advance(by: .milliseconds(500))
        #expect(column(app) == 5, "the second pass runs back")
        app.advance(by: .seconds(1))
        #expect(column(app) == 10, "over, it shows where the change put it")
        app.advance(by: .seconds(60))
        #expect(column(app) == 10)
    }

    @Test("An odd count ends at the target as it always did")
    func oddCountEndsAtTheTarget() {
        let app = TestApp(width: 20, height: 3) {
            Mover(animation: .linear(duration: 1).repeatCount(3, autoreverses: true))
        }
        app.press(.enter)
        app.advance(by: .seconds(4))
        #expect(column(app) == 10)
    }

    @Test("A view inserted under an even count of autoreversing passes is there once they are over")
    func evenCountArrivalEndsPresent() {
        let app = TestApp(width: 20, height: 3) { Arrival() }
        app.press(.enter)
        app.advance(by: .seconds(3))
        #expect(app.screen.lines[1] == "XXXXXX")
    }

    @Test("A change after an even count animates from where the view is shown")
    func nextChangeStartsFromTheTarget() {
        let app = TestApp(width: 20, height: 3) {
            Mover(animation: .linear(duration: 1).repeatCount(2, autoreverses: true))
        }
        app.press(.enter)
        app.advance(by: .seconds(3))
        app.press(.enter)
        app.advance(by: .milliseconds(500))
        #expect(column(app) == 5, "heading back from 10, half way")
    }
}
