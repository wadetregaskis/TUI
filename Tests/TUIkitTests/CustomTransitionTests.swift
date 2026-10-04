//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomTransitionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The values an animatable modifier was drawn at, in order.
@MainActor
private final class Drawn {
    var values: [Double] = []
}

/// An animatable modifier that reports every value it is DRAWN at — not
/// measured at — and draws nothing of its own.
private struct Report: BufferModifier, Animatable {
    var animatableData: Double
    let drawn: Drawn

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        drawn.values.append(animatableData)
        return buffer
    }
}

/// A transition whose body is one reported value: 0 away from rest, 10 at it.
private struct Reported: Transition {
    let drawn: Drawn

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(Report(animatableData: phase.isIdentity ? 10 : 0, drawn: drawn))
    }
}

/// A transition that indents the view by four columns away from rest.
private struct Indent: Transition {
    var away = 4
    var atRest = 0

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.padding(.leading, phase.isIdentity ? atRest : away)
    }
}

/// Two cells of content in a slot six wide, so an indented picture has room
/// inside the slot to show.
private struct Wide: View {
    var body: some View {
        Text("XX").frame(width: 6, alignment: .leading)
    }
}

/// A view that counts its renders and remembers where it was drawn.
@MainActor
private final class Renders {
    var count = 0
    var identities: [ViewIdentity] = []
}

private struct Counted: View, Renderable {
    let renders: Renders
    var body: Never { fatalError("Counted renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A render made only to measure is not a drawing.
        if !context.isMeasuring {
            renders.count += 1
            renders.identities.append(context.identity)
        }
        return FrameBuffer(lines: ["XX"])
    }
}

/// Draws `X` (or `XX`) in an optional rendered directly, so a removal has a
/// slot to play in.
@MainActor
private final class Screen {
    var context = makeRenderContext(width: 10, height: 4)

    init(_ animation: Animation?) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    func draw<V: View>(_ view: V?, atMillis millis: Int) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }

    /// The rows drawn, without their styling or their trailing blanks.
    func lines<V: View>(_ view: V?, atMillis millis: Int) -> [String] {
        draw(view, atMillis: millis).lines.map { line in
            String(line.stripped.reversed().drop { $0 == " " }.reversed())
        }
    }
}

@MainActor
@Suite("Transitions with a body of their own")
struct CustomTransitionTests {

    // MARK: - Vocabulary

    @Test("A phase's value is -1, 0 or 1, and only identity is the identity")
    func phaseValues() {
        #expect(TransitionPhase.willAppear.value == -1)
        #expect(TransitionPhase.identity.value == 0)
        #expect(TransitionPhase.didDisappear.value == 1)
        #expect(TransitionPhase.identity.isIdentity)
        #expect(!TransitionPhase.willAppear.isIdentity)
        #expect(!TransitionPhase.didDisappear.isIdentity)
    }

    @Test("Opacity and identity have no motion; the rest do, and a pair has it if either half does")
    func properties() {
        // Measured on SwiftUI (macOS 26.2 SDK).
        #expect(!OpacityTransition.properties.hasMotion)
        #expect(!IdentityTransition.properties.hasMotion)
        #expect(MoveTransition.properties.hasMotion)
        #expect(OffsetTransition.properties.hasMotion)
        #expect(ScaleTransition.properties.hasMotion)
        #expect(SlideTransition.properties.hasMotion)
        #expect(PushTransition.properties.hasMotion)
        #expect(!AsymmetricTransition<OpacityTransition, OpacityTransition>.properties.hasMotion)
        #expect(AsymmetricTransition<OpacityTransition, MoveTransition>.properties.hasMotion)
        #expect(!_CombinedTransition<OpacityTransition, OpacityTransition>.properties.hasMotion)
        #expect(_CombinedTransition<OpacityTransition, MoveTransition>.properties.hasMotion)
        #expect(Indent.properties.hasMotion, "a transition has motion unless it says otherwise")
    }

    @Test("The built-in transitions erase to the effects they are drawn with")
    func builtInsErase() {
        #expect(AnyTransition(OpacityTransition()) == .opacity)
        #expect(AnyTransition(IdentityTransition()) == .identity)
        #expect(AnyTransition(MoveTransition(edge: .top)) == .move(edge: .top))
        #expect(AnyTransition(OffsetTransition(CellSize(width: 2, height: 1))) == .offset(x: 2, y: 1))
        #expect(AnyTransition(ScaleTransition(0.5, anchor: .leading)) == .scale(scale: 0.5, anchor: .leading))
        #expect(AnyTransition(SlideTransition()) == .slide)
        #expect(AnyTransition(PushTransition(edge: .leading)) == .push(from: .leading))
        #expect(
            AnyTransition(OpacityTransition().combined(with: MoveTransition(edge: .top)))
                == AnyTransition.opacity.combined(with: .move(edge: .top)))
        #expect(
            AnyTransition(AsymmetricTransition(insertion: OpacityTransition(), removal: SlideTransition()))
                == .asymmetric(insertion: .opacity, removal: .slide))
        let animated = AnyTransition(OpacityTransition().animation(.linear(duration: 1)))
        #expect(animated.explicitAnimation == .linear(duration: 1))
        #expect(AnyTransition(Indent()).custom != nil, "a body of the app's own is drawn through it")
    }

    @Test("Push is in from its edge and out to the opposite one, fading both ways")
    func pushIsSwiftUIs() {
        #expect(
            AnyTransition.push(from: .top)
                == .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)))
    }

    @Test("The static spellings build the types SwiftUI's do")
    func staticSpellings() {
        let scale: ScaleTransition = .scale
        #expect(scale.scale == 1e-5, "SwiftUI's value, measured")
        #expect(scale.anchor == .center)
        let half: ScaleTransition = .scale(0.5)
        #expect(half.scale == 0.5)
        let offset: OffsetTransition = .offset(x: 3, y: 4)
        #expect(offset.offset == CellSize(width: 3, height: 4))
        let move: MoveTransition = .move(edge: .leading)
        #expect(move.edge == .leading)
        let push: PushTransition = .push(from: .top)
        #expect(push.edge == .top)
    }

    // MARK: - Arriving

    @Test("An arriving body is recorded at willAppear, then drawn at the frame's point towards identity")
    func arrivalScrubs() {
        let drawn = Drawn()
        let screen = Screen(.linear(duration: 1))
        let view = Text("XX").transition(Reported(drawn: drawn))
        _ = screen.draw(Optional<Text>.none.map { $0.transition(Reported(drawn: drawn)) }, atMillis: 0)

        _ = screen.draw(view, atMillis: 0)
        #expect(drawn.values == [0, 0], "recorded at willAppear (0), drawn there too: nothing has moved")
        drawn.values = []
        _ = screen.draw(view, atMillis: 250)
        #expect(drawn.values == [0, 2.5])
        drawn.values = []
        _ = screen.draw(view, atMillis: 1000)
        #expect(drawn.values == [10], "at rest, one render at identity")
    }

    @Test("An indent transition slides the view in from four columns over, inside its slot")
    func arrivalDraws() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.lines(Optional<Wide>.none.map { $0.transition(Indent()) }, atMillis: 0)
        let view = Wide().transition(Indent())
        #expect(screen.lines(view, atMillis: 0).first == "    XX")
        #expect(screen.lines(view, atMillis: 500).first == "  XX")
        #expect(screen.lines(view, atMillis: 1000).first == "XX")
        #expect(screen.draw(view, atMillis: 1000).width == 6)
    }

    @Test("A body bigger part-way than at rest is drawn inside its size at rest")
    func pictureKeepsTheRestingSize() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.lines(Optional<Text>.none.map { $0.transition(Indent()) }, atMillis: 0)
        // At rest the view is two wide; four columns of indent leave nothing
        // of it inside those two.
        let drawn = screen.draw(Text("XX").transition(Indent()), atMillis: 0)
        #expect(drawn.width <= 2)
        #expect(drawn.lines.map(\.stripped).joined().trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("Without an animation an appearance is the body at rest at once")
    func unanimatedArrival() {
        let screen = Screen(nil)
        _ = screen.lines(Optional<Text>.none.map { $0.transition(Indent()) }, atMillis: 0)
        #expect(screen.lines(Text("XX").transition(Indent()), atMillis: 0).first == "XX")
    }

    @Test("At rest the body is drawn at identity, and what it leaves there stays")
    func restingBodyIsDrawn() {
        let screen = Screen(nil)
        let view = Text("XX").transition(Indent(away: 4, atRest: 1))
        #expect(screen.lines(view, atMillis: 0).first == " XX")
        #expect(screen.lines(view, atMillis: 100).first == " XX")
    }

    @Test("A spring carries the body past rest, extrapolating every value")
    func overshootExtrapolates() {
        let drawn = Drawn()
        let screen = Screen(.spring(duration: 0.5, bounce: 0.5))
        _ = screen.draw(Optional<Text>.none.map { $0.transition(Reported(drawn: drawn)) }, atMillis: 0)
        let view = Text("XX").transition(Reported(drawn: drawn))
        var peak = 0.0
        for millis in stride(from: 0, through: 1000, by: 20) {
            drawn.values = []
            _ = screen.draw(view, atMillis: millis)
            peak = max(peak, drawn.values.last ?? 0)
        }
        #expect(peak > 10.5, "a bouncy spring overshoots: peak \(peak)")
    }

    // MARK: - The content

    @Test("The content is drawn once a frame, at the transition's own identity")
    func contentDrawnOnceAtTransitionIdentity() {
        let screen = Screen(.linear(duration: 1))
        let plain = Renders()
        _ = screen.draw(Counted(renders: plain).transition(.opacity), atMillis: 0)

        let custom = Renders()
        let fresh = Screen(.linear(duration: 1))
        _ = fresh.draw(Optional<Counted>.none.map { $0.transition(Indent()) }, atMillis: 0)
        _ = fresh.draw(Counted(renders: custom).transition(Indent()), atMillis: 0)
        #expect(custom.count == 1, "the record pass draws an empty box, not the content")
        _ = fresh.draw(Counted(renders: custom).transition(Indent()), atMillis: 500)
        #expect(custom.count == 2)
        #expect(custom.identities.first == plain.identities.first, "the content's @State is where it would be")
    }

    @Test("An environment value the body sets reaches the live content")
    func bodyEnvironmentReachesContent() {
        struct Disabling: Transition {
            func body(content: Content, phase: TransitionPhase) -> some View {
                content.disabled(true)
            }
        }
        struct ReadsDisabled: View {
            @Environment(\.isEnabled) var isEnabled
            var body: some View { Text(isEnabled ? "on" : "off") }
        }
        let screen = Screen(nil)
        #expect(screen.lines(ReadsDisabled().transition(Disabling()), atMillis: 0).first == "off")
    }

    // MARK: - Leaving

    @Test("A departing body is drawn around the content's last picture, towards didDisappear")
    func removalScrubs() {
        let screen = Screen(.linear(duration: 1))
        let present: Wide? = Wide()
        let absent: Wide? = nil
        _ = screen.lines(present.map { $0.transition(Indent()) }, atMillis: 0)
        _ = screen.lines(present.map { $0.transition(Indent()) }, atMillis: 1100)
        #expect(screen.lines(absent.map { $0.transition(Indent()) }, atMillis: 1100).first == "XX")
        #expect(screen.lines(absent.map { $0.transition(Indent()) }, atMillis: 1600).first == "  XX")
        #expect(screen.lines(absent.map { $0.transition(Indent()) }, atMillis: 2200).isEmpty)
    }

    // MARK: - Composition

    @Test("A built-in composed into a body draws as the built-in does")
    func composedBuiltInMatchesFastPath() {
        struct Faded: Transition {
            func body(content: Content, phase: TransitionPhase) -> some View {
                OpacityTransition().apply(content: content, phase: phase)
            }
        }
        let fast = Screen(.linear(duration: 1))
        _ = fast.draw(Optional<Text>.none.map { $0.transition(.opacity) }, atMillis: 0)
        _ = fast.draw(Text("XX").transition(.opacity), atMillis: 0)
        let expected = fast.draw(Text("XX").transition(.opacity), atMillis: 400).lines

        let body = Screen(.linear(duration: 1))
        _ = body.draw(Optional<Text>.none.map { $0.transition(Faded()) }, atMillis: 0)
        _ = body.draw(Text("XX").transition(Faded()), atMillis: 0)
        let drawn = body.draw(Text("XX").transition(Faded()), atMillis: 400).lines
        #expect(drawn == expected)
        #expect(drawn != body.draw(Text("XX").transition(Faded()), atMillis: 1000).lines)
    }

    @Test("A body of the app's own combines with an effect, through the erased value")
    func customCombinesWithEffect() {
        let screen = Screen(.linear(duration: 1))
        let transition = AnyTransition(Indent()).combined(with: .opacity)
        #expect(transition.custom != nil)
        _ = screen.lines(Optional<Wide>.none.map { $0.transition(transition) }, atMillis: 0)
        #expect(screen.lines(Wide().transition(transition), atMillis: 0).first == "    XX")
        #expect(screen.lines(Wide().transition(transition), atMillis: 500).first == "  XX")
        #expect(screen.lines(Wide().transition(transition), atMillis: 1000).first == "XX")
    }

    @Test("Asymmetric with a body of its own uses the body arriving and the effect leaving")
    func asymmetricCustom() {
        let screen = Screen(.linear(duration: 1))
        let transition = AnyTransition.asymmetric(
            insertion: AnyTransition(Indent()), removal: .move(edge: .trailing))
        let present: Wide? = Wide()
        let absent: Wide? = nil
        _ = screen.lines(absent.map { $0.transition(transition) }, atMillis: 0)
        #expect(screen.lines(present.map { $0.transition(transition) }, atMillis: 0).first == "    XX")
        #expect(screen.lines(present.map { $0.transition(transition) }, atMillis: 500).first == "  XX")
        _ = screen.lines(present.map { $0.transition(transition) }, atMillis: 1100)
        _ = screen.lines(absent.map { $0.transition(transition) }, atMillis: 1100)
        // Leaving by the move: three of the six columns gone to the trailing side.
        #expect(screen.lines(absent.map { $0.transition(transition) }, atMillis: 1600).first == "   XX")
    }
}
