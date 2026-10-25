//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReduceMotionSpatialTests.swift
//
//  Reduce motion is SPATIAL motion (owner decision A-D3M-1, 2026-10-05): an
//  animated change of where something is drawn or how much room it takes
//  jumps to its end; a colour or an opacity still animates.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// One place in the tree, rendered again as the frame clock advances, with
/// every change animated linearly over a second.
@MainActor
private final class Screen {
    var context = makeRenderContext(width: 30, height: 4)

    init(reducesMotion: Bool) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
        context.environment.accessibilityReduceMotion = reducesMotion
    }

    func render<V: View>(_ view: V, atMillis millis: Int) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }

    func draw<V: View>(_ view: V, atMillis millis: Int) -> [String] {
        render(view, atMillis: millis).lines.map(\.stripped)
    }

    /// `before` drawn and settled, then `after` drawn twice: on the frame its
    /// change lands, and half way through the animation it would start.
    func halfway<V: View>(from before: V, to after: V) -> FrameBuffer {
        _ = render(before, atMillis: 0)
        _ = render(after, atMillis: 0)
        return render(after, atMillis: 500)
    }
}

/// Where the text starts, as a column.
private func indent(_ lines: [String]) -> Int? {
    for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        return line.count - line.drop(while: { $0 == " " }).count
    }
    return nil
}

/// Where `text` is first drawn in `buffer` — in its lines, or in a layer
/// floated over them — as a column, and the opacity its line is drawn at.
private func place(
    of text: String, in buffer: FrameBuffer, x: Int = 0
) -> (x: Int, opacity: Double?)? {
    for (row, line) in buffer.lines.enumerated() {
        let stripped = line.stripped
        if let range = stripped.range(of: text) {
            let opacity = buffer.opacityRegions.first { $0.offsetY <= row && row < $0.offsetY + $0.height }?.opacity
            return (x + stripped.distance(from: stripped.startIndex, to: range.lowerBound), opacity)
        }
    }
    for layer in buffer.overlays {
        if let found = place(of: text, in: layer.content, x: x + layer.offsetX) { return found }
    }
    return nil
}

@MainActor
@Suite("Reduce motion holds geometry still")
struct ReduceMotionSpatialTests {

    @Test("An animated offset jumps to its end where motion is reduced, and slides where it is not")
    func offsetJumps() {
        func column(reducesMotion: Bool) -> Int? {
            Screen(reducesMotion: reducesMotion)
                .halfway(from: Text("ab").offset(x: 0), to: Text("ab").offset(x: 20))
                .overlays.first?.offsetX
        }
        #expect(column(reducesMotion: false) == 10, "it slides")
        #expect(column(reducesMotion: true) == 20)
    }

    @Test("An animated position jumps to its end where motion is reduced")
    func positionJumps() {
        // Floated, as an offset is: the place to read is the layer's.
        func row(reducesMotion: Bool) -> Int? {
            Screen(reducesMotion: reducesMotion)
                .halfway(from: Text("ab").position(x: 4, y: 0), to: Text("ab").position(x: 4, y: 2))
                .overlays.first?.offsetY
        }
        #expect(row(reducesMotion: false) == 1, "it glides")
        #expect(row(reducesMotion: true) == 2)
    }

    @Test("An animated padding or fixed frame jumps to its end where motion is reduced")
    func layoutJumps() {
        let moving = Screen(reducesMotion: false)
            .halfway(from: Text("ab").padding(.leading, 0), to: Text("ab").padding(.leading, 8))
        #expect(indent(moving.lines.map(\.stripped)) == 4, "it opens")
        let still = Screen(reducesMotion: true)
            .halfway(from: Text("ab").padding(.leading, 0), to: Text("ab").padding(.leading, 8))
        #expect(indent(still.lines.map(\.stripped)) == 8)

        let growing = Screen(reducesMotion: false)
            .halfway(from: Text("ab").frame(width: 4), to: Text("ab").frame(width: 24))
        #expect(growing.lines[0].stripped.count == 14, "it grows")
        let grown = Screen(reducesMotion: true)
            .halfway(from: Text("ab").frame(width: 4), to: Text("ab").frame(width: 24))
        #expect(grown.lines[0].stripped.count == 24)
    }

    @Test("An animated opacity is not motion, and still animates where motion is reduced")
    func opacityStillAnimates() {
        let still = Screen(reducesMotion: false).render(Text("ab").opacity(0.5), atMillis: 0)
        let reduced = Screen(reducesMotion: true)
            .halfway(from: Text("ab").opacity(1), to: Text("ab").opacity(0))
        #expect(reduced.opacityRegions == still.opacityRegions)
        #expect(reduced.opacityRegions != Screen(reducesMotion: true).render(Text("ab").opacity(0), atMillis: 0).opacityRegions)
    }

    @Test("A visual effect's offset jumps where motion is reduced, while its opacity animates")
    func visualEffectHoldsOnlyItsOffset() {
        func view(_ x: Int, _ opacity: Double) -> some View {
            Text("ab").visualEffect { content, _ in content.offset(x: x).opacity(opacity) }
        }
        let reduced = Screen(reducesMotion: true).halfway(from: view(0, 1), to: view(20, 0))
        let still = Screen(reducesMotion: true).render(view(20, 0.5), atMillis: 0)
        #expect(reduced.overlays.first?.offsetX == 20, "the offset jumped")
        #expect(reduced.overlays.first?.content.opacityRegions == still.overlays.first?.content.opacityRegions)

        let moving = Screen(reducesMotion: false).halfway(from: view(0, 1), to: view(20, 0))
        #expect(moving.overlays.first?.offsetX == 10, "it slides")
    }

    /// `before` drawn and settled, then `after` drawn under a `withAnimation`
    /// with a completion: whether the completion fired on that frame, and
    /// whether the store still had anything moving half way through.
    private func completion<V: View>(
        reducesMotion: Bool, from before: V, to after: V
    ) -> (firedAtOnce: Bool, liveHalfway: Bool) {
        let screen = Screen(reducesMotion: reducesMotion)
        let storage = screen.context.environment.stateStorage!
        _ = screen.render(before, atMillis: 0)
        var fired = false
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.addAnimationCompletion { fired = true }
        screen.context.environment.transaction = transaction
        storage.beginRenderPass()
        storage.animationCompletions.beginPass(placing: transaction.completions)
        _ = renderToBuffer(after, context: screen.context)
        storage.endRenderPass()
        storage.animationCompletions.endPass(at: 0, animations: storage.animations)
        return (fired, storage.animations.hasLiveAnimations(at: 500_000_000))
    }

    /// Nothing animated, so nothing waits: a `withAnimation` whose only change
    /// is held still completes on the frame it lands on.
    @Test("A completion waiting on nothing but held motion fires on the frame the change lands")
    func completionFiresAtOnce() {
        func completes(reducesMotion: Bool) -> Bool {
            completion(reducesMotion: reducesMotion, from: Text("ab").offset(x: 0), to: Text("ab").offset(x: 20))
                .firedAtOnce
        }
        #expect(!completes(reducesMotion: false), "it waits for the slide")
        #expect(completes(reducesMotion: true))
    }

    /// The review's case: the chain's offset was drawn at its end, but the
    /// store still ran the chain's whole animation, so the completion waited
    /// the full second and the loop drew identical frames for it.
    @Test("A visual effect whose change is its offset alone starts no animation where motion is reduced")
    func visualEffectMotionAloneStartsNothing() {
        func view(_ x: Int) -> some View {
            Text("ab").visualEffect { content, _ in content.offset(x: x).opacity(1) }
        }
        let reduced = completion(reducesMotion: true, from: view(0), to: view(20))
        #expect(reduced.firedAtOnce, "the completion waited on a held offset")
        #expect(!reduced.liveHalfway, "the loop is still drawing frames for it")
        let moving = completion(reducesMotion: false, from: view(0), to: view(20))
        #expect(!moving.firedAtOnce && moving.liveHalfway, "it slides")
    }

    /// Motion alone is judged from where the picture IS: an offset moved while
    /// the opacity is still fading must not cut the fade short.
    @Test("A visual effect's offset moved during an opacity fade jumps, and the fade carries on")
    func visualEffectOffsetDuringAFade() {
        func view(_ x: Int, _ opacity: Double) -> some View {
            Text("ab").visualEffect { content, _ in content.offset(x: x).opacity(opacity) }
        }
        let screen = Screen(reducesMotion: true)
        _ = screen.render(view(0, 1), atMillis: 0)
        _ = screen.render(view(0, 0), atMillis: 0)
        _ = screen.render(view(20, 0), atMillis: 250)
        let drawn = screen.render(view(20, 0), atMillis: 500)
        let faded = Screen(reducesMotion: true).render(view(20, 0), atMillis: 0)
        #expect(drawn.overlays.first?.offsetX == 20, "the offset jumped")
        #expect(
            drawn.overlays.first?.content.opacityRegions != faded.overlays.first?.content.opacityRegions,
            "the fade was cut short")
    }

    /// Geometry's scroll transition animated its effect outside the motion
    /// hold `visualEffect` has: under reduce motion an `.animated` transition
    /// still slid its offset in.
    @Test("A scroll transition's offset jumps where motion is reduced, while its opacity animates")
    func scrollTransitionHoldsOnlyItsOffset() {
        func halfway(reducesMotion: Bool, atMillis millis: Int = 500) -> (x: Int, opacity: Double?)? {
            let screen = Screen(reducesMotion: reducesMotion)
            var position = ScrollPosition()
            let binding = Binding(get: { position }, set: { position = $0 })
            let page = ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<8, id: \.self) { index in
                        Text("row \(index)")
                            .scrollTransition(.animated(.linear(duration: 1)).threshold(.visible(1))) { effect, phase in
                                effect.offset(x: phase.isIdentity ? 0 : 10).opacity(phase.isIdentity ? 1 : 0)
                            }
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollPosition(binding)
            .frame(width: 30, height: 4)
            _ = screen.render(page, atMillis: 0)
            _ = screen.render(page, atMillis: 0)
            // Row 4 comes wholly into view: from its edge phase to identity,
            // on the frame after the scroll lands, which finds it there.
            // Written without animation, as the harness's standing transaction
            // would otherwise make it: a scroll made inside one glides there
            // (decisions B27-ANIMATING), and this is about the transition.
            position.scrollTo(y: 1)
            let standing = screen.context.environment.transaction
            screen.context.environment.transaction = Transaction()
            _ = screen.render(page, atMillis: 0)
            screen.context.environment.transaction = standing
            _ = screen.render(page, atMillis: 0)
            return place(of: "row 4", in: screen.render(page, atMillis: millis))
        }
        let reduced = halfway(reducesMotion: true)
        let moving = halfway(reducesMotion: false)
        #expect(moving?.x == 5, "it slides")
        #expect(moving?.opacity == 0.5, "it fades")
        #expect(reduced?.x == 0, "the offset jumped")
        #expect(reduced?.opacity == 0.5, "the fade was cut short")
        #expect(halfway(reducesMotion: true, atMillis: 2000)?.opacity == 1, "the fade does not end")
    }

    /// Where a shadow is drawn: its overflow past `Text("ab")`'s frame, as the
    /// layer's place — at `x - radius`, `-radius` for a shadow wholly to the
    /// right of the label.
    private func shadowPlace(_ buffer: FrameBuffer) -> (x: Int, y: Int)? {
        buffer.overlays.first(where: \.isOverflow).map { ($0.offsetX, $0.offsetY) }
    }

    @Test("A shadow's offset jumps to its end where motion is reduced, and slides where it is not")
    func shadowOffsetJumps() {
        func place(reducesMotion: Bool) -> (x: Int, y: Int)? {
            shadowPlace(
                Screen(reducesMotion: reducesMotion)
                    .halfway(from: Text("ab").shadow(radius: 0, x: 4), to: Text("ab").shadow(radius: 0, x: 20)))
        }
        #expect(place(reducesMotion: false)?.x == 12, "it slides")
        #expect(place(reducesMotion: true)?.x == 20)

        let reduced = completion(
            reducesMotion: true, from: Text("ab").shadow(radius: 0, x: 4), to: Text("ab").shadow(radius: 0, x: 20))
        #expect(reduced.firedAtOnce && !reduced.liveHalfway, "an offset held still starts no animation")
    }

    @Test("A shadow's radius still grows where motion is reduced, its offset at its end meanwhile")
    func shadowRadiusStillAnimates() {
        func place(reducesMotion: Bool) -> (x: Int, y: Int)? {
            shadowPlace(
                Screen(reducesMotion: reducesMotion)
                    .halfway(from: Text("ab").shadow(radius: 0, x: 4), to: Text("ab").shadow(radius: 4, x: 20)))
        }
        let moving = place(reducesMotion: false)
        #expect(moving?.x == 10 && moving?.y == -2, "x 12, radius 2")
        let reduced = place(reducesMotion: true)
        #expect(reduced?.x == 18 && reduced?.y == -2, "x 20 at once, radius 2 on its way to 4")
    }
}
