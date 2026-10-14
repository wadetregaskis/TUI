//  🖥️ TUIkit — Terminal UI Kit for Swift
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

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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

    @Test("An if's view fades in and out of a stack, holding its row while it leaves")
    func stackedFades() {
        let screen = Screen()
        _ = screen.draw(Stacked(showing: false), atMillis: 0, animated: false)
        let arriving = screen.draw(Stacked(showing: true), atMillis: 10, animated: true)
        #expect(arriving.lines.map(\.stripped) == ["XXXX", "----"])
        #expect(fades(arriving) == [0], "it arrives from nothing")
        #expect(fades(screen.draw(Stacked(showing: true), atMillis: 510, animated: false)) == [0.5])
        #expect(fades(screen.draw(Stacked(showing: true), atMillis: 1100, animated: false)).isEmpty, "arrived")

        _ = screen.draw(Stacked(showing: false), atMillis: 1200, animated: true)
        let leaving = screen.draw(Stacked(showing: false), atMillis: 1700, animated: false)
        #expect(leaving.lines.map(\.stripped) == ["XXXX", "----"], "its row is held while it leaves")
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
