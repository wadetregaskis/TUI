//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyframeTypes.swift
//
//  The four keyframes, and the builders that put them, and tracks, together.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - The keyframes

/// A keyframe that uses simple linear interpolation.
public struct LinearKeyframe<Value: Animatable>: KeyframeTrackContent {
    private let keyframe: Keyframe<Value>

    /// Creates a new keyframe using the given value and timestamp.
    ///
    /// - Parameters:
    ///   - to: The value of the keyframe.
    ///   - duration: The duration of the segment defined by this keyframe.
    ///   - timingCurve: A unit curve that controls the speed of interpolation.
    public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
        keyframe = Keyframe(target: to, duration: duration, kind: .linear(timingCurve))
    }

    /// The keyframe itself.
    public var body: Self { self }

    /// Adds this keyframe.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.keyframes.append(keyframe)
    }
}

/// A keyframe that uses a cubic curve to smoothly interpolate between values.
///
/// If you don't specify a start or end velocity, a curve that maintains
/// smooth motion between keyframes is computed. Adjacent cubic keyframes
/// result in a Catmull-Rom spline.
///
/// If a cubic keyframe follows a different type of keyframe, such as a linear
/// keyframe, the end velocity of the segment defined by the previous keyframe
/// will be used as the starting velocity.
///
/// Likewise, if a cubic keyframe is followed by a different type of keyframe,
/// the initial velocity of the next segment is used as the end velocity of the
/// segment defined by this keyframe.
public struct CubicKeyframe<Value: Animatable>: KeyframeTrackContent {
    private let keyframe: Keyframe<Value>

    /// Creates a new keyframe using the given value and timestamp.
    ///
    /// - Parameters:
    ///   - to: The value of the keyframe.
    ///   - duration: The duration of the segment defined by this keyframe.
    ///   - startVelocity: The velocity of the value at the beginning of the
    ///     segment, or `nil` to automatically compute the velocity to maintain
    ///     smooth motion.
    ///   - endVelocity: The velocity of the value at the end of the segment, or
    ///     `nil` to automatically compute the velocity to maintain smooth
    ///     motion.
    public init(
        _ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil
    ) {
        keyframe = Keyframe(
            target: to, duration: duration,
            kind: .cubic(startVelocity: startVelocity, endVelocity: endVelocity))
    }

    /// The keyframe itself.
    public var body: Self { self }

    /// Adds this keyframe.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.keyframes.append(keyframe)
    }
}

/// A keyframe that uses a spring function to interpolate to the given value.
public struct SpringKeyframe<Value: Animatable>: KeyframeTrackContent {
    private let keyframe: Keyframe<Value>

    /// Creates a new keyframe using the given value and timestamp.
    ///
    /// - Parameters:
    ///   - to: The value of the keyframe.
    ///   - duration: The duration of the segment defined by this keyframe, or
    ///     nil to use the settling duration of the spring.
    ///   - spring: The spring that defines the shape of the segment before
    ///     this keyframe.
    ///   - startVelocity: The velocity of the value at the start of the
    ///     segment, or `nil` to automatically compute the velocity to maintain
    ///     smooth motion.
    public init(
        _ to: Value, duration: TimeInterval? = nil, spring: Spring = Spring(),
        startVelocity: Value? = nil
    ) {
        keyframe = Keyframe(
            target: to, duration: duration, kind: .spring(spring, startVelocity: startVelocity))
    }

    /// The keyframe itself.
    public var body: Self { self }

    /// Adds this keyframe.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.keyframes.append(keyframe)
    }
}

/// A keyframe that immediately moves to the given value without
/// interpolating.
public struct MoveKeyframe<Value: Animatable>: KeyframeTrackContent {
    private let keyframe: Keyframe<Value>

    /// Creates a new keyframe using the given value.
    ///
    /// - Parameter to: The value of the keyframe.
    public init(_ to: Value) {
        keyframe = Keyframe(target: to, duration: 0, kind: .move)
    }

    /// The keyframe itself.
    public var body: Self { self }

    /// Adds this keyframe.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.keyframes.append(keyframe)
    }
}

// MARK: - What the builders build

/// Two runs of track content, one after the other.
struct _KeyframeTrackSequence<First: KeyframeTrackContent, Second: KeyframeTrackContent>:
    KeyframeTrackContent
where First.Value == Second.Value {
    typealias Value = First.Value

    let first: First
    let second: Second

    var body: Self { self }

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        first._resolve(into: &resolved)
        second._resolve(into: &resolved)
    }
}

/// Track content repeated over a collection — a `for` loop in a builder.
struct _KeyframeTrackArray<Element: KeyframeTrackContent>: KeyframeTrackContent {
    typealias Value = Element.Value

    let elements: [Element]

    var body: Self { self }

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        for element in elements { element._resolve(into: &resolved) }
    }
}

/// No keyframes.
struct _EmptyKeyframeTrackContent<Value: Animatable>: KeyframeTrackContent {
    var body: Self { self }

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {}
}

// MARK: - The builders

/// The builder that creates keyframe track content from the keyframes that you
/// define within a closure.
@MainActor
@resultBuilder
public struct KeyframeTrackContentBuilder<Value: Animatable> {
    /// A keyframe, or other track content, as written.
    public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> K
    where Value == K.Value {
        expression
    }

    /// The content of a `for` loop.
    public static func buildArray(_ components: [some KeyframeTrackContent<Value>]) -> some KeyframeTrackContent<Value> {
        _KeyframeTrackArray(elements: components)
    }

    /// The first branch of an `if`/`else`.
    public static func buildEither<First: KeyframeTrackContent, Second: KeyframeTrackContent>(
        first component: First
    ) -> Conditional<Value, First, Second> where Value == First.Value, First.Value == Second.Value {
        Conditional(storage: .first(component))
    }

    /// The second branch of an `if`/`else`.
    public static func buildEither<First: KeyframeTrackContent, Second: KeyframeTrackContent>(
        second component: Second
    ) -> Conditional<Value, First, Second> where Value == First.Value, First.Value == Second.Value {
        Conditional(storage: .second(component))
    }

    /// The first content of a block.
    public static func buildPartialBlock<K: KeyframeTrackContent>(first: K) -> K where Value == K.Value {
        first
    }

    /// The content so far, then the next.
    public static func buildPartialBlock(
        accumulated: some KeyframeTrackContent<Value>, next: some KeyframeTrackContent<Value>
    ) -> some KeyframeTrackContent<Value> {
        _KeyframeTrackSequence(first: accumulated, second: next)
    }

    /// An empty block.
    public static func buildBlock() -> some KeyframeTrackContent<Value> {
        _EmptyKeyframeTrackContent<Value>()
    }
}

extension KeyframeTrackContentBuilder {
    /// A conditional result from the result builder.
    public struct Conditional<ConditionalValue, First, Second>: KeyframeTrackContent
    where
        ConditionalValue == First.Value, First: KeyframeTrackContent, Second: KeyframeTrackContent,
        First.Value == Second.Value
    {
        enum Storage {
            case first(First)
            case second(Second)
        }

        let storage: Storage

        /// The animatable value the keyframes move.
        public typealias Value = ConditionalValue

        /// The content itself.
        public var body: Self { self }

        /// Adds the keyframes of the branch that was taken.
        public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<ConditionalValue>) {
            switch storage {
            case .first(let first): first._resolve(into: &resolved)
            case .second(let second): second._resolve(into: &resolved)
            }
        }
    }
}

/// A builder that combines keyframe content values into a single value.
///
/// It takes either keyframes, which become one track over the whole value, or
/// tracks (``KeyframeTrack``) — one per property.
@MainActor
@resultBuilder
public struct KeyframesBuilder<Value> {
    /// A keyframe, or other track content, as written.
    public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> K
    where Value == K.Value {
        expression
    }

    /// The content of a `for` loop.
    public static func buildArray(_ components: [some KeyframeTrackContent<Value>]) -> some KeyframeTrackContent<Value> {
        _KeyframeTrackArray(elements: components)
    }

    /// The first branch of an `if`/`else`.
    public static func buildEither<First: KeyframeTrackContent, Second: KeyframeTrackContent>(
        first component: First
    ) -> KeyframeTrackContentBuilder<Value>.Conditional<Value, First, Second>
    where Value == First.Value, First.Value == Second.Value {
        KeyframeTrackContentBuilder<Value>.Conditional(storage: .first(component))
    }

    /// The second branch of an `if`/`else`.
    public static func buildEither<First: KeyframeTrackContent, Second: KeyframeTrackContent>(
        second component: Second
    ) -> KeyframeTrackContentBuilder<Value>.Conditional<Value, First, Second>
    where Value == First.Value, First.Value == Second.Value {
        KeyframeTrackContentBuilder<Value>.Conditional(storage: .second(component))
    }

    /// The first content of a block.
    public static func buildPartialBlock<K: KeyframeTrackContent>(first: K) -> K where Value == K.Value {
        first
    }

    /// The content so far, then the next.
    public static func buildPartialBlock(
        accumulated: some KeyframeTrackContent<Value>, next: some KeyframeTrackContent<Value>
    ) -> some KeyframeTrackContent<Value> {
        _KeyframeTrackSequence(first: accumulated, second: next)
    }

    /// An empty block of track content.
    public static func buildBlock() -> some KeyframeTrackContent<Value> where Value: Animatable {
        _EmptyKeyframeTrackContent<Value>()
    }

    /// Keyframes written without a track: one track over the whole value.
    public static func buildFinalResult<Content: KeyframeTrackContent>(
        _ component: Content
    ) -> KeyframeTrack<Value, Value, Content> where Value == Content.Value {
        KeyframeTrack { component }
    }

    /// Keyframes — a track, or a type of the app's own — as written.
    public static func buildExpression<Content: Keyframes>(_ expression: Content) -> Content
    where Value == Content.Value {
        expression
    }

    /// The first keyframes of a block.
    public static func buildPartialBlock<Content: Keyframes>(first: Content) -> Content
    where Value == Content.Value {
        first
    }

    /// The keyframes so far, then the next.
    public static func buildPartialBlock(
        accumulated: some Keyframes<Value>, next: some Keyframes<Value>
    ) -> some Keyframes<Value> {
        _KeyframesSequence(first: accumulated, second: next)
    }

    /// An empty block of keyframes.
    public static func buildBlock() -> some Keyframes<Value> {
        _EmptyKeyframes<Value>()
    }

    /// Keyframes, as they are.
    public static func buildFinalResult<Content: Keyframes>(_ component: Content) -> Content
    where Value == Content.Value {
        component
    }
}
