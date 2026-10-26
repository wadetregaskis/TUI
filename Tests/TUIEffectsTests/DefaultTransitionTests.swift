//  🖥️ TUI — A Terminal UI framework for Swift
//  DefaultTransitionTests.swift
//
//  A view an `if` puts in or takes out under an animated change fades, as
//  SwiftUI's does with no `.transition` written: the default transition is
//  `.opacity`. The fade is the opacity claim the frame carries, so these read
//  the claim's strength rather than the drawn cells.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport

/// An `if` inside a stack, above a row that stays.
private struct Stacked: View {
    let showing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showing { Text("XXXX") }
            Text("----")
        }
    }
}

/// An `if` that is the whole body: the optional is rendered directly.
private struct Direct: View {
    let showing: Bool

    var body: some View {
        if showing { Text("XXXX") }
    }
}

/// An `if` inside an `if`, the inner one already true when the outer arrives.
private struct Nested: View {
    let outer: Bool

    var body: some View {
        VStack(spacing: 0) {
            if outer {
                VStack(spacing: 0) {
                    if true { Text("XXXX") }
                }
            }
            Text("----")
        }
    }
}

/// A view with a transition of its own, which the default stands aside for.
private struct Explicit: View {
    let showing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showing { Text("XXXX").transition(.move(edge: .leading)) }
            Text("----")
        }
    }
}

/// How many `Stamped` views have been made: a `@State` box kept from an
/// earlier frame shows the number it was made with, a new one the latest.
@MainActor
private enum Made {
    static var count = 0

    static func next() -> Int {
        count += 1
        return count
    }
}

/// An `if` whose view draws displaced, past its slot, beside a row that
/// stays: with no transition, and with `.opacity` written outside the offset.
private struct Displaced: View {
    let showing: Bool
    var transition: AnyTransition?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            if showing {
                if let transition {
                    Text("XX").offset(x: 3).transition(transition)
                } else {
                    Text("XX").offset(x: 3)
                }
            }
        }
    }
}

/// The strengths of the fades a frame carries, its layers' included.
private func allFades(_ buffer: FrameBuffer) -> [Double] {
    fades(buffer) + buffer.overlays.flatMap { allFades($0.content) }
}

/// A view whose `@State` says when its box was made.
private struct Stamped: View {
    @State private var made = Made.next()

    var body: some View {
        Text("\(made)")
    }
}

/// An `if` that is the whole body, holding a view with `@State`.
private struct DirectStamped: View {
    let showing: Bool

    var body: some View {
        if showing { Stamped() }
    }
}

@MainActor
private final class Screen {
    var context = makeRenderContext(width: 8, height: 4)

    init() {
        context.environment.canAnimate = true
    }

    /// One frame at `millis`, under a one-second linear change when `animated`.
    func draw(_ view: some View, atMillis millis: Int, animated: Bool) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        context.environment.transaction = Transaction(animation: animated ? .linear(duration: 1) : nil)
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }
}

/// The strengths of the fades a frame carries.
private func fades(_ buffer: FrameBuffer) -> [Double] {
    buffer.opacityRegions.map { ($0.opacity * 100).rounded() / 100 }
}

@MainActor
@Suite("The default transition")
struct DefaultTransitionTests {

    /// SwiftUI's model, measured (`Tools/SwiftUIProbes/Insertion and removal (FB16)/samples.txt`): the row below
    /// glides as the view comes and goes, and the view fades where it is —
    /// arriving in its new row with the row below not yet moved out of it,
    /// leaving in its old row with the row below gliding up into it. What is
    /// drawn past the stack, which has closed up at once, is drawn in.
    @Test("An if's view fades in and out of a stack while the row below glides")
    func stackedFades() {
        let screen = Screen()
        _ = screen.draw(Stacked(showing: false), atMillis: 0, animated: false)
        let arriving = screen.draw(Stacked(showing: true), atMillis: 10, animated: true).withLayersDrawn()
        #expect(arriving.lines.map(\.stripped) == ["----", "    "], "the row below has not moved yet")
        #expect(fades(arriving).allSatisfy { $0 == 0 }, "it arrives from nothing")
        let halfIn = screen.draw(Stacked(showing: true), atMillis: 510, animated: false).withLayersDrawn()
        #expect(halfIn.lines.map(\.stripped) == ["XXXX", "----"])
        #expect(fades(halfIn) == [0.5])
        #expect(fades(screen.draw(Stacked(showing: true), atMillis: 1100, animated: false)).isEmpty, "arrived")

        _ = screen.draw(Stacked(showing: false), atMillis: 1200, animated: true)
        let leaving = screen.draw(Stacked(showing: false), atMillis: 1700, animated: false)
        #expect(leaving.lines.map(\.stripped) == ["XXXX"], "its row has gone from the layout")
        #expect(leaving.withLayersDrawn().lines.map(\.stripped) == ["XXXX", "----"], "the row below is on its way up")
        #expect(fades(leaving) == [0.5])
        #expect(screen.draw(Stacked(showing: false), atMillis: 2300, animated: false).lines.map(\.stripped) == ["----"])
    }

    @Test("An if that is a whole body fades its view in and out")
    func directFades() {
        let screen = Screen()
        _ = screen.draw(Direct(showing: false), atMillis: 0, animated: false)
        _ = screen.draw(Direct(showing: true), atMillis: 10, animated: true)
        #expect(fades(screen.draw(Direct(showing: true), atMillis: 510, animated: false)) == [0.5])
        _ = screen.draw(Direct(showing: true), atMillis: 1100, animated: false)
        _ = screen.draw(Direct(showing: false), atMillis: 1200, animated: true)
        let leaving = screen.draw(Direct(showing: false), atMillis: 1700, animated: false)
        #expect(leaving.lines.map(\.stripped) == ["XXXX"])
        #expect(fades(leaving) == [0.5])
        #expect(screen.draw(Direct(showing: false), atMillis: 2300, animated: false).isEmpty)
    }

    @Test("Without an animation an if's view comes and goes at once")
    func unanimatedIsInstant() {
        let screen = Screen()
        _ = screen.draw(Stacked(showing: false), atMillis: 0, animated: false)
        #expect(fades(screen.draw(Stacked(showing: true), atMillis: 10, animated: false)).isEmpty)
        let gone = screen.draw(Stacked(showing: false), atMillis: 20, animated: false)
        #expect(gone.lines.map(\.stripped) == ["----"])
    }

    @Test("A view seen for the first time is not an arrival, animated or not")
    func firstSightIsNotAnArrival() {
        let screen = Screen()
        #expect(fades(screen.draw(Stacked(showing: true), atMillis: 0, animated: true)).isEmpty)
    }

    @Test("An animated change that leaves an if as it was does not fade its view")
    func unchangedIfDoesNotFade() {
        let screen = Screen()
        _ = screen.draw(Stacked(showing: true), atMillis: 0, animated: false)
        #expect(fades(screen.draw(Stacked(showing: true), atMillis: 10, animated: true)).isEmpty)
    }

    /// SwiftUI transitions the view that was inserted, not each view inside
    /// it: an inner `if` that arrives with its parent is seen for the first
    /// time, so only the outer one fades.
    @Test("Only the outermost arriving if fades, not the ifs inside it")
    func nestedFadesOnce() {
        let screen = Screen()
        _ = screen.draw(Nested(outer: false), atMillis: 0, animated: false)
        _ = screen.draw(Nested(outer: true), atMillis: 10, animated: true)
        #expect(fades(screen.draw(Nested(outer: true), atMillis: 510, animated: false)) == [0.5])
    }

    /// The view an `if` takes out is gone, and so is its `@State`, as in
    /// SwiftUI. An `if` that is a whole body draws its view at its own
    /// address, and it used to mark that address as in use on every frame it
    /// was empty — keeping the view's `@State` for when it came back.
    @Test("A view an if that is a whole body takes out loses its state")
    func directRemovalDropsState() {
        let screen = Screen()
        let first = screen.draw(DirectStamped(showing: true), atMillis: 0, animated: false).lines.map(\.stripped)
        _ = screen.draw(DirectStamped(showing: false), atMillis: 10, animated: false)
        let again = screen.draw(DirectStamped(showing: true), atMillis: 20, animated: false).lines.map(\.stripped)
        #expect(!first.isEmpty)
        #expect(first != again, "the state it had before it went: \(again)")
    }

    /// What a view draws past its slot is its own drawing, displaced, and
    /// fades with it, as SwiftUI's does (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr3.out` T14, T15): the default fade
    /// and `.opacity` reach the layer an `.offset` draws, as `.opacity(_:)`
    /// does. They faded the empty slot and left the layer whole.
    @Test("A view drawn past its slot fades with its if, by default or by .opacity", arguments: [false, true])
    func displacedDrawingFades(explicit: Bool) {
        let screen = Screen()
        let transition: AnyTransition? = explicit ? .opacity : nil
        _ = screen.draw(Displaced(showing: false, transition: transition), atMillis: 0, animated: false)
        _ = screen.draw(Displaced(showing: true, transition: transition), atMillis: 10, animated: true)
        let half = screen.draw(Displaced(showing: true, transition: transition), atMillis: 510, animated: false)
        let layers = half.overlays.flatMap { allFades($0.content) }
        #expect(layers.contains { abs($0 - 0.5) < 0.02 }, "the displaced drawing fades in: \(layers)")
        let arrived = screen.draw(Displaced(showing: true, transition: transition), atMillis: 1100, animated: false)
        #expect(arrived.overlays.flatMap { allFades($0.content) }.allSatisfy { $0 == 1 })
    }

    @Test("A transition of the view's own plays instead of the fade")
    func explicitTransitionWins() {
        let screen = Screen()
        _ = screen.draw(Explicit(showing: false), atMillis: 0, animated: false)
        _ = screen.draw(Explicit(showing: true), atMillis: 10, animated: true)
        let arriving = screen.draw(Explicit(showing: true), atMillis: 510, animated: false)
        #expect(arriving.lines.map(\.stripped).first == "XX  ", "it slides")
        #expect(fades(arriving).isEmpty, "and does not fade as well")
        _ = screen.draw(Explicit(showing: true), atMillis: 1100, animated: false)
        _ = screen.draw(Explicit(showing: false), atMillis: 1200, animated: true)
        let leaving = screen.draw(Explicit(showing: false), atMillis: 1700, animated: false)
        #expect(leaving.lines.map(\.stripped).first == "XX  ", "it slides out to its edge")
        #expect(fades(leaving).isEmpty)
    }
}
