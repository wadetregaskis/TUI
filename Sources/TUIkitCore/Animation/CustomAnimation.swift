//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomAnimation.swift
//
//  SwiftUI's `CustomAnimation` family: an animation curve of the app's own,
//  integrated forward from a state it keeps between calls.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - The protocol

/// A type that defines how an animatable value changes over time — mirrors
/// SwiftUI's `CustomAnimation`.
///
/// Wrap one in an ``Animation`` with ``Animation/init(_:)`` and use it as any
/// other: `withAnimation(Animation(MyCurve())) { … }`.
///
/// ```swift
/// struct Linear: CustomAnimation {
///     var duration: TimeInterval
///
///     func animate<V: VectorArithmetic>(
///         value: V, time: TimeInterval, context: inout AnimationContext<V>
///     ) -> V? {
///         guard time < duration else { return nil }
///         return value.scaled(by: time / duration)
///     }
/// }
/// ```
///
/// TUIkit integrates a custom animation once, on its 60 Hz frame grid, the
/// first time each frame of it is asked for, and keeps every value: so the
/// measure and render walks of a frame read the same value, a frame asked for
/// twice costs nothing the second time, and once ``animate(value:time:context:)``
/// returns `nil` the kept values are the curve's whole table — repeated,
/// reversed, delayed and sped up as a built-in curve is. Until then the
/// animation runs live, a frame at a time. `value` is the whole change as a
/// `Double` of 1, and the result is taken as the fraction of the change made:
/// a curve that treats a value's components differently from one another
/// moves them all alike here. Its context's environment is a default one.
public protocol CustomAnimation: Hashable, Sendable {
    /// The value at `time` seconds into the animation, of a change of
    /// `value`, or `nil` when the animation has finished.
    ///
    /// - Parameters:
    ///   - value: The whole change: where the value goes, less where it was.
    ///   - time: The time since the animation started, in seconds.
    ///   - context: The animation's state, which this may change and which is
    ///     handed back to the next call.
    nonisolated func animate<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> V?

    /// The rate of change at `time`, or `nil` where the animation has none to
    /// give. Not implemented, it is `nil`.
    nonisolated func velocity<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: AnimationContext<V>
    ) -> V?

    /// Whether this animation, applied to a value `previous` is still
    /// animating, takes it over — merging the two — rather than running beside
    /// it. Not implemented, it is `false`.
    nonisolated func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool
}

extension CustomAnimation {
    /// No velocity: `nil`.
    public func velocity<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: AnimationContext<V>
    ) -> V? {
        nil
    }

    /// Never merges: `false`.
    public func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool {
        false
    }
}

// MARK: - State

/// A key for a value a custom animation keeps in its ``AnimationState`` —
/// mirrors SwiftUI's `AnimationStateKey`.
public protocol AnimationStateKey {
    /// The type of the value kept.
    associatedtype Value

    /// The value before anything is stored.
    static var defaultValue: Value { get }
}

/// The values a custom animation keeps between calls, by key — mirrors
/// SwiftUI's `AnimationState`.
public struct AnimationState<Value: VectorArithmetic> {
    /// The stored values, by their key's type.
    private var storage: [ObjectIdentifier: Any] = [:]

    /// An empty state: every key reads its default.
    public init() {}

    /// The value stored for `key`, or its default.
    public subscript<K: AnimationStateKey>(key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

/// What a custom animation is handed with each call: its state, whether it is
/// logically complete, and the environment — mirrors SwiftUI's
/// `AnimationContext`.
public struct AnimationContext<Value: VectorArithmetic> {
    /// The animation's own state, kept from one call to the next.
    public var state: AnimationState<Value>

    /// Whether the animation has logically completed — set by the animation,
    /// for a ``AnimationCompletionCriteria/logicallyComplete`` completion.
    public var isLogicallyComplete: Bool

    /// The environment the animation runs in.
    public var environment: EnvironmentValues { _environment }

    /// ``environment``'s storage.
    private let _environment: EnvironmentValues

    /// A context with `state`, in `environment`.
    package init(
        state: AnimationState<Value> = AnimationState(), isLogicallyComplete: Bool = false,
        environment: EnvironmentValues = EnvironmentValues()
    ) {
        self.state = state
        self.isLogicallyComplete = isLogicallyComplete
        self._environment = environment
    }

    /// This context with another state, of another value type.
    public func withState<T: VectorArithmetic>(_ state: AnimationState<T>) -> AnimationContext<T> {
        AnimationContext<T>(state: state, isLogicallyComplete: isLogicallyComplete, environment: _environment)
    }
}

// MARK: - The integrated curve

/// Which custom animation an ``AnimationCurve`` runs: its place in
/// ``CustomAnimationCurve``'s table.
///
/// An index rather than the curve itself, so `AnimationCurve` stays a trivial
/// enum every byte of which is written (`_AllBytesDefined`): the per-pass
/// memos hash an ``Animation`` whole, and a reference in it would make every
/// view holding one bypass them.
struct CustomCurveID: Hashable, Sendable {
    /// The place in the table.
    let index: Int

    /// The curve.
    var curve: CustomAnimationCurve { CustomAnimationCurve.curve(at: index) }
}

/// A custom animation as a curve: integrated on the frame grid as it is asked
/// for, every value kept (see ``CustomAnimation``).
///
/// One per distinct custom animation, for the life of the process: equal
/// animations share it, so a frame is integrated once whoever asks for it — a
/// change's transaction, the record its animation runs from, a modifier
/// rebuilding it with a delay, the same animation made again in a body.
final class CustomAnimationCurve: @unchecked Sendable {
    /// The frames a second the animation is integrated at: the render loop's.
    static let framesPerSecond: Double = 60

    /// The most frames kept: ten minutes of them. An animation still running
    /// then stops where it is, at its target, rather than growing without end.
    static let maximumFrames = 60 * 600

    /// The animation.
    let base: any CustomAnimation

    /// ``base``, for equality and hashing.
    private let key: AnyHashable

    /// What has been integrated so far.
    private struct Table: @unchecked Sendable {
        /// The fraction of the change made at each frame integrated, from 0.
        var values: [Double] = []
        /// The state handed from one frame to the next.
        var context = AnimationContext<Double>()
        /// The first frame at which the animation had finished, once one has.
        var finishedFrame: Int?
        /// The first frame at which the animation said it was logically
        /// complete, if it has.
        var logicallyCompleteFrame: Int?
    }

    /// ``Table``, behind a lock: an ``Animation`` is `Sendable`.
    private let table = Lock(initialState: Table())

    private init(_ base: some CustomAnimation) {
        self.base = base
        self.key = AnyHashable(base)
    }

    /// The curves, and where each animation's is.
    private struct Registry: @unchecked Sendable {
        var curves: [CustomAnimationCurve] = []
        var indices: [AnyHashable: Int] = [:]
    }

    /// Every custom animation's curve, kept for the life of the process: a
    /// value's curve is its integration, which an equal value reuses. An
    /// animation finishes in a few dozen frames, so a curve's table is small;
    /// one that runs for ten minutes keeps 36,000 values.
    private static let registry = Lock(initialState: Registry())

    /// The id of `base`'s curve, made the first time `base` is seen.
    static func intern(_ base: some CustomAnimation) -> CustomCurveID {
        registry.withLock { registry in
            let key = AnyHashable(base)
            if let index = registry.indices[key] { return CustomCurveID(index: index) }
            registry.curves.append(CustomAnimationCurve(base))
            registry.indices[key] = registry.curves.count - 1
            return CustomCurveID(index: registry.curves.count - 1)
        }
    }

    /// The curve at `index`.
    static func curve(at index: Int) -> CustomAnimationCurve {
        registry.withLock { $0.curves[index] }
    }

    /// The frame `time` falls in: read on the frame grid, so every walk of a
    /// frame, and a frame asked for again, reads the same value.
    private static func frame(at time: TimeInterval) -> Int {
        max(0, Int((time * framesPerSecond + 1e-6).rounded(.down)))
    }

    /// Integrates `table` through `frame`, or until the animation finishes.
    private static func integrate(_ table: inout Table, through frame: Int, base: any CustomAnimation) {
        while table.finishedFrame == nil, table.values.count <= frame {
            let index = table.values.count
            guard index < maximumFrames else {
                table.finishedFrame = index
                return
            }
            let time = Double(index) / framesPerSecond
            guard let value = base.animate(value: 1.0, time: time, context: &table.context) else {
                table.finishedFrame = index
                return
            }
            table.values.append(value)
            if table.context.isLogicallyComplete, table.logicallyCompleteFrame == nil {
                table.logicallyCompleteFrame = index
            }
        }
    }

    /// The fraction of the change made `time` seconds into one pass: the
    /// target's, 1, once the animation has finished.
    func progress(at time: TimeInterval) -> Double {
        let frame = Self.frame(at: time)
        let base = self.base
        return table.withLock { table in
            Self.integrate(&table, through: frame, base: base)
            if let finished = table.finishedFrame, frame >= finished { return 1 }
            return table.values[frame]
        }
    }

    /// How long one pass takes, if the animation finishes within `time`
    /// seconds — integrating that far to find out — else `nil`.
    func duration(within time: TimeInterval) -> TimeInterval? {
        let frame = Self.frame(at: time)
        let base = self.base
        return table.withLock { table in
            Self.integrate(&table, through: frame, base: base)
            return table.finishedFrame.map { Double($0) / Self.framesPerSecond }
        }
    }

    /// How long one pass takes, if that is known already, without integrating
    /// any further.
    var knownDuration: TimeInterval? {
        table.withLock { table in table.finishedFrame.map { Double($0) / Self.framesPerSecond } }
    }

    /// When the animation said it was logically complete, within one pass, if
    /// it has said so in what has been integrated.
    var logicalCompletionTime: TimeInterval? {
        table.withLock { table in table.logicallyCompleteFrame.map { Double($0) / Self.framesPerSecond } }
    }
}

// MARK: - Animation

extension Animation {
    /// An animation that runs a custom animation — mirrors SwiftUI's
    /// `Animation.init(_:)`.
    ///
    /// The animation is integrated once, a frame at a time, as it is asked for
    /// (see ``CustomAnimation``). Delays, speeds and repeats apply as to any
    /// curve: a repeat starts once the animation has finished its first pass,
    /// which ``CustomAnimation/animate(value:time:context:)`` says by returning
    /// `nil`.
    ///
    /// - Parameter base: The custom animation.
    public init<A: CustomAnimation>(_ base: A) {
        // An animation's own curve handed back: the animation itself.
        if let builtIn = base as? BuiltInCustomAnimation {
            self = builtIn.animation
            return
        }
        self.init(curve: .custom(CustomAnimationCurve.intern(base)), passDuration: 0)
    }

    /// The custom animation this animation runs — mirrors SwiftUI's
    /// `Animation.base`.
    ///
    /// For an animation built from a curve TUIkit names (`easeInOut`,
    /// `spring`, …), a custom animation that runs it, which
    /// ``init(_:)`` turns back into this animation.
    public var base: any CustomAnimation {
        plainCustomAnimation ?? BuiltInCustomAnimation(animation: self)
    }

    /// The value at `time` seconds into this animation, of a change of `value`,
    /// or `nil` once it has finished — mirrors SwiftUI's
    /// `Animation.animate(value:time:context:)`.
    ///
    /// A custom animation with no delay, speed or repeat is asked itself, with
    /// `value` and `context` as given. Any other is sampled as TUIkit draws
    /// it: the whole change scaled by ``fraction(at:)``.
    public func animate<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> V? {
        if let custom = plainCustomAnimation {
            return custom.animate(value: value, time: time, context: &context)
        }
        guard !isFinished(at: time) else { return nil }
        return value.scaled(by: fraction(at: time))
    }

    /// The rate of change at `time` seconds into this animation, of a change
    /// of `value` — mirrors SwiftUI's `Animation.velocity(value:time:context:)`.
    ///
    /// A plain custom animation answers itself; any other is differentiated
    /// across a frame of ``fraction(at:)``, and is `nil` once it has finished.
    public func velocity<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: AnimationContext<V>
    ) -> V? {
        if let custom = plainCustomAnimation {
            return custom.velocity(value: value, time: time, context: context)
        }
        guard !isFinished(at: time) else { return nil }
        let step = 1 / CustomAnimationCurve.framesPerSecond
        let slope = (fraction(at: time + step) - fraction(at: max(0, time - step))) / (time >= step ? 2 * step : step)
        return value.scaled(by: slope)
    }

    /// Whether this animation, applied to a value `previous` is still
    /// animating, takes it over — mirrors SwiftUI's
    /// `Animation.shouldMerge(previous:value:time:context:)`.
    ///
    /// A plain custom animation answers itself. Of TUIkit's curves a spring
    /// says yes, as SwiftUI's does, and the rest no — though TUIkit restarts a
    /// spring from where the value stands, at rest, rather than carrying its
    /// velocity across.
    public func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool {
        if let custom = plainCustomAnimation {
            return custom.shouldMerge(previous: previous, value: value, time: time, context: &context)
        }
        if case .spring = curve { return true }
        return false
    }

    /// The custom animation this runs, where it runs one with no delay, speed,
    /// logical completion or repeat of TUIkit's around it.
    private var plainCustomAnimation: (any CustomAnimation)? {
        guard case .custom(let id) = curve, delayInterval == 0, speedFactor == 1, logicalCompletion < 0,
            case .count(1, _) = repeatMode
        else { return nil }
        return id.curve.base
    }
}

/// One of TUIkit's own animations as a ``CustomAnimation``: what
/// ``Animation/base`` hands back for an animation TUIkit names, and what
/// ``Animation/init(_:)`` unwraps again.
struct BuiltInCustomAnimation: CustomAnimation {
    /// The animation.
    let animation: Animation

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        animation.animate(value: value, time: time, context: &context)
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        animation.velocity(value: value, time: time, context: context)
    }

    func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool {
        animation.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }
}
