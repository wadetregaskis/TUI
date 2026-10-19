//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionAnimationTests.swift
//
//  Which animation a transition runs under: each half of an `asymmetric`
//  transition its own, the one nearest the view where several are written,
//  and none at all where it says `nil` — measured on SwiftUI,
//  `Tools/SwiftUIProbes/Transitions/tr1.out` and `tr2.out`. Moved out of
//  `TransitionTests.swift`, which had passed the file-length guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A transition's own animations")
struct TransitionAnimationTests {

    /// SwiftUI keeps each half's animation (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr1.out` T4: two seconds in and eight
    /// out under a change of four). One animation for both, the insertion's,
    /// had this removal over in a second. The row stays above the view, so
    /// nothing glides over it.
    @Test("Each half of an asymmetric transition keeps its own animation")
    func asymmetricHalvesKeepTheirAnimations() {
        let halves = AnyTransition.asymmetric(
            insertion: .move(edge: .leading).animation(.linear(duration: 1)),
            removal: .move(edge: .trailing).animation(.linear(duration: 4)))
        let screen = RemovalScreen(animation: .linear(duration: 2)) { showing in
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { Text("XXXX").transition(halves) }
            }
        }
        _ = screen.draw(false, atMillis: 0)
        _ = screen.draw(true, atMillis: 0)
        #expect(screen.draw(true, atMillis: 500) == ["----", "XX  "], "half-way in after half its own second")
        #expect(screen.draw(true, atMillis: 1000) == ["----", "XXXX"])
        _ = screen.draw(false, atMillis: 1000)
        #expect(screen.draw(false, atMillis: 2000) == ["----", " XXX"], "a quarter out after one of its four")
        #expect(screen.draw(false, atMillis: 4000) == ["----", "   X"])
        #expect(screen.draw(false, atMillis: 5100) == ["----"])
    }

    /// SwiftUI plays a transition whose animation is `nil` at once under
    /// `withAnimation`, both ways, and a half whose animation is `nil` at once
    /// while the other runs under the change (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr1.out` T5, `tr2.out` T13): `nil`
    /// said is not `nil` unsaid. Stored as the same `nil`, it ran under the
    /// change.
    @Test("A transition whose animation is nil comes and goes at once under an animated change")
    func nilAnimationIsInstant() {
        let instant = AnyTransition.move(edge: .leading).animation(nil)
        let screen = RemovalScreen(animation: .linear(duration: 1)) { showing in
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { Text("XXXX").transition(instant) }
            }
        }
        _ = screen.draw(false, atMillis: 0)
        #expect(screen.draw(true, atMillis: 0) == ["----", "XXXX"], "in at once")
        _ = screen.draw(true, atMillis: 100)
        #expect(screen.draw(false, atMillis: 100) == ["----"], "and out at once")

        let leavesAtOnce = AnyTransition.asymmetric(insertion: .move(edge: .leading), removal: .opacity.animation(nil))
        let halves = RemovalScreen(animation: .linear(duration: 1)) { showing in
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { Text("XXXX").transition(leavesAtOnce) }
            }
        }
        _ = halves.draw(false, atMillis: 0)
        _ = halves.draw(true, atMillis: 0)
        #expect(halves.draw(true, atMillis: 500) == ["----", "XX  "], "in under the change")
        _ = halves.draw(true, atMillis: 1100)
        #expect(halves.draw(false, atMillis: 1100) == ["----"], "out at once")
    }

    @Test("Nil is kept as an animation nearer the view than one written outside it")
    func nilIsNearest() {
        let nilThen = AnyTransition.opacity.animation(nil).animation(.linear(duration: 8))
        #expect(nilThen.insertionAnimation == .some(nil))
        let thenNil = AnyTransition.opacity.animation(.linear(duration: 8)).animation(nil)
        #expect(thenNil.insertionAnimation == .some(.linear(duration: 8)))
        #expect(AnyTransition.opacity.insertionAnimation == nil, "nothing named")
    }

    /// The animation nearest the view wins, as in SwiftUI (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr2.out` T9, T10).
    @Test("An animation written outside a transition leaves the halves that have their own alone")
    func innerAnimationWins() {
        let twice = AnyTransition.opacity.animation(.linear(duration: 2)).animation(.linear(duration: 8))
        #expect(twice.insertionAnimation == .linear(duration: 2))
        #expect(twice.removalAnimation == .linear(duration: 2))
        let outer = AnyTransition.asymmetric(insertion: .opacity.animation(.linear(duration: 2)), removal: .opacity)
            .animation(.linear(duration: 8))
        #expect(outer.insertionAnimation == .linear(duration: 2))
        #expect(outer.removalAnimation == .linear(duration: 8))
        let combined = AnyTransition.opacity.combined(with: AnyTransition.scale.animation(.linear(duration: 3)))
        #expect(combined.insertionAnimation == .linear(duration: 3), "a part with none takes the other's")
    }
}
