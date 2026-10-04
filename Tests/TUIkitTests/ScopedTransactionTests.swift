//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScopedTransactionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// What was seen where.
@MainActor
private final class Seen {
    var content: [Animation?] = []
    var identities: [ViewIdentity] = []
    var modifier: [Animation?] = []
    var values: [Double] = []
}

/// The view a scoped transaction wraps: records the animation it renders under
/// and where.
private struct Wrapped: View, Renderable {
    let seen: Seen
    var body: Never { fatalError("Wrapped renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            seen.content.append(context.environment.transaction.animation)
            seen.identities.append(context.identity)
        }
        return FrameBuffer(lines: ["X"])
    }
}

/// A modifier in the scope: records the animation it renders under.
private struct Probe: BufferModifier {
    let seen: Seen

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        seen.modifier.append(context.environment.transaction.animation)
        return buffer
    }
}

/// An animatable modifier that reports the values it is drawn at.
private struct Report: BufferModifier, Animatable {
    var animatableData: Double
    let seen: Seen

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        seen.values.append(animatableData)
        return buffer
    }
}

/// A view that is its own value, for `animation(_:)`.
private struct Level: View, Equatable {
    let level: Double
    let seen: Seen

    var body: some View {
        Text("x").modifier(Report(animatableData: level, seen: seen))
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.level == rhs.level }
}

/// A `ViewModifier` of an app's own with an animatable value inside it.
private struct Reporting: ViewModifier {
    let level: Double
    let seen: Seen

    func body(content: Content) -> some View {
        content.modifier(Report(animatableData: level, seen: seen))
    }
}

@MainActor
private final class Frames {
    var context = makeRenderContext(width: 10, height: 2)

    init(_ animation: Animation? = nil) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    func draw<V: View>(_ view: V, atMillis millis: Int) {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        _ = renderToBuffer(view, context: context)
    }
}

@MainActor
@Suite("Transactions scoped to the modifiers in a closure")
struct ScopedTransactionTests {

    @Test("The modifiers in the body render under the transform; the view they wrap does not")
    func transformReachesOnlyTheBody() {
        let seen = Seen()
        let frames = Frames(.easeIn(duration: 1))
        frames.draw(
            Wrapped(seen: seen).transaction(
                { $0.animation = .linear(duration: 2) }, body: { $0.modifier(Probe(seen: seen)) }),
            atMillis: 0)
        #expect(seen.modifier == [.linear(duration: 2)])
        #expect(seen.content == [.easeIn(duration: 1)])
    }

    @Test("The wrapped view is drawn where it would be with the modifiers written on it")
    func wrappedViewKeepsItsIdentity() {
        let direct = Seen()
        Frames().draw(Wrapped(seen: direct).modifier(Probe(seen: direct)), atMillis: 0)
        let scoped = Seen()
        Frames().draw(
            Wrapped(seen: scoped).transaction({ _ in }, body: { $0.modifier(Probe(seen: scoped)) }),
            atMillis: 0)
        #expect(scoped.identities == direct.identities)
    }

    @Test("animation(_:body:) animates the body's values with no withAnimation around the change")
    func animationBodyAnimates() {
        let seen = Seen()
        let frames = Frames()
        func view(_ level: Double) -> some View {
            Wrapped(seen: seen).animation(.linear(duration: 1)) {
                $0.modifier(Report(animatableData: level, seen: seen))
            }
        }
        frames.draw(view(0), atMillis: 0)
        frames.draw(view(10), atMillis: 0)
        seen.values = []
        frames.draw(view(10), atMillis: 500)
        #expect(seen.values == [5])
        #expect(seen.content.allSatisfy { $0 == nil }, "the wrapped view keeps the transaction it had")
    }

    @Test("animation(_:body:) leaves a subtree that opted out of animating alone")
    func animationBodyRespectsDisablesAnimations() {
        let seen = Seen()
        let frames = Frames()
        func view(_ level: Double) -> some View {
            Wrapped(seen: seen)
                .animation(.linear(duration: 1)) { $0.modifier(Report(animatableData: level, seen: seen)) }
                .transaction { $0.disablesAnimations = true }
        }
        frames.draw(view(0), atMillis: 0)
        frames.draw(view(10), atMillis: 0)
        seen.values = []
        frames.draw(view(10), atMillis: 500)
        #expect(seen.values == [10])
    }

    @Test("An Equatable view's animation(_:) animates the change of its own value")
    func equatableViewAnimation() {
        let seen = Seen()
        let frames = Frames()
        frames.draw(Level(level: 0, seen: seen).animation(.linear(duration: 1)), atMillis: 0)
        frames.draw(Level(level: 10, seen: seen).animation(.linear(duration: 1)), atMillis: 0)
        seen.values = []
        frames.draw(Level(level: 10, seen: seen).animation(.linear(duration: 1)), atMillis: 250)
        #expect(seen.values == [2.5])
    }

    @Test("A ViewModifier's animation(_:) animates the values inside it, not the view it wraps")
    func viewModifierAnimation() {
        let seen = Seen()
        let frames = Frames()
        func view(_ level: Double) -> some View {
            Wrapped(seen: seen).modifier(Reporting(level: level, seen: seen).animation(.linear(duration: 1)))
        }
        frames.draw(view(0), atMillis: 0)
        frames.draw(view(10), atMillis: 0)
        seen.values = []
        frames.draw(view(10), atMillis: 500)
        #expect(seen.values == [5])
        #expect(seen.content.allSatisfy { $0 == nil })
    }

    @Test("A ViewModifier's transaction(_:) transforms the transaction inside it")
    func viewModifierTransaction() {
        struct Probing: ViewModifier {
            let seen: Seen
            func body(content: Content) -> some View { content.modifier(Probe(seen: seen)) }
        }
        let seen = Seen()
        Frames(.easeIn(duration: 1)).draw(
            Wrapped(seen: seen).modifier(Probing(seen: seen).transaction { $0.animation = nil }),
            atMillis: 0)
        #expect(seen.modifier == [nil])
        #expect(seen.content == [.easeIn(duration: 1)])
    }
}
