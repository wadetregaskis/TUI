//  🖥️ TUI — A Terminal UI framework for Swift
//  SymbolGlyphEffect.swift
//
//  How an SF Symbol's glyph breathes under a pulse or a breathe symbol effect
//  (decisions A35). The effects arrive through Apple's Symbols types, on
//  macOS only (`SymbolEffects+Symbols.swift`); what reaches the glyph is this,
//  which names none of them. Only where Symbols is, as the effects are, so an
//  icon elsewhere carries none of it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Symbols)
    import Foundation

    /// The breath a symbol's glyph draws: its ink fading toward what is behind it
    /// and back, the one change a single glyph in a cell can show of SF Symbols'
    /// pulse and breathe.
    package enum SymbolBreath: Equatable, Sendable {
        /// Pulse: down to a third of the ink, as SF Symbols' pulse fades the
        /// symbol's layers.
        case pulse
        /// Breathe: a gentler swell, down to two thirds; SF Symbols' breathe also
        /// scales the symbol, which a glyph cannot.
        case breathe

        /// The ink's opacity at the faintest point of the breath.
        var faintest: Double {
            switch self {
            case .pulse: 1.0 / 3.0
            case .breathe: 2.0 / 3.0
            }
        }

        /// Frames in one breath: a second at 60 Hz in steps of three ticks.
        static let frameCount = 20

        /// Ticks of 1/60 s each frame shows for at `speed` (SF Symbols' default 1
        /// is a breath a second), at least one.
        package static func frameTicks(speed: Double) -> Int {
            guard speed.isFinite, speed > 0 else { return AnimationClock.standardFrameTicks }
            return max(1, Int((Double(AnimationClock.standardFrameTicks) / speed).rounded()))
        }

        /// The ink's opacity at frame `index` of a breath: full at its start, the
        /// faintest at its middle, on a cosine.
        func opacity(atFrame index: Int) -> Double {
            let phase = Double(index % Self.frameCount) / Double(Self.frameCount)
            return 1 - (1 - faintest) * (1 - cos(2 * .pi * phase)) / 2
        }
    }

    /// The symbol effect a glyph below draws, if any — set by
    /// `symbolEffect(_:options:isActive:)` and `symbolEffect(_:options:value:)`,
    /// cleared by `symbolEffectsRemoved(_:)`.
    package enum SymbolGlyphEffect: Equatable, Sendable {
        /// Breathing for as long as it is in the environment.
        case breathing(SymbolBreath, frameTicks: Int)
        /// `cycles` breaths from `startNanos` on the frame clock, then still.
        case playing(SymbolBreath, frameTicks: Int, startNanos: Int64, cycles: Int)

        /// How long a play lasts, in nanoseconds.
        package static func playLength(frameTicks: Int, cycles: Int) -> Int64 {
            AnimationClock.nanoseconds(atTick: Int64(frameTicks) * Int64(SymbolBreath.frameCount) * Int64(max(1, cycles)))
        }
    }

    private struct SymbolGlyphEffectKey: EnvironmentKey {
        static let defaultValue: SymbolGlyphEffect? = nil
    }

    extension EnvironmentValues {
        /// The symbol effect the SF Symbol glyphs below draw. See ``SymbolGlyphEffect``.
        package var symbolGlyphEffect: SymbolGlyphEffect? {
            get { self[SymbolGlyphEffectKey.self] }
            set { self[SymbolGlyphEffectKey.self] = newValue }
        }
    }

    // MARK: - The glyph

    /// An SF Symbol's glyph drawn with its effect: the ink breathing, as one
    /// ``AnimatedCellRun`` the run loop replays, or for a play, drawn frame by
    /// frame until it ends. With no effect, the glyph as a plain `Text`: what
    /// `_SymbolIcon` draws for every glyph, so an icon is one view whether or not
    /// an effect is set.
    struct _SymbolEffectGlyph: View {
        let glyph: String
        let effect: SymbolGlyphEffect?

        var body: Never {
            fatalError("_SymbolEffectGlyph renders via Renderable")
        }

        /// The glyph in `ink`, through `Text` so it is drawn as a symbol always is.
        private func drawn(_ ink: Color?, context: RenderContext) -> FrameBuffer {
            let text = Text(verbatim: glyph)
            return TUIView.renderToBuffer(ink.map { text.foregroundStyle($0) } ?? text, context: context)
        }

        /// The ink at `opacity`, composited over the palette's page: a frame of a
        /// run is a finished string, so its colours are the blended ones.
        private func ink(_ opacity: Double, context: RenderContext) -> Color {
            let palette = context.environment.palette
            let full = (context.environment.foregroundStyle?.representative ?? palette.foreground).resolve(with: palette)
            return full.compositing(opacity, over: palette.background.resolve(with: palette))
        }
    }

    extension _SymbolEffectGlyph: Renderable, Layoutable {
        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            measureChild(Text(verbatim: glyph), proposal: proposal, context: context)
        }

        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            let glyph = breathing(context: context)
            // A breath draws in inks of its own, faded from the foreground
            // style's, so the glyph's `Text` casts no shadow: a shadowed style's
            // shadows are cast here instead (``ShapeStyle/shadow(_:)``). A glyph
            // drawn in the style itself has cast them already.
            guard glyph.inked, let paint = context.environment.foregroundStyle else { return glyph.buffer }
            return glyph.buffer.castingShadows(of: paint, context: context, owner: Self.self)
        }

        /// The glyph at this frame of its effect, and whether it is drawn in an
        /// ink of the effect's own rather than in the foreground style.
        private func breathing(context: RenderContext) -> (buffer: FrameBuffer, inked: Bool) {
            guard let effect, !context.isMeasuring else { return (drawn(nil, context: context), false) }
            let now = context.environment.frameNowNanos
            switch effect {
            case .breathing(let breath, let frameTicks):
                let frames = (0..<SymbolBreath.frameCount).map {
                    drawn(ink(breath.opacity(atFrame: $0), context: context), context: context).lines.first ?? ""
                }
                let elapsed = Double(now) / 1_000_000_000
                let step = Int(AnimationClock.step(atElapsed: elapsed, frameTicks: frameTicks) % Int64(frames.count))
                var buffer = drawn(ink(breath.opacity(atFrame: (step + frames.count) % frames.count), context: context), context: context)
                if let first = frames.first, frames.allSatisfy({ $0.strippedLength == first.strippedLength }) {
                    buffer.animatedCells.append(
                        AnimatedCellRun(
                            offsetX: 0, offsetY: 0, width: first.strippedLength, frames: frames,
                            frameTicks: frameTicks, clock: .content))
                }
                return (buffer, true)
            case .playing(let breath, let frameTicks, let start, let cycles):
                let length = SymbolGlyphEffect.playLength(frameTicks: frameTicks, cycles: cycles)
                guard now >= start, now < start &+ length else { return (drawn(nil, context: context), false) }
                let tick = AnimationClock.tick(atNanoseconds: now &- start)
                let frame = Int(tick / Int64(frameTicks) % Int64(SymbolBreath.frameCount))
                // A frame at the next step, until the play is over; the modifier
                // that started it asks for the one at its end.
                context.requestWake(
                    token: "symbol-effect-\(context.identity.path)",
                    atNanos: start &+ AnimationClock.nanoseconds(atTick: (tick / Int64(frameTicks) + 1) * Int64(frameTicks)))
                return (drawn(ink(breath.opacity(atFrame: frame), context: context), context: context), true)
            }
        }
    }
#endif
