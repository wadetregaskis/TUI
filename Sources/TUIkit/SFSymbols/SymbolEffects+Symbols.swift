//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SymbolEffects+Symbols.swift
//
//  SwiftUI's symbol effects, taking Apple's own Symbols types (decisions
//  A35): macOS only, since the Symbols framework is; elsewhere the API is
//  absent, so code that uses it does not compile.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Symbols)
    import Foundation
    import Symbols

    // MARK: - Which effects a glyph can show

    extension SymbolBreath {
        /// The breath `effect` draws, by its type: pulse and breathe are the two
        /// of SF Symbols' indefinite effects one glyph in one cell can show.
        /// Every other type — bounce, scale, wiggle, rotate, variable colour —
        /// needs the symbol's layers or its geometry, and is not drawn.
        init?(_ effect: some SymbolEffect) {
            if effect is PulseSymbolEffect {
                self = .pulse
            } else if #available(macOS 15, *), effect is BreatheSymbolEffect {
                self = .breathe
            } else {
                return nil
            }
        }
    }

    extension SymbolEffectOptions {
        /// The speed the options ask for, 1 where it cannot be read.
        ///
        /// Symbols keeps its options' values to itself — `SymbolEffectOptions`
        /// has no getters — so they are read off its stored properties by
        /// reflection, and a layout that ever stops matching falls back to the
        /// defaults rather than failing.
        var tuikitSpeed: Double {
            (Mirror(reflecting: self).children.first { $0.label == "speed" }?.value as? Double) ?? 1
        }

        /// How many times a discrete effect plays: a count the options give,
        /// else once.
        ///
        /// Read by its shape, not its spelling: the stored `repeat` is an
        /// optional enum whose counted case mirrors as one child labelled
        /// `count` holding an `Int` (`.repeat(3)`, `.nonRepeating`, and on
        /// macOS 15 `.repeat(.periodic(3, delay:))` all store it so,
        /// measured). Earlier this parsed `String(describing:)`, which
        /// names the private type and would drop the count silently if its
        /// printed form changed; `SymbolEffectTests` pins the reading on every
        /// SDK the tests run against.
        var tuikitRepeatCount: Int {
            Self.repeatCount(stored: Mirror(reflecting: self).children.first { $0.label == "repeat" }?.value)
        }

        /// The count in a stored repeat option: an optional enum's `count`
        /// case, at least 1; 1 for anything else.
        static func repeatCount(stored: Any?) -> Int {
            guard var repeatOption = stored else { return 1 }
            let optional = Mirror(reflecting: repeatOption)
            if optional.displayStyle == .optional {
                guard let wrapped = optional.children.first?.value else { return 1 }
                repeatOption = wrapped
            }
            let count = Mirror(reflecting: repeatOption).children.first { $0.label == "count" }?.value as? Int
            return max(1, count ?? 1)
        }
    }

    // MARK: - The modifiers

    extension View {
        /// Returns a new view with a symbol effect added to it — mirrors
        /// SwiftUI's `symbolEffect(_:options:isActive:)`.
        ///
        /// ```swift
        /// VStack {
        ///     Image(systemName: "bolt.slash.fill")
        ///     Image(systemName: "folder.fill.badge.person.crop")
        /// }
        /// .symbolEffect(.pulse)
        /// ```
        ///
        /// > Important: **Two of SF Symbols' effects are drawn: pulse and
        /// > breathe.** A symbol in a terminal is one glyph in one cell, so what
        /// > it can show is its ink fading toward what is behind it and back —
        /// > pulse fades it to a third, breathe to two thirds (breathe's swell
        /// > in size is not drawn). Bounce, scale, wiggle, rotate and variable
        /// > colour need the symbol's layers or its geometry: they compile,
        /// > being Apple's own types, and change nothing. Told apart by type,
        /// > so `.pulse.byLayer` pulses as `.pulse` does. The options' speed is
        /// > honoured; a repeat count is not, here — the effect breathes while
        /// > it is active.
        ///
        /// macOS only, as the Symbols framework is. An `Image(systemName:)`
        /// draws only where the terminal has the SF Symbols font (see
        /// ``SFSymbol``), and so does its effect.
        ///
        /// - Parameters:
        ///   - effect: A symbol effect to add to the view. Existing effects
        ///     added by ancestors of the view are preserved, but may be
        ///     overridden by the new effect. Added effects will be applied to
        ///     the `Image` views contained by the child view.
        ///   - options: The options for the effect.
        ///   - isActive: whether the effect is active or inactive.
        /// - Returns: a copy of the view with a symbol effect added.
        public func symbolEffect<T: IndefiniteSymbolEffect & SymbolEffect>(
            _ effect: T, options: SymbolEffectOptions = .default, isActive: Bool = true
        ) -> some View {
            let breath = isActive ? SymbolBreath(effect) : nil
            let frameTicks = SymbolBreath.frameTicks(speed: options.tuikitSpeed)
            return transformEnvironment(\.symbolGlyphEffect) { inherited in
                guard let breath else { return }
                inherited = .breathing(breath, frameTicks: frameTicks)
            }
        }

        /// Returns a new view with a symbol effect added to it — mirrors
        /// SwiftUI's `symbolEffect(_:options:value:)`.
        ///
        /// The effect plays each time `value` changes: a pulse or a breathe
        /// breathes once (or as many times as the options' repeat count says),
        /// at the options' speed. The other discrete effects — bounce above
        /// all — are not drawn; see ``View/symbolEffect(_:options:isActive:)``.
        ///
        /// - Parameters:
        ///   - effect: A symbol effect to add to the view.
        ///   - options: The options for the effect.
        ///   - value: the value to monitor for changes, the animation is
        ///     triggered each time the value changes.
        /// - Returns: a copy of the view with a symbol effect added.
        public func symbolEffect<T: DiscreteSymbolEffect & SymbolEffect, U: Equatable>(
            _ effect: T, options: SymbolEffectOptions = .default, value: U
        ) -> some View {
            _DiscreteSymbolEffectModifier(
                content: self, breath: SymbolBreath(effect),
                frameTicks: SymbolBreath.frameTicks(speed: options.tuikitSpeed),
                cycles: options.tuikitRepeatCount, value: value)
        }

        /// Returns a new view with its inherited symbol image effects either
        /// removed or left unchanged — mirrors SwiftUI's
        /// `symbolEffectsRemoved(_:)`.
        ///
        /// - Parameter isEnabled: Whether to remove inherited symbol effects
        ///   or not.
        /// - Returns: a copy of the view with its symbol effects either
        ///   removed or left unchanged.
        public func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View {
            transformEnvironment(\.symbolGlyphEffect) { inherited in
                if isEnabled { inherited = nil }
            }
        }
    }

    // MARK: - The discrete form

    /// The view behind `symbolEffect(_:options:value:)`: compares `value`
    /// with the one the last render saw, as `.onChange` does, and from a
    /// change plays the breath for the glyphs below until it is over.
    struct _DiscreteSymbolEffectModifier<Content: View, Value: Equatable>: View {
        let content: Content
        let breath: SymbolBreath?
        let frameTicks: Int
        let cycles: Int
        let value: Value

        var body: Never {
            fatalError("_DiscreteSymbolEffectModifier renders via Renderable")
        }

        /// What the last render saw, and when the play it started began.
        fileprivate struct Seen {
            let value: Value
            let startNanos: Int64?
        }
    }

    extension _DiscreteSymbolEffectModifier: Renderable, Layoutable {
        /// The content's context: one environment application deeper, as below
        /// any modifier that notes what it applies, so a `symbolEffectsRemoved`
        /// drawn at this identity notes under a slot of its own.
        private func contentContext(_ context: RenderContext) -> RenderContext {
            var content = context
            content.environmentApplicationDepth += 1
            return content
        }

        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            // The effect never changes a glyph's size, so the measure applies none.
            measureChild(content, proposal: proposal, context: contentContext(context))
        }

        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            guard let breath, !context.isMeasuring, let storage = context.stateStorage else {
                return TUIkitView.renderToBuffer(content, context: contentContext(context))
            }
            // A per-frame comparison, which a served buffer would skip: declared,
            // as `.onChange` declares its own.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            let key = StateStorage.StateKey(
                identity: context.identity, propertyIndex: storage.nextOnChangeIndex(for: context.identity))
            let now = context.environment.frameNowNanos
            let seen: Seen? = storage.trackedValue(for: key)
            var start = seen?.startNanos
            if let seen, seen.value != value { start = now }
            storage.setTrackedValue(Seen(value: value, startNanos: start), for: key)
            storage.markActive(context.identity)

            var playing = contentContext(context)
            if let start {
                let end = start &+ SymbolGlyphEffect.playLength(frameTicks: frameTicks, cycles: cycles)
                if now < end {
                    playing.environment.symbolGlyphEffect = .playing(
                        breath, frameTicks: frameTicks, startNanos: start, cycles: cycles)
                    context.requestWake(token: "symbol-play-\(context.identity.path)", atNanos: end)
                }
            }
            // Noted as an environment modifier notes its value, because a memo
            // below keys on its own view value and cannot see the play begin or
            // end: written straight into the context, an `.equatable()` glyph
            // whose value did not change served the frame drawn before the play
            // (the setting-bypasses-cache class). The play's start is in the
            // value, so the clear comes once at each end of a play.
            if let cache = context.renderCache,
                case .changed = cache.noteAppliedEnvironment(
                    playing.environment.symbolGlyphEffect as Any, identity: context.identity,
                    keyPath: \EnvironmentValues.symbolGlyphEffect, depth: context.environmentApplicationDepth)
            {
                cache.clearAffected(by: context.identity)
            }
            return TUIkitView.renderToBuffer(content, context: playing)
        }
    }

    extension _DiscreteSymbolEffectModifier: SingleContentWrapper {
        var wrappedContent: Content { content }
    }

    /// Draws its content unchanged, at its own identity, so a removal
    /// transition written inside it plays — see `DrawsContentUnchanged`.
    extension _DiscreteSymbolEffectModifier: DrawsContentUnchanged {}

    // MARK: - Transitions

    /// Creates a transition that applies the Appear, Disappear, DrawOn or
    /// DrawOff symbol animation to symbol images within the inserted or
    /// removed view hierarchy — mirrors SwiftUI's `SymbolEffectTransition`.
    ///
    /// > Important: **Drawn as a fade of the whole view.** One glyph in one
    /// > cell cannot draw a symbol's layers appearing or its strokes being
    /// > drawn on, so the transition fades in and out through the opacity
    /// > compositor, as ``OpacityTransition`` does — and fades everything the
    /// > transition is on, where SwiftUI's leaves views other than symbol
    /// > images unaffected. The effect's direction and options are not drawn.
    public struct SymbolEffectTransition: Transition {
        /// Creates a transition for `effect` with `options`.
        public init<T: SymbolEffect & TransitionSymbolEffect>(effect: T, options: SymbolEffectOptions) {}

        /// The fade the transition is drawn as.
        public func body(content: Content, phase: TransitionPhase) -> some View {
            content.modifier(_TransitionEffectModifier(.opacity, phase: phase))
        }

        /// No motion: a fade.
        public static let properties = TransitionProperties(hasMotion: false)

        public var _erased: AnyTransition { .opacity }
    }

    extension Transition where Self == SymbolEffectTransition {
        /// A transition that applies the default symbol effect transition to
        /// symbol images within the inserted or removed view hierarchy —
        /// drawn as a fade (see ``SymbolEffectTransition``).
        public static var symbolEffect: SymbolEffectTransition {
            SymbolEffectTransition(effect: .appear, options: .default)
        }

        /// Creates a transition that applies the provided effect to symbol
        /// images within the inserted or removed view hierarchy — drawn as a
        /// fade (see ``SymbolEffectTransition``).
        ///
        /// - Parameter effect: the symbol effect value.
        /// - Returns: a new transition.
        public static func symbolEffect<T: SymbolEffect & TransitionSymbolEffect>(
            _ effect: T, options: SymbolEffectOptions = .default
        ) -> SymbolEffectTransition {
            SymbolEffectTransition(effect: effect, options: options)
        }
    }

    extension ContentTransition {
        /// A content transition that applies the default symbol effect
        /// transition to symbol images within the inserted or removed view
        /// hierarchy — drawn as ``ContentTransition/opacity``, a cross-fade:
        /// SF Symbols' replace is one symbol giving way to another, and in a
        /// cell that is one glyph dissolving into the next. Everything the
        /// modifier wraps dissolves, as it does under `.opacity`.
        public static var symbolEffect: ContentTransition { .opacity }

        /// Creates a content transition that applies the symbol Replace
        /// animation to symbol images that it is applied to — drawn as
        /// ``ContentTransition/opacity`` (see ``symbolEffect``); the replace's
        /// direction and options are not drawn.
        ///
        /// - Returns: a new content transition.
        public static func symbolEffect<T: ContentTransitionSymbolEffect & SymbolEffect>(
            _ effect: T, options: SymbolEffectOptions = .default
        ) -> ContentTransition {
            .opacity
        }
    }
#endif
