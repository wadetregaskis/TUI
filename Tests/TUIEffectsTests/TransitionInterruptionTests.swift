//  🖥️ TUI — A Terminal UI framework for Swift
//  TransitionInterruptionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport

/// The values an animatable modifier was drawn at, in order.
@MainActor
private final class Drawn {
    var values: [Double] = []
}

/// An animatable modifier that reports every value it is drawn at.
private struct Report: BufferModifier, Animatable {
    var animatableData: Double
    let drawn: Drawn

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        drawn.values.append(animatableData)
        return buffer
    }
}

/// A body that sets one value: -10 arriving, 0 at rest, 10 leaving — so its
/// arrival and its removal pull opposite ways, as `.push`'s do.
private struct Swept: Transition {
    let drawn: Drawn

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(Report(animatableData: phase.value * 10, drawn: drawn))
    }
}

/// Ten cells of content in an optional rendered directly, every frame under a
/// one-second linear animation: a removal has a slot to play in, and a move
/// shows a cell for every tenth of the way.
@MainActor
private final class Slot {
    var context = makeRenderContext(width: 10, height: 4)

    init() {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
    }

    func draw<V: View>(_ view: V?, atMillis millis: Int) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }

    /// The first row drawn with `transition` on the content, or without the
    /// content, without its styling or its trailing blanks.
    func row(_ showing: Bool, _ transition: AnyTransition, atMillis millis: Int) -> String {
        let content: Text? = showing ? Text("XXXXXXXXXX") : nil
        let line = draw(content.map { $0.transition(transition) }, atMillis: millis).lines.first ?? ""
        return String(line.stripped.reversed().drop { $0 == " " }.reversed())
    }
}

/// An `if`'s view with no transition of its own, above a row.
private struct Stacked: View {
    let showing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showing { Text("XXXX") }
            Text("----")
        }
    }
}

/// `Stacked`, each frame animated or not as the change it draws is: the fades it is drawn with are
/// what its default transition does.
@MainActor
private final class FadeScreen {
    var context = makeRenderContext(width: 8, height: 4)

    init() {
        context.environment.canAnimate = true
    }

    /// The strengths of the fades drawn at `millis`, to two places.
    func fades(_ showing: Bool, atMillis millis: Int, animated: Bool) -> [Double] {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        context.environment.transaction = Transaction(animation: animated ? .linear(duration: 1) : nil)
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        // Its layers' too: while the row below glides, the stack draws its
        // children past itself.
        func strengths(_ buffer: FrameBuffer) -> [Double] {
            buffer.opacityRegions.map { ($0.opacity * 100).rounded() / 100 }
                + buffer.overlays.flatMap { strengths($0.content) }
        }
        return strengths(renderToBuffer(Stacked(showing: showing), context: context))
    }
}

/// A transition interrupted by a change that reverses it carries on from where
/// the view is, as SwiftUI's does (measured,
/// `Tools/SwiftUIProbes/Transitions/tr5.out`): the animation it interrupted runs
/// on, and the new one takes each value from wherever that has it.
@MainActor
@Suite("Transitions interrupted")
struct TransitionInterruptionTests {
    nonisolated static let pushAside = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing), removal: .move(edge: .leading))

    /// Owner's ruling ROW-REMOVAL (b): at 30% in, a `.push` removed jumped
    /// from 70% off the trailing side to 70% off the leading one, the removal
    /// taken to the arrival's phase. SwiftUI (T19, T20): it carries on from
    /// 70% off the trailing side, its arrival running on beneath the removal.
    @Test(
        "A view removed mid-insertion whose removal goes the other way carries on from where it is",
        arguments: [pushAside, .push(from: .trailing)])
    func asymmetricRemovalCarriesOn(transition: AnyTransition) {
        let slot = Slot()
        _ = slot.row(true, transition, atMillis: 0)
        #expect(slot.row(true, transition, atMillis: 300) == "       XXX", "precondition: 30% in")
        #expect(slot.row(false, transition, atMillis: 300) == "       XXX", "the removal starts where the view is")
        // Arrived 0.5 by now, so its own move has 0.4 left to undo, 0.8 of it
        // still to come: four cells right; the removal's, 0.2 of the way, two
        // left. Taken to the arrival's phase it was 8 cells off the left.
        #expect(slot.row(false, transition, atMillis: 500) == "  XXXXXXXX")
        #expect(slot.row(false, transition, atMillis: 900) == "XXXX", "out to the leading side")
        #expect(slot.row(false, transition, atMillis: 1400).isEmpty)
    }

    /// SwiftUI (T18): removed at 30%, a `.move` goes on towards its place,
    /// slowing, before it turns and leaves — its arrival runs on beneath the
    /// removal, rather than standing where it was when the removal came.
    @Test("A view removed mid-insertion goes on towards its place before it turns back")
    func symmetricRemovalCarriesOn() {
        let slot = Slot()
        let transition = AnyTransition.move(edge: .trailing)
        _ = slot.row(true, transition, atMillis: 0)
        #expect(slot.row(true, transition, atMillis: 300) == "       XXX")
        #expect(slot.row(false, transition, atMillis: 300) == "       XXX")
        // 0.5 arrived × 0.8 present: six cells off, where 0.3 × 0.8 was eight.
        #expect(slot.row(false, transition, atMillis: 500) == "      XXXX")
        #expect(slot.row(false, transition, atMillis: 1000) == "       XXX")
    }

    /// The default fade of an `if`'s view: `arrived × presence`, the arrival
    /// running on (T18's arithmetic, on opacity).
    @Test("A view fading in that is removed fades out from where its arrival has got by then")
    func defaultFadeCarriesOn() {
        let screen = FadeScreen()
        _ = screen.fades(false, atMillis: 0, animated: false)
        _ = screen.fades(true, atMillis: 10, animated: true)
        #expect(screen.fades(true, atMillis: 510, animated: false) == [0.5], "precondition: half in")
        #expect(screen.fades(false, atMillis: 510, animated: true) == [0.5])
        #expect(
            screen.fades(false, atMillis: 710, animated: false) == [0.56], "0.7 arrived × 0.8 present, not 0.5 × 0.8")
    }

    /// A body of the app's own: each value from where the arrival has it
    /// towards the removal's end.
    @Test("A body removed mid-insertion draws each value from where its arrival has it")
    func bodyRemovalCarriesOn() {
        let drawn = Drawn()
        let slot = Slot()
        let present: Text? = Text("XX")
        let absent: Text? = nil
        _ = slot.draw(absent.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 0)
        _ = slot.draw(present.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 0)
        _ = slot.draw(present.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 300)
        #expect(isNear(drawn.values.last, -7), "precondition: 30% in")
        _ = slot.draw(absent.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 300)
        #expect(isNear(drawn.values.last, -7), "the removal starts where the value is")
        // The arrival has it at -5 by now; 0.2 of the way from there to 10.
        _ = slot.draw(absent.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 500)
        #expect(isNear(drawn.values.last, -2), "\(drawn.values)")
    }

    // MARK: - Back mid-removal

    /// SwiftUI (T22 to T24): inserted again 30% into its removal, the view is
    /// the same view, and comes back from where the removal has it, the
    /// removal running on beneath its return: `r + (1 − r) q` present, by the
    /// removal's effect — so an asymmetric move returns from the side it was
    /// leaving by. It used to start its arrival from nothing, from the side
    /// it arrives from.
    @Test(
        "A view inserted again mid-removal comes back from where it is, the way it was going",
        arguments: [pushAside, .push(from: .trailing), .move(edge: .leading)])
    func returnCarriesOn(transition: AnyTransition) {
        let slot = Slot()
        _ = slot.row(true, transition, atMillis: 0)
        #expect(slot.row(true, transition, atMillis: 1100) == "XXXXXXXXXX", "precondition: arrived")
        _ = slot.row(false, transition, atMillis: 1100)
        #expect(slot.row(false, transition, atMillis: 1400) == "XXXXXXX", "precondition: 30% out to the leading side")
        #expect(slot.row(true, transition, atMillis: 1400) == "XXXXXXX", "it comes back from where it is")
        // The removal has it 0.5 present by now, and the return 0.2 of the
        // way from there: 0.6, four cells off the leading side.
        #expect(slot.row(true, transition, atMillis: 1600) == "XXXXXX")
        // The removal has played out; the return is 0.7 of the way from nothing.
        #expect(slot.row(true, transition, atMillis: 2100) == "XXXXXXX")
        #expect(slot.row(true, transition, atMillis: 2400) == "XXXXXXXXXX")
    }

    /// The same view, removed again while it comes back: from where the
    /// return has it, by the removal's effect alone.
    @Test("A view removed again while it comes back leaves from where it is")
    func removalOfAReturnCarriesOn() {
        let slot = Slot()
        let transition = Self.pushAside
        _ = slot.row(true, transition, atMillis: 0)
        _ = slot.row(true, transition, atMillis: 1100)
        _ = slot.row(false, transition, atMillis: 1100)
        _ = slot.row(false, transition, atMillis: 1400)
        _ = slot.row(true, transition, atMillis: 1400)
        #expect(slot.row(true, transition, atMillis: 1600) == "XXXXXX", "precondition: 0.6 present")
        #expect(slot.row(false, transition, atMillis: 1600) == "XXXXXX", "the removal starts where the view is")
    }

    /// An `if`'s default fade, inserted again mid-removal (T21: 0.71 down to
    /// 0.59 and back up to 1).
    @Test("A view fading out that is inserted again fades back in from where it is")
    func defaultFadeReturnCarriesOn() {
        let screen = FadeScreen()
        _ = screen.fades(false, atMillis: 0, animated: false)
        _ = screen.fades(true, atMillis: 10, animated: false)
        _ = screen.fades(false, atMillis: 100, animated: true)
        #expect(screen.fades(false, atMillis: 400, animated: false) == [0.7], "precondition: 30% out")
        #expect(screen.fades(true, atMillis: 400, animated: true) == [0.7], "it comes back from where it is")
        #expect(screen.fades(true, atMillis: 600, animated: false) == [0.6], "0.5 + 0.5 × 0.2")
        #expect(screen.fades(true, atMillis: 1100, animated: false) == [0.7], "the removal over, 0.7 of the way")
        #expect(screen.fades(true, atMillis: 1500, animated: false).isEmpty, "arrived")
        // And removed once more after it has: as any view that has arrived.
        _ = screen.fades(false, atMillis: 1500, animated: true)
        #expect(screen.fades(false, atMillis: 2000, animated: false) == [0.5], "its removal starts, and plays")
    }

    /// A body of the app's own comes back from `.didDisappear`, where the
    /// removal has it.
    @Test("A body inserted again mid-removal comes back from where its removal has each value")
    func bodyReturnCarriesOn() {
        let drawn = Drawn()
        let slot = Slot()
        let present: Text? = Text("XX")
        let absent: Text? = nil
        _ = slot.draw(present.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 0)
        _ = slot.draw(present.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 1100)
        _ = slot.draw(absent.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 1100)
        _ = slot.draw(absent.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 1400)
        #expect(isNear(drawn.values.last, 3), "precondition: 30% out")
        _ = slot.draw(present.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 1400)
        #expect(isNear(drawn.values.last, 3), "it comes back from where it is: \(drawn.values)")
        _ = slot.draw(present.map { $0.transition(Swept(drawn: drawn)) }, atMillis: 1600)
        #expect(isNear(drawn.values.last, 4), "0.6 present, from 10: \(drawn.values)")
    }
}

/// Whether `value` is `expected`, give or take the rounding of a fraction.
private func isNear(_ value: Double?, _ expected: Double) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 1e-9
}
