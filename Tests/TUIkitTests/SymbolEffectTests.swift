//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SymbolEffectTests.swift
//
//  SwiftUI's symbol effects over Apple's own Symbols types (decisions A35):
//  which effects a glyph draws (pulse and breathe, told apart by type), what
//  the modifiers put in the environment, the breath as a replayable run, a
//  discrete effect's one play, and the transitions as fades.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Symbols)
    import Foundation
    import Symbols
    import Testing

    import TUIkit
    @testable import TUIkitFoundation

    /// What the glyphs below saw, frame by frame.
    @MainActor
    private final class EffectLog {
        var seen: [SymbolGlyphEffect?] = []
    }

    /// A stand-in for an SF Symbol's glyph that records the effect it was
    /// handed rather than needing the SF Symbols font to draw one.
    private struct EffectReader: View {
        let log: EffectLog
        @Environment(\.symbolGlyphEffect) private var effect

        var body: some View {
            log.seen.append(effect)
            return Text("x")
        }
    }

    /// The reader behind a memo: equal to every other, so `.equatable()`
    /// serves it whenever nothing tells the memo its environment moved.
    private struct MemoizedReader: View, Equatable {
        let log: EffectLog

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

        var body: some View { EffectReader(log: log) }
    }

    /// A repeat option whose printed form names nothing the old reader
    /// looked for — as an SDK's could, the field being private.
    private enum RepeatOptionSpelledOtherwise: CustomStringConvertible {
        case count(Int)
        case indefinite

        var description: String { "a repeat" }
    }

    /// The value a discrete effect watches, changed between frames.
    @MainActor
    private final class Counter {
        var value = 0
    }

    private struct DiscreteApp: App {
        let log: EffectLog
        let counter: Counter

        init() { self.init(log: EffectLog(), counter: Counter()) }

        init(log: EffectLog, counter: Counter) {
            self.log = log
            self.counter = counter
        }

        var body: some Scene {
            WindowGroup {
                EffectReader(log: log).symbolEffect(.pulse, options: .repeat(2), value: counter.value)
            }
        }
    }

    /// The review's shape: the glyph behind `.equatable()`, the watched value
    /// moving with nothing above it written (a plain class, as a timeline's
    /// date is).
    private struct MemoizedDiscreteApp: App {
        let log: EffectLog
        let counter: Counter

        init() { self.init(log: EffectLog(), counter: Counter()) }

        init(log: EffectLog, counter: Counter) {
            self.log = log
            self.counter = counter
        }

        var body: some Scene {
            WindowGroup {
                MemoizedReader(log: log).equatable().symbolEffect(.pulse, options: .default, value: counter.value)
            }
        }
    }

    @MainActor
    @Suite("Symbol effects")
    struct SymbolEffectTests {
        @Test("Pulse and breathe are drawn, told apart by type; the effects that need layers or geometry are not")
        func whichEffectsDraw() {
            #expect(SymbolBreath(PulseSymbolEffect.pulse) == .pulse)
            #expect(SymbolBreath(PulseSymbolEffect.pulse.byLayer) == .pulse)
            #expect(SymbolBreath(VariableColorSymbolEffect.variableColor) == nil)
            #expect(SymbolBreath(BounceSymbolEffect.bounce) == nil)
            #expect(SymbolBreath(ScaleSymbolEffect.scale) == nil)
            #expect(SymbolBreath(AppearSymbolEffect.appear) == nil)
            if #available(macOS 15, *) {
                #expect(SymbolBreath(BreatheSymbolEffect.breathe) == .breathe)
                #expect(SymbolBreath(WiggleSymbolEffect.wiggle) == nil)
                #expect(SymbolBreath(RotateSymbolEffect.rotate) == nil)
            }
        }

        @Test("The options' speed and repeat count are read, and default to 1")
        func optionsAreRead() {
            #expect(SymbolEffectOptions.default.tuikitSpeed == 1)
            #expect(SymbolEffectOptions.speed(2).tuikitSpeed == 2)
            #expect(SymbolEffectOptions.default.tuikitRepeatCount == 1)
            #expect(SymbolEffectOptions.repeat(3).tuikitRepeatCount == 3)
            #expect(SymbolEffectOptions.nonRepeating.tuikitRepeatCount == 1)
            #expect(SymbolEffectOptions.repeating.tuikitRepeatCount == 1, "an indefinite repeat has no count")
            #expect(SymbolEffectOptions.speed(2).repeat(4).tuikitRepeatCount == 4)
            if #available(macOS 15, *) {
                #expect(SymbolEffectOptions.repeat(.periodic(5, delay: 1)).tuikitRepeatCount == 5)
            }
            // By its shape, not its printed form.
            let spelled: RepeatOptionSpelledOtherwise? = .count(6)
            #expect(SymbolEffectOptions.repeatCount(stored: spelled as Any) == 6)
            #expect(SymbolEffectOptions.repeatCount(stored: RepeatOptionSpelledOtherwise.indefinite) == 1)
            #expect(SymbolEffectOptions.repeatCount(stored: nil) == 1)
            #expect(SymbolBreath.frameTicks(speed: 1) == 3)
            #expect(SymbolBreath.frameTicks(speed: 3) == 1)
            #expect(SymbolBreath.frameTicks(speed: 0.5) == 6)
        }

        private func harness() -> (TUIContext, RenderContext) {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.frameNowNanos = 0
            return (tui, RenderContext(availableWidth: 20, availableHeight: 3, environment: environment, tuiContext: tui))
        }

        /// The effect `wrap` puts in the environment of the view it wraps.
        private func environmentEffect(_ wrap: (EffectReader) -> some View) -> SymbolGlyphEffect? {
            let log = EffectLog()
            let (tui, context) = harness()
            tui.stateStorage.beginRenderPass()
            _ = renderToBuffer(wrap(EffectReader(log: log)), context: context)
            tui.stateStorage.endRenderPass()
            return log.seen.last.flatMap { $0 }
        }

        @Test("An active pulse or breathe reaches the glyphs below, at its speed; the rest leave them as they were")
        func theIndefiniteModifier() {
            #expect(environmentEffect { $0.symbolEffect(.pulse) } == .breathing(.pulse, frameTicks: 3))
            #expect(environmentEffect { $0.symbolEffect(.pulse, options: .speed(3)) } == .breathing(.pulse, frameTicks: 1))
            #expect(environmentEffect { $0.symbolEffect(.pulse, isActive: false) } == nil)
            #expect(environmentEffect { $0.symbolEffect(.variableColor) } == nil)
            // An ancestor's survives an effect below that is not drawn, and is
            // removed by `symbolEffectsRemoved`.
            #expect(environmentEffect { $0.symbolEffect(.variableColor).symbolEffect(.pulse) } == .breathing(.pulse, frameTicks: 3))
            #expect(environmentEffect { $0.symbolEffectsRemoved().symbolEffect(.pulse) } == nil)
            #expect(environmentEffect { $0.symbolEffectsRemoved(false).symbolEffect(.pulse) } == .breathing(.pulse, frameTicks: 3))
        }

        @Test("A breathing glyph is one run of a full breath, its ink fading and returning, drawn at the frame's step")
        func theBreathIsARun() {
            let (_, context) = harness()
            let buffer = renderToBuffer(_SymbolEffectGlyph(glyph: "@", effect: .breathing(.pulse, frameTicks: 3)), context: context)
            let run = buffer.animatedCells.first
            #expect(run?.frames.count == SymbolBreath.frameCount)
            #expect(run?.frameTicks == 3)
            #expect(run?.clock == .content)
            #expect(Set(run?.frames ?? []).count > 2, "the ink does not change")
            #expect(run?.frames.allSatisfy { $0.stripped == "@" } == true)
            #expect(buffer.lines.first == run?.frames.first, "frame 0 is not what is drawn at step 0")
            #expect(SymbolBreath.pulse.opacity(atFrame: 0) == 1)
            #expect(abs(SymbolBreath.pulse.opacity(atFrame: SymbolBreath.frameCount / 2) - 1.0 / 3.0) < 1e-9)
        }

        @Test("A discrete pulse plays from a change of its value, as many breaths as its repeat count, then stops")
        func theDiscreteModifier() {
            let log = EffectLog()
            let counter = Counter()
            let app = HeadlessApp(DiscreteApp(log: log, counter: counter), width: 20, height: 3)
            app.frame(atNanos: 0)
            #expect(log.seen.last == .some(nil), "the effect played as the view appeared")

            let start: Int64 = 100_000_000
            counter.value = 1
            app.frame(atNanos: start)
            #expect(log.seen.last == .playing(.pulse, frameTicks: 3, startNanos: start, cycles: 2))
            // Two breaths of a second each, and a frame asked for at the end.
            let end = start + SymbolGlyphEffect.playLength(frameTicks: 3, cycles: 2)
            #expect(end == start + 2_000_000_000)
            #expect(app.nextWake(after: start) == end)
            app.frame(atNanos: end - 1)
            #expect(log.seen.last == .playing(.pulse, frameTicks: 3, startNanos: start, cycles: 2))
            app.frame(atNanos: end)
            #expect(log.seen.last == .some(nil), "the play did not end")
            app.frame(atNanos: end + 1_000_000_000)
            #expect(log.seen.last == .some(nil))
        }

        @Test("Behind an equatable memo a discrete play is seen as it begins and as it ends")
        func theDiscreteModifierBehindAMemo() {
            let log = EffectLog()
            let counter = Counter()
            let app = HeadlessApp(MemoizedDiscreteApp(log: log, counter: counter), width: 20, height: 3)
            app.frame(atNanos: 0)
            app.frame(atNanos: 16_666_667)
            #expect(log.seen.last == .some(nil))

            let start: Int64 = 100_000_000
            counter.value = 1
            app.frame(atNanos: start)
            #expect(log.seen.last == .playing(.pulse, frameTicks: 3, startNanos: start, cycles: 1), "the memo served the frame before the play")
            let end = start + SymbolGlyphEffect.playLength(frameTicks: 3, cycles: 1)
            app.frame(atNanos: end)
            #expect(log.seen.last == .some(nil), "the memo served the play after it ended")
        }

        @Test("The symbol transitions are fades")
        func transitionsAreFades() {
            #expect(ContentTransition.symbolEffect == .opacity)
            #expect(ContentTransition.symbolEffect(.replace) == .opacity)
            #expect(SymbolEffectTransition.properties.hasMotion == false)
            let automatic: SymbolEffectTransition = .symbolEffect
            let disappearing: SymbolEffectTransition = .symbolEffect(.disappear.down)
            #expect(automatic._erased == .opacity)
            #expect(disappearing._erased == .opacity)
        }
    }
#endif
