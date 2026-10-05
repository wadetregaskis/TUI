//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReduceMotionTests.swift
//
//  `\.accessibilityReduceMotion`: where it comes from — the user's
//  `TUIKIT_REDUCE_MOTION`, the app's `Scene.reduceMotion(_:)` — and what follows
//  it: a transition with motion plays as a fade.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A view that comes and goes, in a slot that survives it — two cells of
/// content in a slot six wide, so a picture moved inside the slot shows.
private struct Host: View {
    let showing: Bool
    let transition: AnyTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showing {
                Text("XX").frame(width: 6, alignment: .leading).transition(transition)
            }
            Text("------")
        }
    }
}

/// A transition of the app's own that indents its view four cells away from
/// rest — motion, by the default properties.
private struct Indent: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.padding(.leading, phase.isIdentity ? 0 : 4)
    }
}

/// The same, saying it has no motion.
private struct StillIndent: Transition {
    static let properties = TransitionProperties(hasMotion: false)

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.padding(.leading, phase.isIdentity ? 0 : 4)
    }
}

@MainActor
@Suite("Reduce motion")
struct ReduceMotionTests {

    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 8, height: 6)

        init(reducesMotion: Bool) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: .linear(duration: 1))
            context.environment.accessibilityReduceMotion = reducesMotion
        }

        func draw(_ showing: Bool, _ transition: AnyTransition, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(
                Host(showing: showing, transition: transition), context: context
            ).lines.map(\.stripped)
        }

        /// The first row halfway through an arrival under `transition`.
        func halfway(_ transition: AnyTransition) -> String {
            _ = draw(false, transition, atMillis: 0)
            _ = draw(true, transition, atMillis: 0)
            return draw(true, transition, atMillis: 500)[0]
        }
    }

    @Test("A transition with motion plays as a fade where motion is reduced")
    func motionBecomesAFade() {
        #expect(!Screen(reducesMotion: false).halfway(.move(edge: .trailing)).hasPrefix("XX"), "it moves")
        // A fade draws the view where it rests, in a colour part-way there.
        #expect(Screen(reducesMotion: true).halfway(.move(edge: .trailing)).hasPrefix("XX"))
        #expect(!Screen(reducesMotion: false).halfway(.scale(scale: 0, anchor: .trailing)).hasPrefix("XX"))
        #expect(Screen(reducesMotion: true).halfway(.scale(scale: 0, anchor: .trailing)).hasPrefix("XX"))
    }

    @Test("A transition of the app's own follows what its properties say")
    func customTransitionsFollowTheirProperties() {
        #expect(Screen(reducesMotion: false).halfway(AnyTransition(Indent())).hasPrefix(" "), "it moves")
        #expect(Screen(reducesMotion: true).halfway(AnyTransition(Indent())).hasPrefix("XX"), "a fade instead")
        #expect(Screen(reducesMotion: true).halfway(AnyTransition(StillIndent())).hasPrefix(" "), "no motion, kept")
    }

    @Test("Motion is the move, offset and scale effects, at either end, or a body that says so")
    func whatHasMotion() {
        #expect(!AnyTransition.opacity.hasMotion)
        #expect(!AnyTransition.identity.hasMotion)
        #expect(AnyTransition.move(edge: .top).hasMotion)
        #expect(AnyTransition.offset(x: 1, y: 0).hasMotion)
        #expect(AnyTransition.opacity.combined(with: .slide).hasMotion)
        #expect(AnyTransition.asymmetric(insertion: .opacity, removal: .move(edge: .top)).hasMotion)
        #expect(AnyTransition(Indent()).hasMotion)
        #expect(!AnyTransition(StillIndent()).hasMotion)
        #expect(AnyTransition(StillIndent()).combined(with: .move(edge: .top)).hasMotion)
    }

    @Test("The fade keeps the transition's own animation")
    func fadeKeepsTheAnimation() {
        var environment = EnvironmentValues()
        environment.accessibilityReduceMotion = true
        let slow = AnyTransition.move(edge: .top).animation(.linear(duration: 3))
        let reduced = slow.reducingMotion(in: environment)
        #expect(!reduced.hasMotion)
        #expect(reduced.explicitAnimation == slow.explicitAnimation)
    }

    @Test("The user asks with TUIKIT_REDUCE_MOTION=1, and nothing else asks")
    func environmentVariable() {
        #expect(TerminalClient.reduceMotionRequested(environment: ["TUIKIT_REDUCE_MOTION": "1"]))
        #expect(!TerminalClient.reduceMotionRequested(environment: ["TUIKIT_REDUCE_MOTION": "0"]))
        #expect(!TerminalClient.reduceMotionRequested(environment: [:]))
    }

    @Test("The app's scene turns it on, and never off")
    func sceneSetting() {
        func root(_ scene: some Scene, userAsked: Bool) -> Bool {
            var environment = EnvironmentValues()
            environment.accessibilityReduceMotion = userAsked
            scene.applyingRootEnvironment(to: &environment)
            return environment.accessibilityReduceMotion
        }
        #expect(root(WindowGroup { Text("app") }.reduceMotion(), userAsked: false))
        #expect(!root(WindowGroup { Text("app") }.reduceMotion(false), userAsked: false))
        #expect(root(WindowGroup { Text("app") }.reduceMotion(false), userAsked: true), "the user's ask stands")
        #expect(!root(WindowGroup { Text("app") }, userAsked: false))
    }
}
