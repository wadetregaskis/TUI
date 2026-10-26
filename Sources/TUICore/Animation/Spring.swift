//  🖥️ TUI — A Terminal UI framework for Swift
//  Spring.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A representation of a spring's motion.
///
/// Use this type to convert between different representations of spring
/// parameters:
///
/// ```swift
/// let spring = Spring(duration: 0.5, bounce: 0.3)
/// let (mass, stiffness, damping) = (spring.mass, spring.stiffness, spring.damping)
/// // (1.0, 157.9, 17.6)
///
/// let spring2 = Spring(mass: 1, stiffness: 100, damping: 10)
/// let (duration, bounce) = (spring2.duration, spring2.bounce)
/// // (0.63, 0.5)
/// ```
///
/// You can also use it to query for a spring's position and its other
/// properties for a given set of inputs:
///
/// ```swift
/// func unitPosition(time: TimeInterval) -> Double {
///     let spring = Spring(duration: 0.5, bounce: 0.3)
///     return spring.value(target: 1.0, time: time)
/// }
/// ```
///
/// Every number here is SwiftUI's, measured on its own `Spring` — including
/// two of its quirks, kept so that ported arithmetic agrees: an overdamped
/// spring's `stiffness` reads `(2ζ² − 1)` times the stiffness it moves with,
/// and the settling duration of a critically or overdamped spring is found in
/// steps of a tenth of a second. The motion itself is the closed form of a
/// damped harmonic oscillator, which is also what TUI's spring animations
/// are drawn with.
public struct Spring: Hashable, Sendable {
    /// The time for one undamped oscillation, the spring's pace.
    private let pace: Double

    /// The damping ratio: 1 is critical, below it bounces, above it is slower.
    private let ratio: Double

    /// The mass, which scales the force the spring reports.
    private let springMass: Double

    private init(pace: Double, ratio: Double, mass: Double) {
        self.pace = pace
        self.ratio = ratio
        self.springMass = mass
    }

    // MARK: - Making one

    /// Creates a spring with the specified duration and bounce.
    ///
    /// - Parameters:
    ///   - duration: Defines the pace of the spring. This is approximately
    ///     equal to the settling duration, but for springs with very large
    ///     bounce values, will be the duration of the period of oscillation
    ///     for the spring.
    ///   - bounce: How bouncy the spring should be. A value of 0 indicates no
    ///     bounces (a critically damped spring), positive values indicate
    ///     increasing amounts of bounciness up to a maximum of 1.0
    ///     (corresponding to undamped oscillation), and negative values
    ///     indicate overdamped springs with a minimum value of -1.0.
    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) {
        // Above 1 is clamped, as SwiftUI does. At -1 and below SwiftUI's
        // ratio is infinite or NaN; this stops a hair short, an overdamped
        // spring so slow it never visibly arrives, rather than a NaN that
        // reaches a cell coordinate.
        let clamped = min(1, max(-0.999, bounce))
        self.init(
            pace: duration, ratio: clamped >= 0 ? 1 - clamped : 1 / (1 + clamped), mass: 1)
    }

    /// Creates a spring with the specified response and damping ratio.
    ///
    /// - Parameters:
    ///   - response: Defines the stiffness of the spring as an approximate
    ///     duration in seconds.
    ///   - dampingRatio: Defines the amount of drag applied as a fraction of
    ///     the amount needed to produce critical damping.
    public init(response: Double, dampingRatio: Double) {
        self.init(pace: response, ratio: dampingRatio, mass: 1)
    }

    /// Creates a spring with the specified mass, stiffness, and damping.
    ///
    /// - Parameters:
    ///   - mass: Specifies that property of the object attached to the end of
    ///     the spring.
    ///   - stiffness: The corresponding spring coefficient.
    ///   - damping: Defines how the spring's motion should be damped due to
    ///     the forces of friction.
    ///   - allowOverDamping: A value of true specifies that over-damping
    ///     should be allowed when appropriate based on the other inputs, and a
    ///     value of false specifies that such cases should instead be treated
    ///     as critically damped.
    public init(
        mass: Double = 1.0, stiffness: Double, damping: Double, allowOverDamping: Bool = false
    ) {
        let omega = (stiffness / mass).squareRoot()
        let ratio = damping / (2 * (stiffness * mass).squareRoot())
        self.init(
            pace: 2 * Double.pi / omega, ratio: allowOverDamping ? ratio : min(ratio, 1),
            mass: mass)
    }

    /// Creates a spring with the specified duration and damping ratio.
    ///
    /// - Parameters:
    ///   - settlingDuration: The approximate time it will take for the
    ///     spring to come to rest.
    ///   - dampingRatio: The amount of drag applied as a fraction of the
    ///     amount needed to produce critical damping. Above 1 is treated as 1.
    ///   - epsilon: The threshold for how small all subsequent values need to
    ///     be before the spring is considered to have settled.
    ///
    /// The spring is solved from SwiftUI's own relation (measured), which is
    /// not the one ``settlingDuration`` answers by: as there, the spring made
    /// here reports a somewhat longer settling duration than it was asked
    /// for.
    public init(settlingDuration: TimeInterval, dampingRatio: Double, epsilon: Double = 0.001) {
        let ratio = min(dampingRatio, 1)
        let decay: Double  // ζω₀ · settlingDuration, or ω₀ · settlingDuration when critical
        if ratio < 1 {
            decay = log(ratio / ((1 - ratio * ratio).squareRoot() * epsilon)) / ratio
        } else {
            // (1 + x)·e^(−x) = ε: the critically damped envelope's crossing.
            decay = Self.crossing { x in (1 + x) * exp(-x) - epsilon }
        }
        self.init(pace: 2 * Double.pi * settlingDuration / decay, ratio: ratio, mass: 1)
    }

    /// A smooth spring with a predefined duration and no bounce.
    public static var smooth: Self { smooth() }

    /// A smooth spring with a predefined duration and no bounce that can be
    /// tuned.
    ///
    /// - Parameters:
    ///   - duration: The perceptual duration, which defines the pace of the
    ///     spring.
    ///   - extraBounce: How much additional bounce should be added to the
    ///     base bounce of 0.
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Self {
        Self(duration: duration, bounce: extraBounce)
    }

    /// A spring with a predefined duration and small amount of bounce that
    /// feels more snappy.
    public static var snappy: Self { snappy() }

    /// A spring with a predefined duration and small amount of bounce that
    /// feels more snappy and can be tuned.
    ///
    /// - Parameters:
    ///   - duration: The perceptual duration, which defines the pace of the
    ///     spring.
    ///   - extraBounce: How much additional bounciness should be added to the
    ///     base bounce of 0.15.
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Self {
        Self(duration: duration, bounce: 0.15 + extraBounce)
    }

    /// A spring with a predefined duration and higher amount of bounce.
    public static var bouncy: Self { bouncy() }

    /// A spring with a predefined duration and higher amount of bounce that
    /// can be tuned.
    ///
    /// - Parameters:
    ///   - duration: The perceptual duration, which defines the pace of the
    ///     spring.
    ///   - extraBounce: How much additional bounce should be added to the
    ///     base bounce of 0.3.
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Self {
        Self(duration: duration, bounce: 0.3 + extraBounce)
    }

    // MARK: - Its parameters

    /// The perceptual duration, which defines the pace of the spring.
    public var duration: TimeInterval { pace }

    /// The stiffness of the spring, defined as an approximate duration in
    /// seconds.
    public var response: Double { pace }

    /// How bouncy the spring is: 0 for none, up to 1 for an undamped one,
    /// negative for an overdamped one.
    public var bounce: Double { ratio <= 1 ? 1 - ratio : 1 / ratio - 1 }

    /// The amount of drag applied, as a fraction of the amount needed to
    /// produce critical damping.
    public var dampingRatio: Double { ratio }

    /// The mass of the object attached to the end of the spring.
    public var mass: Double { springMass }

    /// The spring stiffness coefficient.
    ///
    /// Increasing the stiffness reduces the number of oscillations and will
    /// reduce the settling duration. Decreasing the stiffness increases the
    /// number of oscillations and will increase the settling duration.
    ///
    /// For an overdamped spring this is `(2ζ² − 1)` times the stiffness the
    /// spring moves with, as SwiftUI reports it (measured).
    public var stiffness: Double {
        let natural = springMass * (2 * Double.pi / pace) * (2 * Double.pi / pace)
        return ratio <= 1 ? natural : natural * (2 * ratio * ratio - 1)
    }

    /// Defines how the spring's motion should be damped due to the forces of
    /// friction.
    ///
    /// Reducing this value reduces the energy loss with each oscillation: the
    /// spring will overshoot its destination. Increasing the value increases
    /// the energy loss with each duration: there will be fewer and smaller
    /// oscillations.
    public var damping: Double { 4 * Double.pi * springMass * ratio / pace }

    /// The estimated duration required for the spring system to be
    /// considered at rest.
    ///
    /// This uses a `target` of 1.0, an `initialVelocity` of 0, and an
    /// `epsilon` of 0.001.
    public var settlingDuration: TimeInterval {
        settlingDuration(target: 1.0, initialVelocity: 0.0, epsilon: 0.001)
    }

    // MARK: - Its motion

    /// The undamped angular frequency, ω₀.
    private var omega: Double { 2 * Double.pi / pace }

    /// Calculates the value of the spring at a given time given a target
    /// amount of change.
    public func value<V: VectorArithmetic>(
        target: V, initialVelocity: V = .zero, time: TimeInterval
    ) -> V {
        let motion = SpringMotion(omega: omega, ratio: ratio, time: time)
        // From rest at zero: displaced by −target, moving at the velocity.
        var value = target
        value.scale(by: 1 - motion.displacement)
        var moving = initialVelocity
        moving.scale(by: motion.impulse)
        return value + moving
    }

    /// Calculates the velocity of the spring at a given time given a target
    /// amount of change.
    public func velocity<V: VectorArithmetic>(
        target: V, initialVelocity: V = .zero, time: TimeInterval
    ) -> V {
        let motion = SpringMotion(omega: omega, ratio: ratio, time: time)
        var value = target
        value.scale(by: -motion.displacementVelocity)
        var moving = initialVelocity
        moving.scale(by: motion.impulseVelocity)
        return value + moving
    }

    /// Updates the current value and velocity of a spring.
    ///
    /// - Parameters:
    ///   - value: The current value of the spring.
    ///   - velocity: The current velocity of the spring.
    ///   - target: The target that `value` is moving towards.
    ///   - deltaTime: The amount of time that has passed since the spring was
    ///     at the position specified by `value`.
    public func update<V: VectorArithmetic>(
        value: inout V, velocity: inout V, target: V, deltaTime: TimeInterval
    ) {
        let remaining = target - value
        let moved = self.value(target: remaining, initialVelocity: velocity, time: deltaTime)
        velocity = self.velocity(target: remaining, initialVelocity: velocity, time: deltaTime)
        value += moved
    }

    /// Calculates the force upon the spring given a current position, target,
    /// and velocity amount of change.
    ///
    /// This value is in units of the vector type per second squared.
    public func force<V: VectorArithmetic>(target: V, position: V, velocity: V) -> V {
        var pull = target - position
        pull.scale(by: stiffness)
        var drag = velocity
        drag.scale(by: damping)
        return pull - drag
    }

    /// The estimated duration required for the spring system to be
    /// considered at rest.
    ///
    /// The `epsilon` value specifies the threshold for how small all
    /// subsequent values need to be before the spring is considered to have
    /// settled.
    public func settlingDuration<V: VectorArithmetic>(
        target: V, initialVelocity: V = .zero, epsilon: Double
    ) -> TimeInterval {
        let displacement = target.magnitudeSquared.squareRoot()
        guard displacement > 0 || initialVelocity.magnitudeSquared > 0 else { return 0 }
        guard ratio > 0 else { return .infinity }
        if ratio < 1 {
            // An exponential envelope over both parts of the motion, as
            // SwiftUI bounds it (measured): |y₀| + |v₀ + ζω₀·y₀|.
            var pushed = initialVelocity
            var held = target
            held.scale(by: -ratio * omega)
            pushed += held
            let amplitude = displacement + pushed.magnitudeSquared.squareRoot()
            return max(0, log(amplitude / epsilon) / (ratio * omega))
        }
        // Critically and overdamped: the first tenth of a second at which
        // the spring is within `epsilon`, as SwiftUI searches for it.
        for step in 1...100_000 {
            let time = Double(step) / 10
            let motion = SpringMotion(omega: omega, ratio: ratio, time: time)
            var away = target
            away.scale(by: -motion.displacement)
            var moving = initialVelocity
            moving.scale(by: motion.impulse)
            away += moving
            if away.magnitudeSquared.squareRoot() < epsilon { return time }
        }
        return .infinity
    }

    /// Calculates the value of the spring at a given time for a starting and
    /// ending value for the spring to travel.
    @MainActor
    public func value<V: Animatable>(
        fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval
    ) -> V {
        var result = fromValue
        result.animatableData =
            fromValue.animatableData
            + value(
                target: toValue.animatableData - fromValue.animatableData,
                initialVelocity: initialVelocity.animatableData, time: time)
        return result
    }

    /// Calculates the velocity of the spring at a given time given a starting
    /// and ending value for the spring to travel.
    @MainActor
    public func velocity<V: Animatable>(
        fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval
    ) -> V {
        var result = fromValue
        result.animatableData = velocity(
            target: toValue.animatableData - fromValue.animatableData,
            initialVelocity: initialVelocity.animatableData, time: time)
        return result
    }

    /// Calculates the force upon the spring given a current position,
    /// velocity, and divisor from the starting and end values for the spring
    /// to travel.
    ///
    /// The position is relative to `fromValue`, as SwiftUI takes it
    /// (measured): the force at the start of the travel is the force at a
    /// `position` of zero.
    @MainActor
    public func force<V: Animatable>(fromValue: V, toValue: V, position: V, velocity: V) -> V {
        var result = fromValue
        result.animatableData = force(
            target: toValue.animatableData - fromValue.animatableData,
            position: position.animatableData, velocity: velocity.animatableData)
        return result
    }

    /// The estimated duration required for the spring system to be
    /// considered at rest.
    @MainActor
    public func settlingDuration<V: Animatable>(
        fromValue: V, toValue: V, initialVelocity: V, epsilon: Double
    ) -> TimeInterval {
        settlingDuration(
            target: toValue.animatableData - fromValue.animatableData,
            initialVelocity: initialVelocity.animatableData, epsilon: epsilon)
    }

    /// The root of a decreasing `excess` between 0 and 100, by bisection.
    private static func crossing(_ excess: (Double) -> Double) -> Double {
        var low = 0.0
        var high = 100.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if excess(mid) > 0 { low = mid } else { high = mid }
        }
        return high
    }
}

// MARK: - The closed form

/// A damped harmonic oscillator's motion at one instant, as the two responses
/// every motion is a sum of: how much of a starting displacement remains
/// (`displacement`), and where a unit starting velocity has carried it
/// (`impulse`) — with their rates of change.
///
/// One formula for the whole framework: ``Spring``'s values and the spring
/// curve an ``Animation`` is drawn with are both made of these.
struct SpringMotion {
    /// The fraction of a starting displacement still there.
    var displacement: Double
    /// Its rate of change.
    var displacementVelocity: Double
    /// The displacement a unit starting velocity has produced.
    var impulse: Double
    /// Its rate of change.
    var impulseVelocity: Double

    /// The motion `time` seconds after the start, of a spring with undamped
    /// angular frequency `omega` and damping ratio `ratio`.
    ///
    /// A band either side of a ratio of 1 is critical: the under- and
    /// overdamped forms divide by a quantity that vanishes there.
    init(omega: Double, ratio: Double, time: Double) {
        guard time > 0, omega > 0 else {
            self.init(displacement: 1, displacementVelocity: 0, impulse: 0, impulseVelocity: 1)
            return
        }
        if ratio < Self.criticalBand {
            let damped = omega * (1 - ratio * ratio).squareRoot()
            let decay = exp(-ratio * omega * time)
            let (sine, cosine) = (sin(damped * time), cos(damped * time))
            self.init(
                displacement: decay * (cosine + (ratio * omega / damped) * sine),
                displacementVelocity: -decay * (omega * omega / damped) * sine,
                impulse: decay * sine / damped,
                impulseVelocity: decay * (cosine - (ratio * omega / damped) * sine))
        } else if ratio <= 1 / Self.criticalBand {
            let decay = exp(-omega * time)
            self.init(
                displacement: decay * (1 + omega * time),
                displacementVelocity: -decay * omega * omega * time,
                impulse: decay * time,
                impulseVelocity: decay * (1 - omega * time))
        } else {
            let root = omega * (ratio * ratio - 1).squareRoot()
            let slow = -ratio * omega + root
            let fast = -ratio * omega - root
            let (slowDecay, fastDecay) = (exp(slow * time), exp(fast * time))
            let spread = slow - fast
            self.init(
                displacement: (slow * fastDecay - fast * slowDecay) / spread,
                displacementVelocity: slow * fast * (fastDecay - slowDecay) / spread,
                impulse: (slowDecay - fastDecay) / spread,
                impulseVelocity: (slow * slowDecay - fast * fastDecay) / spread)
        }
    }

    private init(
        displacement: Double, displacementVelocity: Double, impulse: Double, impulseVelocity: Double
    ) {
        self.displacement = displacement
        self.displacementVelocity = displacementVelocity
        self.impulse = impulse
        self.impulseVelocity = impulseVelocity
    }

    /// How close to a ratio of 1 counts as critically damped. See
    /// `AnimationCurve`'s spring for why it is a band.
    static let criticalBand = 0.9999
}
