//  🖥️ TUI — A Terminal UI framework for Swift
//  TupleDrawnWholeStateTests.swift
//
//  A view after an `if` in a tuple drawn whole keeps its state when the `if`
//  flips (VIEWS-11, H-08).
//
//  A tuple drawn whole — an `AnyView` of a view of the app's own whose body is
//  several views — numbered a plain child by how many children came before it
//  flattened, so an `if` that adds two views moved the view after it from
//  index 2 to 3: a new identity, its `@State` and focus id gone. SwiftUI keeps
//  it (measured on macOS 15.8.3, `Tools/SwiftUIProbes/AnyView type swap (H-08)/anyview.out`,
//  the tuple steps).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// Flips the `if` from outside, between frames.
@MainActor
private final class Flip {
    var shows: Binding<Bool>?
}

private struct Counter: View {
    let name: String
    @State private var count = 0

    var body: some View {
        Button("\(name) \(count)") { count += 1 }
    }
}

/// A text, an `if` of two views, then a counter.
private struct Flipping: View {
    let shows: Bool

    var body: some View {
        Text("a")
        if shows {
            Text("x")
            Text("y")
        }
        Counter(name: "C")
    }
}

/// The view above drawn whole, behind an `AnyView`.
private struct Host: View {
    @State private var shows = false
    let flip: Flip

    var body: some View {
        flip.shows = $shows
        return AnyView(Flipping(shows: shows))
    }
}

@MainActor
@Suite("A tuple drawn whole numbers its views by their place in it")
struct TupleDrawnWholeStateTests {
    @Test("A view after an if keeps its state when the if flips")
    func viewAfterAnIfKeepsItsState() throws {
        let flip = Flip()
        let app = TestApp(width: 30, height: 8) { Host(flip: flip) }
        try app.click("C 0")
        #expect(app.screen.contains("C 1"), "precondition: \(app.screen)")
        flip.shows?.wrappedValue = true
        #expect(app.screen.contains("x"), "precondition: \(app.screen)")
        #expect(app.screen.contains("C 1"), "the counter was reset: \(app.screen)")
        flip.shows?.wrappedValue = false
        #expect(app.screen.contains("C 1"), "the counter was reset: \(app.screen)")
    }
}
