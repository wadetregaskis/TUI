//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Animation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// How a value changes over time when it changes inside ``withAnimation(_:_:)``
/// or under ``View/animation(_:value:)``.
///
/// ```swift
/// withAnimation(.easeInOut(duration: 0.4)) { isExpanded.toggle() }
/// ```
///
/// An `Animation` is a pure description — a curve, a duration, and the
/// modifiers stacked on it. It holds no state and starts nothing; what turns
/// one into movement is a change to an ``Animatable`` value while it is in
/// force. That separation is what lets the same value be a `static let`, be
/// compared, and — the part that matters in a terminal — be asked in advance
/// what its whole cycle looks like.
///
/// ## What it costs
///
/// A finite animation costs one render pass per frame **for its duration**: a
/// 0.4 s ease is eight or nine passes and then nothing. A
/// ``repeatForever(autoreverses:)`` animation would cost that forever, so the
/// framework serves it differently where it can — by rendering the cycle once
/// and handing the run loop finished frames to replay (``AnimatedCellRun``).
/// See <doc:AnimatingYourOwnView>.
public struct Animation: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// How many times, and in which directions, the curve is played, and how
    /// long each pass waits before it plays.
    ///
    /// `passDelay` is a ``delay(_:)`` written BEFORE the repeat, which SwiftUI
    /// repeats with the pass (measured, `Tools/SwiftUIProbes/Animation curves,
    /// springs and keyframes/p11.swift`): every pass, a reversed one too,
    /// holds where it starts for that long, before ``speed(_:)``. A `Float`
    /// and an `Int32`, for the bytes: with them the enum is the nine bytes the
    /// pass count and its flag took alone, where an `Int` and a `Double`
    /// would add a word to every `Animation`, `Transaction` and `Binding`.
    /// Seven significant digits are plenty for a wait, and two billion passes
    /// for a count.
    enum Repeat: Sendable, Equatable, Hashable {
        /// A number of one-way passes. `autoreverses` plays every second pass
        /// backwards, so `.count(2, autoreverses: true)` ends where it started.
        /// A single pass has no `passDelay`: its delay leads (`delayInterval`).
        case count(Int32, passDelay: Float, autoreverses: Bool)

        /// Passes without end, alternating direction when `autoreverses`.
        case forever(passDelay: Float, autoreverses: Bool)

        /// The wait before every pass, before ``Animation/speed(_:)``.
        var passDelay: TimeInterval {
            switch self {
            case .count(_, let delay, _), .forever(let delay, _): TimeInterval(delay)
            }
        }
    }

    /// The shape of one pass.
    let curve: AnimationCurve

    /// When ``logicallyComplete(after:)`` says the animation logically
    /// completes, counted from its start and before ``speed(_:)``; negative
    /// for "when it naturally does".
    ///
    /// A `Float`, and declared here, for the bytes: the curve ends four bytes
    /// short of a word, and a 4-byte field fills that gap where a `Double`
    /// would have added a word to every `Animation` — and so to every
    /// `Transaction`, and every `Binding`. A completion time does not need more
    /// than seven significant digits.
    let logicalCompletion: Float

    /// How long one pass takes, before ``speed(_:)``.
    ///
    /// For a spring this is the settling time, not the `duration:` argument —
    /// that one names the spring's *pace* (its natural period), and the spring
    /// keeps moving after it.
    let passDuration: TimeInterval

    /// How long to wait before the first pass, before ``speed(_:)`` — a
    /// delay written after one is stored multiplied by it, so the speed's
    /// division gives it back unscaled. A delay written before a repeat is
    /// not here but in ``Repeat/passDelay``.
    let delayInterval: TimeInterval

    /// The rate multiplier. 2 runs it twice as fast.
    let speedFactor: Double

    /// How the pass repeats.
    let repeatMode: Repeat

    init(
        curve: AnimationCurve,
        passDuration: TimeInterval,
        delayInterval: TimeInterval = 0,
        speedFactor: Double = 1,
        logicalCompletion: TimeInterval = -1,
        repeatMode: Repeat = .count(1, passDelay: 0, autoreverses: false)
    ) {
        self.curve = curve
        self.passDuration = max(0, passDuration)
        self.delayInterval = max(0, delayInterval)
        self.speedFactor = speedFactor > 0 ? speedFactor : 1
        self.logicalCompletion = logicalCompletion.isNaN ? -1 : Float(logicalCompletion)
        self.repeatMode = repeatMode
    }

    /// This animation with some of its modifiers replaced — the one place
    /// every modifier rebuilds it, so a new field cannot be dropped by one.
    private func with(
        delayInterval: TimeInterval? = nil, speedFactor: Double? = nil,
        logicalCompletion: TimeInterval? = nil, repeatMode: Repeat? = nil
    ) -> Self {
        Self(
            curve: curve, passDuration: passDuration,
            delayInterval: delayInterval ?? self.delayInterval,
            speedFactor: speedFactor ?? self.speedFactor,
            logicalCompletion: logicalCompletion ?? TimeInterval(self.logicalCompletion),
            repeatMode: repeatMode ?? self.repeatMode)
    }
}

// MARK: - Bézier curves

extension Animation {
    /// The default duration, in seconds, of every curve that does not name one.
    ///
    /// Matches SwiftUI's, so `.easeInOut` means the same length of time in both.
    public static let defaultDuration: TimeInterval = 0.35

    /// The animation to use when none is named, as `withAnimation { … }`
    /// with no argument does: SwiftUI's, a ``spring`` at the default pace
    /// with no bounce. It is 92% of the way at 0.35 s and makes its last
    /// visible change at about 0.84 s.
    ///
    /// Apple documents `default` as a spring of response 0.55, but the
    /// curve SwiftUI draws on macOS 15.8 is the 0.5 one, ``spring`` (measured
    /// frame by frame; the probe is the 2026-10-14 `animation-default` one).
    /// Before macOS 14 SwiftUI's default was an ease-in-out, as TUIkit's was.
    public static let `default` = Animation.spring

    /// A constant rate over `duration`.
    public static func linear(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0, p1y: 0, p2x: 1, p2y: 1), passDuration: duration)
    }

    /// A constant rate over ``defaultDuration``.
    public static var linear: Animation { linear(duration: defaultDuration) }

    /// Starts slowly and accelerates.
    public static func easeIn(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0.42, p1y: 0, p2x: 1, p2y: 1), passDuration: duration)
    }

    /// Starts slowly and accelerates, over ``defaultDuration``.
    public static var easeIn: Animation { easeIn(duration: defaultDuration) }

    /// Starts quickly and decelerates.
    public static func easeOut(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0, p1y: 0, p2x: 0.58, p2y: 1), passDuration: duration)
    }

    /// Starts quickly and decelerates, over ``defaultDuration``.
    public static var easeOut: Animation { easeOut(duration: defaultDuration) }

    /// Eases in and out of the change.
    public static func easeInOut(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0.42, p1y: 0, p2x: 0.58, p2y: 1), passDuration: duration)
    }

    /// Eases in and out of the change, over ``defaultDuration``.
    public static var easeInOut: Animation { easeInOut(duration: defaultDuration) }

    /// A cubic Bézier through `(0, 0)`, `(p1x, p1y)`, `(p2x, p2y)` and `(1, 1)`
    /// — the same parameterisation as CSS `cubic-bezier`.
    public static func timingCurve(
        _ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
        duration: TimeInterval = defaultDuration
    ) -> Animation {
        Animation(
            curve: .bezier(p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y), passDuration: duration)
    }
}

// MARK: - Springs

extension Animation {
    /// A spring with the given pace and springiness.
    ///
    /// - Parameters:
    ///   - duration: The spring's *pace* — the period of its undamped
    ///     oscillation — not how long it moves for. A bouncy spring is still
    ///     settling well after it.
    ///   - bounce: How springy. `0` is the fastest approach that does not
    ///     overshoot; positive values overshoot and oscillate; negative values
    ///     are sluggish. Clamped to `-1...1`.
    ///   - blendDuration: The duration in seconds over which to interpolate
    ///     changes to the duration. See ``spring(_:blendDuration:)``.
    public static func spring(
        duration: TimeInterval = 0.5, bounce: Double = 0, blendDuration: Double = 0
    ) -> Animation {
        spring(Spring(duration: duration, bounce: bounce), blendDuration: blendDuration)
    }

    /// A persistent spring animation.
    ///
    /// When mixed with other `spring()` or `interactiveSpring()` animations on
    /// the same property, each animation will be replaced by their successor,
    /// preserving velocity from one animation to the next. Optionally blends
    /// the duration values between springs over a time period.
    ///
    /// TUIkit's springs are closed-form functions of elapsed time. A change
    /// that retargets one mid-flight starts the next from where its picture
    /// is, at the velocity it was moving, as SwiftUI's merge does; durations
    /// are not blended, so `blendDuration` has nothing to blend.
    ///
    /// - Parameters:
    ///   - spring: A description of the spring's motion.
    ///   - blendDuration: The duration in seconds over which to interpolate
    ///     changes to the duration.
    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0.0) -> Animation {
        Animation(spring: spring, initialVelocity: 0, merges: true)
    }

    /// A persistent spring animation, by response and damping fraction.
    ///
    /// - Parameters:
    ///   - response: The stiffness of the spring, defined as an approximate
    ///     duration in seconds. A value of zero requests an infinitely-stiff
    ///     spring, suitable for driving interactive animations.
    ///   - dampingFraction: The amount of drag applied to the value being
    ///     animated, as a fraction of an estimate of amount needed to produce
    ///     critical damping.
    ///   - blendDuration: The duration in seconds over which to interpolate
    ///     changes to the response value of the spring.
    @_disfavoredOverload
    public static func spring(
        response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: TimeInterval = 0
    ) -> Animation {
        spring(Spring(response: response, dampingRatio: dampingFraction), blendDuration: blendDuration)
    }

    /// A spring at the default pace, with no bounce.
    public static var spring: Animation { spring() }

    /// A convenience for a ``spring(response:dampingFraction:blendDuration:)``
    /// with a lower response value, intended for driving interactive
    /// animations.
    ///
    /// SwiftUI tunes these for a pointer that is continuously retargeting the
    /// spring. A terminal's pointer reports a cell at a time, so here they are
    /// the quick springs their numbers describe, carrying their velocity into
    /// each retarget as any spring does.
    @_disfavoredOverload
    public static func interactiveSpring(
        response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: TimeInterval = 0.25
    ) -> Animation {
        spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }

    /// A convenience for a ``spring(duration:bounce:blendDuration:)`` with a
    /// short pace, intended for driving interactive animations.
    public static var interactiveSpring: Animation { interactiveSpring() }

    /// A convenience for a ``spring(duration:bounce:blendDuration:)`` with a
    /// short pace and a little bounce, intended for driving interactive
    /// animations.
    ///
    /// - Parameters:
    ///   - duration: The perceptual duration, which defines the pace of the
    ///     spring.
    ///   - extraBounce: How much additional bounce should be added to the base
    ///     bounce of 0.15.
    ///   - blendDuration: The duration in seconds over which to interpolate
    ///     changes to the duration.
    public static func interactiveSpring(
        duration: TimeInterval = 0.15, extraBounce: Double = 0.0, blendDuration: TimeInterval = 0.25
    ) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce, blendDuration: blendDuration)
    }

    /// An interpolating spring animation that uses a damped spring model to
    /// produce values in the range [0, 1] that are then used to interpolate
    /// within the [from, to] range of the animated property.
    ///
    /// Unlike ``spring(_:blendDuration:)`` it never merges: a change that
    /// arrives while it runs starts another animation beside it, and the two
    /// ADD, so the motion already under way carries on. The starting velocity
    /// is honoured, in the closed form, for the change it is given to.
    ///
    /// - Parameters:
    ///   - spring: A description of the spring's motion.
    ///   - initialVelocity: The initial velocity of the spring, as a value in
    ///     the range [0, 1] representing the magnitude of the value being
    ///     animated.
    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0.0) -> Animation {
        Animation(spring: spring, initialVelocity: initialVelocity, merges: false)
    }

    /// An interpolating spring animation, by mass, stiffness and damping —
    /// see ``interpolatingSpring(_:initialVelocity:)``. Overdamping is
    /// allowed.
    public static func interpolatingSpring(
        mass: Double = 1.0, stiffness: Double, damping: Double, initialVelocity: Double = 0.0
    ) -> Animation {
        interpolatingSpring(
            Spring(mass: mass, stiffness: stiffness, damping: damping, allowOverDamping: true),
            initialVelocity: initialVelocity)
    }

    /// An interpolating spring animation, by pace and bounce — see
    /// ``interpolatingSpring(_:initialVelocity:)``.
    public static func interpolatingSpring(
        duration: TimeInterval = 0.5, bounce: Double = 0.0, initialVelocity: Double = 0.0
    ) -> Animation {
        interpolatingSpring(Spring(duration: duration, bounce: bounce), initialVelocity: initialVelocity)
    }

    /// An interpolating spring animation at the default pace, with no
    /// bounce.
    public static var interpolatingSpring: Animation { interpolatingSpring() }

    /// The animation `spring` moves with, starting at `initialVelocity` (in
    /// units of the whole change per second), and taking over a change it
    /// interrupts where it `merges`.
    ///
    /// The one place a ``Spring`` becomes a curve. Its pace becomes the
    /// angular frequency, and a pace of zero or a ratio no number describes
    /// is an instant change rather than a NaN on its way to a cell.
    init(spring: Spring, initialVelocity: Double, merges: Bool) {
        let ratio = spring.dampingRatio
        let omega = spring.response > 0 && spring.response.isFinite ? 2 * Double.pi / spring.response : 0
        let zeta = ratio.isFinite ? max(0, ratio) : 1
        let velocity = initialVelocity.isFinite ? initialVelocity : 0
        self.init(
            curve: .spring(omega: omega, zeta: zeta, initialVelocity: velocity, merges: merges),
            passDuration: AnimationCurve.springSettleDuration(
                omega: omega, zeta: zeta, initialVelocity: velocity))
    }

    /// This animation starting with `velocity` — in whole changes per second,
    /// as a spring's initial velocity is — where it is a spring with nothing of
    /// TUIkit's around it (no delay, speed, repeat or logical completion), as
    /// a merge continues one (``AnimationStore``); any other as it is.
    package func carrying(velocity: Double) -> Animation {
        guard case .spring(let omega, let zeta, _, let merges) = curve, velocity.isFinite, delayInterval == 0,
            speedFactor == 1, logicalCompletion < 0, case .count(1, _, _) = repeatMode
        else { return self }
        return Animation(
            curve: .spring(omega: omega, zeta: zeta, initialVelocity: velocity, merges: merges),
            passDuration: AnimationCurve.springSettleDuration(omega: omega, zeta: zeta, initialVelocity: velocity))
    }

    /// A spring with no bounce — the one to reach for when a change should feel
    /// physical but not playful.
    public static var smooth: Animation { smooth() }

    /// ``smooth`` with an explicit pace, and optional bounce added.
    public static func smooth(
        duration: TimeInterval = 0.5, extraBounce: Double = 0
    ) -> Animation {
        spring(duration: duration, bounce: extraBounce)
    }

    /// A spring that settles quickly with a small overshoot.
    public static var snappy: Animation { snappy() }

    /// ``snappy`` with an explicit pace, and optional bounce added.
    public static func snappy(
        duration: TimeInterval = 0.5, extraBounce: Double = 0
    ) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    /// A spring with a pronounced overshoot.
    public static var bouncy: Animation { bouncy() }

    /// ``bouncy`` with an explicit pace, and optional bounce added.
    public static func bouncy(
        duration: TimeInterval = 0.5, extraBounce: Double = 0
    ) -> Animation {
        spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}

// MARK: - Modifiers

extension Animation {
    /// This animation, started `delay` seconds later.
    ///
    /// Composed as SwiftUI's is, each modifier wrapping the animation before
    /// it (measured, `Tools/SwiftUIProbes/Animation curves, springs and
    /// keyframes/p10.swift` and `p11.swift`): a delay written before
    /// ``repeatCount(_:autoreverses:)`` or ``repeatForever(autoreverses:)``
    /// comes again before every pass, reversed ones too, and one written
    /// after them comes once; a delay written before ``speed(_:)`` is scaled
    /// by it, and one written after is not.
    public func delay(_ delay: TimeInterval) -> Animation {
        // Stored before the speed, as every time here is: a delay written
        // after a speed is outside it, so it is stored multiplied by it.
        let stored = delay * speedFactor
        return with(
            delayInterval: delayInterval + stored,
            // A completion time is counted from the start, which moved.
            logicalCompletion: logicalCompletion < 0 ? nil : TimeInterval(logicalCompletion) + stored)
    }

    /// This animation, run `speed` times as fast. A delay written before it
    /// scales with it, as it does in SwiftUI.
    public func speed(_ speed: Double) -> Animation {
        with(speedFactor: speedFactor * speed)
    }

    /// Causes the animation to report logical completion after the specified
    /// duration, if it has not already logically completed.
    ///
    /// Note that the indicated duration will not cause the animation to
    /// continue running after the base animation has fully completed.
    ///
    /// If the animation is removed before the given duration is reached,
    /// logical completion will be reported immediately.
    ///
    /// The duration is counted from the animation's start, delay included, and
    /// scales with ``speed(_:)`` as the delay does.
    ///
    /// - Parameter duration: The duration after which the animation should
    ///   report that it is logically complete.
    /// - Returns: An animation that reports logical completion after the given
    ///   duration.
    public func logicallyComplete(after duration: TimeInterval) -> Animation {
        with(logicalCompletion: max(0, duration))
    }

    /// This animation, played `repeatCount` times.
    ///
    /// The count is *passes*, not round trips: with `autoreverses`, every second
    /// pass runs backwards, so an even count ends where it started and an odd
    /// one ends at the target.
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        let passes = Int32(clamping: max(1, repeatCount))
        // One pass is the animation as it was, its delay still leading.
        guard passes > 1 else { return with(repeatMode: .count(1, passDelay: 0, autoreverses: autoreverses)) }
        return repeating(.count(passes, passDelay: passDelayIncludingLead, autoreverses: autoreverses))
    }

    /// This animation, played until something stops it.
    ///
    /// - Important: Nothing stops it — an animation has no end, and the value it
    ///   animates never arrives. This is the shape of a decoration (a pulse, a
    ///   blink), not of a change. Where the framework can, it serves one by
    ///   pre-rendering the cycle and replaying it (see ``AnimatedCellRun``);
    ///   where it cannot, it re-renders the affected subtree for as long as the
    ///   view is on screen.
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        repeating(.forever(passDelay: passDelayIncludingLead, autoreverses: autoreverses))
    }

    /// The wait before each pass once this animation repeats: its leading
    /// delay, which the repeat now plays before every pass, after any wait it
    /// already had there. A repeat of a repeat replaces it, as it always has
    /// here; SwiftUI's own answer to one is erratic (p11, case 6).
    private var passDelayIncludingLead: Float {
        Float(repeatMode.passDelay + delayInterval)
    }

    /// This animation repeating as `mode` says, its leading delay moved into
    /// the pass.
    private func repeating(_ mode: Repeat) -> Animation {
        with(delayInterval: 0, repeatMode: mode)
    }
}

// MARK: - Evaluation

extension Animation {
    /// One pass, after ``speed(_:)``: unbounded for a custom animation not yet
    /// integrated as far as its end.
    public var effectivePassDuration: TimeInterval { (resolvedPassDuration ?? .infinity) / speedFactor }

    /// How long one pass takes, before ``speed(_:)``: ``passDuration`` — or, for
    /// a custom animation, its length once it has been integrated as far as its
    /// end, and `nil` before.
    var resolvedPassDuration: TimeInterval? {
        guard case .custom(let id) = curve else { return passDuration }
        return id.curve.knownDuration
    }

    /// The wait before the first pass, after ``speed(_:)``.
    public var effectiveDelay: TimeInterval { delayInterval / speedFactor }

    /// How long from the animation's start until it stops moving, or `nil` if it
    /// never does.
    ///
    /// A custom animation's is `nil` until it has been integrated as far as
    /// its end; ``isFinished(at:)`` integrates as far as it is asked.
    public var totalDuration: TimeInterval? {
        switch repeatMode {
        case .count(let n, _, _):
            resolvedPassDuration.map { effectiveDelay + ($0 + repeatMode.passDelay) / speedFactor * Double(n) }
        case .forever: nil
        }
    }

    /// How long from the animation's start until it LOGICALLY completes — the
    /// moment a ``AnimationCompletionCriteria/logicallyComplete`` completion
    /// fires — or `nil` if it never does.
    ///
    /// For a curve that is its end. For a spring it is the end of the last
    /// pass's PACE, the `duration:` the spring was made with: the value has
    /// all but arrived and what remains is its settling, the "long tail"
    /// SwiftUI's criterion describes. ``logicallyComplete(after:)`` can bring
    /// it forward, never past the end.
    public var logicalCompletionDuration: TimeInterval? {
        guard let total = totalDuration, case .count(let count, _, _) = repeatMode else { return nil }
        let passes = Double(count)
        let wait = repeatMode.passDelay
        var natural = total
        if case .spring(let omega, _, _, _) = curve, omega > 0 {
            let pace = min(passDuration, 2 * Double.pi / omega)
            natural = (delayInterval + (passDuration + wait) * (passes - 1) + wait + pace) / speedFactor
        } else if case .custom(let id) = curve, let pass = resolvedPassDuration,
            let logical = id.curve.logicalCompletionTime
        {
            // When the custom animation said so in its context, on its last pass.
            natural = (delayInterval + (pass + wait) * (passes - 1) + wait + logical) / speedFactor
        }
        guard logicalCompletion >= 0 else { return natural }
        return min(natural, TimeInterval(logicalCompletion) / speedFactor)
    }

    /// Whether this animation runs without end.
    public var repeatsForever: Bool {
        if case .forever = repeatMode { return true }
        return false
    }

    /// The length of the repeating cycle, for an animation that has one.
    ///
    /// Two passes when it autoreverses (out and back), one when it does not.
    /// `nil` for an animation that ends. This is what makes a repeating
    /// animation pre-renderable: a finite cycle can be sampled once and
    /// replayed.
    public var cyclePeriod: TimeInterval? {
        switch repeatMode {
        case .count: nil
        case .forever(let wait, let autoreverses):
            resolvedPassDuration.map { ($0 + TimeInterval(wait)) / speedFactor * (autoreverses ? 2 : 1) }
        }
    }

    /// How far the value has moved from its old value towards its new one,
    /// `elapsed` seconds after the animation started.
    ///
    /// `0` is entirely the old value and `1` entirely the new one. A spring
    /// **overshoots**: values above 1 are correct and mean the value has gone
    /// past its target and is on the way back.
    public func fraction(at elapsed: TimeInterval) -> Double {
        let time = (elapsed - effectiveDelay)
        guard time > 0 else { return 0 }
        let scaled = time * speedFactor
        let wait = repeatMode.passDelay
        // A custom animation that has not finished by now is on its first
        // pass, however it repeats: its pass lasts until it finishes.
        if case .custom(let id) = curve, id.curve.duration(within: max(0, scaled - wait)) == nil {
            return scaled <= wait ? 0 : id.curve.progress(at: scaled - wait)
        }
        let passDuration = resolvedPassDuration ?? 0
        // An instant pass jumps when its wait ends, or at once without one.
        guard passDuration > 0 else { return wait > 0 && scaled < wait ? 0 : 1 }

        // Each pass is its wait, then the curve.
        let pass = Int(scaled / (wait + passDuration))
        let into = scaled - Double(pass) * (wait + passDuration)
        let within = max(0, into - wait) / passDuration

        switch repeatMode {
        case .count(let n, _, let autoreverses):
            guard pass < Int(n) else {
                // Finished. An even number of autoreversing passes lands back
                // at the start; anything else lands on the target.
                return autoreverses && n.isMultiple(of: 2) ? 0 : 1
            }
            return value(atPass: pass, within: within, autoreverses: autoreverses, duration: passDuration)
        case .forever(_, let autoreverses):
            return value(atPass: pass, within: within, autoreverses: autoreverses, duration: passDuration)
        }
    }

    /// Whether the animation has stopped moving by `elapsed`.
    public func isFinished(at elapsed: TimeInterval) -> Bool {
        // A custom animation is integrated as far as `elapsed` to learn
        // whether its first pass has ended by then.
        if case .custom(let id) = curve {
            _ = id.curve.duration(within: max(0, (elapsed - effectiveDelay) * speedFactor - repeatMode.passDelay))
        }
        guard let totalDuration else { return false }
        return elapsed >= totalDuration
    }

    /// The curve's value on a given pass, reversing the odd ones when asked.
    ///
    /// A reversed pass runs the curve backwards *in time* — `curve(1 - within)`
    /// — rather than mirroring its output. For an asymmetric curve those differ,
    /// and time reversal is what "plays in reverse" means (and what Core
    /// Animation does).
    private func value(atPass pass: Int, within: Double, autoreverses: Bool, duration: TimeInterval) -> Double {
        let reversed = autoreverses && !pass.isMultiple(of: 2)
        return curve.value(
            atFraction: reversed ? 1 - within : within, duration: duration)
    }
}

// MARK: - Description

extension Animation {
    /// A source-shaped description of this animation, e.g.
    /// `"easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)"`.
    ///
    /// Written to read like the call that would build the same value, so a
    /// logged or `#expect`-printed animation says what it is rather than
    /// dumping its stored curve. The curve names follow the factories that
    /// produce them (``Animation/easeInOut(duration:)``,
    /// ``Animation/spring(duration:bounce:blendDuration:)``,
    /// ``Animation/timingCurve(_:_:_:_:duration:)``), and any repeat or delay
    /// is appended in modifier order, so the string round-trips by eye.
    public var description: String {
        var text = curveDescription
        // The wait before every pass is a delay written before the repeat,
        // and the speed scales it; the leading delay, written after both,
        // is already unscaled.
        if repeatMode.passDelay != 0 { text += ".delay(\(repeatMode.passDelay))" }
        if speedFactor != 1 { text += ".speed(\(speedFactor))" }
        if logicalCompletion >= 0 { text += ".logicallyComplete(after: \(logicalCompletion))" }
        switch repeatMode {
        case .count(1, _, _): break
        case .count(let n, _, let autoreverses):
            text += ".repeatCount(\(n), autoreverses: \(autoreverses))"
        case .forever(_, let autoreverses):
            text += ".repeatForever(autoreverses: \(autoreverses))"
        }
        if delayInterval != 0 { text += ".delay(\(effectiveDelay))" }
        return text
    }

    /// The factory call that would build ``curve`` at ``passDuration``.
    fileprivate var curveDescription: String {
        switch curve {
        case .custom(let id):
            return "Animation(\(id.curve.base))"
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            // Recognised by control points rather than remembered: nothing is
            // stored to say which factory built this, and it does not need to
            // be. An explicit `timingCurve(0.42, 0, 0.58, 1)` IS an ease-in-out
            // — the same animation by another spelling — so naming it one is
            // accurate rather than a guess.
            switch (p1x, p1y, p2x, p2y) {
            case (0, 0, 1, 1): return "linear(duration: \(passDuration))"
            case (0.42, 0, 1, 1): return "easeIn(duration: \(passDuration))"
            case (0, 0, 0.58, 1): return "easeOut(duration: \(passDuration))"
            case (0.42, 0, 0.58, 1): return "easeInOut(duration: \(passDuration))"
            default:
                return "timingCurve(\(p1x), \(p1y), \(p2x), \(p2y), duration: \(passDuration))"
            }
        case .circular(let curve):
            let name =
                switch curve {
                case .easeIn: ".circularEaseIn"
                case .easeOut: ".circularEaseOut"
                case .easeInOut: ".circularEaseInOut"
                case .easeOutIn: ".circularEaseInOut.inverse"
                }
            return "timingCurve(\(name), duration: \(passDuration))"
        case .spring(let omega, let zeta, let initialVelocity, let merges):
            // Inverted back through `spring(duration:bounce:)`'s own mapping.
            // This used to print the stored `omega`/`zeta`/`settles`, which no
            // factory accepts — the one spelling that cannot round-trip. A
            // merging spring's velocity is one a merge carried in, which no
            // factory spells either, so it goes unprinted.
            let duration = omega > 0 ? 2 * Double.pi / omega : 0
            let bounce = zeta <= 1 ? 1 - zeta : 1 / zeta - 1
            guard merges else {
                let velocity = initialVelocity == 0 ? "" : ", initialVelocity: \(initialVelocity)"
                return "interpolatingSpring(duration: \(Self.solved(duration)), "
                    + "bounce: \(Self.solved(bounce))\(velocity))"
            }
            return "spring(duration: \(Self.solved(duration)), bounce: \(Self.solved(bounce)))"
        }
    }

    /// A solved spring parameter, printed at six decimals.
    ///
    /// NOT cosmetic rounding of a stored number: `duration` and `bounce` are
    /// recovered by inverting the arithmetic the factory did, and that trip
    /// lands a unit in the last place away — `bounce: 0.15` comes back as
    /// 0.15000000000000002. Six decimals is finer than any pace or springiness
    /// anyone writes, and reads back as what they wrote.
    private static func solved(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        return "\((value * 1_000_000).rounded() / 1_000_000)"
    }
}

// MARK: - Debugging

extension Animation: CustomDebugStringConvertible, CustomReflectable {
    /// The description, marked as an animation: `Animation(easeInOut(duration:
    /// 0.35))`. SwiftUI prints its internal animator types here; neither
    /// string is a format to parse.
    public var debugDescription: String {
        "Animation(\(description))"
    }

    /// What the animation is made of, one child per part: the curve as the
    /// factory that builds it, the pass's length, and each modifier that
    /// differs from its default.
    public var customMirror: Mirror {
        var children: [(label: String?, value: Any)] = [
            ("curve", curveDescription), ("duration", passDuration),
        ]
        if delayInterval != 0 { children.append(("delay", delayInterval)) }
        if repeatMode.passDelay != 0 { children.append(("delayEachPass", repeatMode.passDelay)) }
        if speedFactor != 1 { children.append(("speed", speedFactor)) }
        if logicalCompletion >= 0 { children.append(("logicallyCompleteAfter", logicalCompletion)) }
        switch repeatMode {
        case .count(1, _, _): break
        case .count(let passes, _, let autoreverses):
            children.append(("repeatCount", Int(passes)))
            children.append(("autoreverses", autoreverses))
        case .forever(_, let autoreverses):
            children.append(("repeatsForever", true))
            children.append(("autoreverses", autoreverses))
        }
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

// MARK: - Value Hash

/// A trivial non-generic enum, internal, whose cases only this module builds:
/// every byte of every value is written, so the per-pass memos' value hash
/// reads it whole. See `_AllBytesDefined`.
extension Animation.Repeat: _AllBytesDefined {}
