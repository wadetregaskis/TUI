//  🖥️ TUI — A Terminal UI framework for Swift
//  Keyframes.swift
//
//  Keyframe timelines: a value's whole path over time, described by keyframes
//  and sampled at any instant — `KeyframeTimeline`, `Keyframes`,
//  `KeyframeTrack`, `KeyframeTrackContent`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - Keyframes

/// A type that defines changes to a value over time.
///
/// Main-actor isolated, as TUI's ``Animatable`` is: resolving keyframes
/// reads and writes their values' `animatableData`.
@MainActor
public protocol Keyframes<Value> {
    /// The type of value animated by this keyframes type.
    associatedtype Value = Body.Value

    /// The type of keyframes representing the body of this type.
    associatedtype Body: Keyframes

    /// The composition of content that comprise the keyframes.
    @KeyframesBuilder<Value> var body: Body { get }

    /// Adds this content's tracks to `resolved`. Not to be implemented by
    /// hand: keyframes of your own are their `body`.
    func _resolve(into resolved: inout _ResolvedKeyframes<Value>, initialValue: Value, initialVelocity: Value?)
}

extension Keyframes where Value == Body.Value {
    /// Keyframes of the app's own are their body.
    public func _resolve(
        into resolved: inout _ResolvedKeyframes<Value>, initialValue: Value, initialVelocity: Value?
    ) {
        body._resolve(into: &resolved, initialValue: initialValue, initialVelocity: initialVelocity)
    }
}

/// `Never` is the body of a keyframes type that resolves itself
/// (``KeyframeTrack``). Its `body` witness is the one `Never: View` declares.
extension Never: Keyframes {
    /// No value: there is no `Never`.
    public typealias Value = Never

    /// Never called.
    public func _resolve(
        into resolved: inout _ResolvedKeyframes<Never>, initialValue: Never, initialVelocity: Never?
    ) {}
}

/// Keyframes resolved into the tracks that change a value over time.
public struct _ResolvedKeyframes<Value> {
    /// One track: how long it runs, and how it writes its part of the value.
    struct Track {
        let duration: TimeInterval
        let apply: @MainActor (inout Value, TimeInterval) -> Void
    }

    var tracks: [Track] = []

    /// The longest track's duration.
    var duration: TimeInterval { tracks.map(\.duration).max() ?? 0 }
}

/// Two keyframes types in sequence — what ``KeyframesBuilder`` builds from a
/// block of them. Their tracks all run from the start, in the order written.
nonisolated struct _KeyframesSequence<First: Keyframes, Second: Keyframes>: Keyframes
where First.Value == Second.Value {
    typealias Value = First.Value

    let first: First
    let second: Second

    // An explicit return keeps this out of the inferred `@KeyframesBuilder`.
    // swiftlint:disable:next implicit_return
    @MainActor var body: Never { return fatalError("_KeyframesSequence resolves itself") }

    @MainActor func _resolve(into resolved: inout _ResolvedKeyframes<Value>, initialValue: Value, initialVelocity: Value?) {
        first._resolve(into: &resolved, initialValue: initialValue, initialVelocity: initialVelocity)
        second._resolve(into: &resolved, initialValue: initialValue, initialVelocity: initialVelocity)
    }
}

/// No keyframes — what an empty ``KeyframesBuilder`` block builds.
struct _EmptyKeyframes<Value>: Keyframes {
    // An explicit return keeps this out of the inferred `@KeyframesBuilder`.
    // swiftlint:disable:next implicit_return
    var body: Never { return fatalError("_EmptyKeyframes resolves itself") }

    func _resolve(into resolved: inout _ResolvedKeyframes<Value>, initialValue: Value, initialVelocity: Value?) {}
}

// MARK: - Tracks

/// A sequence of keyframes animating a single property of a root type.
nonisolated public struct KeyframeTrack<Root, Value, Content>: Keyframes
where Value == Content.Value, Content: KeyframeTrackContent {
    private let keyPath: WritableKeyPath<Root, Value>
    private let content: Content

    /// Creates an instance that animates the entire value from the root of
    /// the key path.
    ///
    /// - Parameter content: A keyframe collection builder closure containing
    ///   the keyframes that control the interpolation curve.
    public init(@KeyframeTrackContentBuilder<Root> content: () -> Content) where Root == Value {
        self.keyPath = \Root.self
        self.content = content()
    }

    /// Creates an instance that animates the property of the root value at the
    /// given key path.
    ///
    /// - Parameters:
    ///   - keyPath: The property to animate.
    ///   - content: A keyframe collection builder closure containing the
    ///     keyframes that control the interpolation curve.
    public init(
        _ keyPath: WritableKeyPath<Root, Value>,
        @KeyframeTrackContentBuilder<Value> content: () -> Content
    ) {
        self.keyPath = keyPath
        self.content = content()
    }

    /// The type of keyframes representing the body of this type.
    public typealias Body = Never

    /// Never called: a track resolves itself. (The explicit `return` keeps
    /// this out of the inferred `@KeyframesBuilder`.)
    @MainActor public var body: Never { return fatalError("KeyframeTrack resolves itself") }  // swiftlint:disable:this implicit_return

    /// Adds this track: its keyframes, from where the initial value has the
    /// property, writing the property.
    @MainActor public func _resolve(
        into resolved: inout _ResolvedKeyframes<Root>, initialValue: Root, initialVelocity: Root?
    ) {
        var keyframes = _ResolvedKeyframeTrackContent<Value>()
        content._resolve(into: &keyframes)
        let curve = KeyframeCurve(from: initialValue[keyPath: keyPath], keyframes: keyframes.keyframes)
        let keyPath = self.keyPath
        resolved.tracks.append(
            _ResolvedKeyframes<Root>.Track(duration: curve.duration) { root, time in
                root[keyPath: keyPath] = curve.value(at: time)
            })
    }
}

// MARK: - Track content

/// A group of keyframes that define an interpolation curve of an animatable
/// value.
@MainActor
public protocol KeyframeTrackContent<Value> {
    /// The animatable value the keyframes move.
    associatedtype Value: Animatable = Body.Value

    /// The type of the content's body.
    associatedtype Body: KeyframeTrackContent

    /// The composition of content that comprise the keyframe track.
    @KeyframeTrackContentBuilder<Value> var body: Body { get }

    /// Adds this content's keyframes to `resolved`. Not to be implemented by
    /// hand: content of your own is its `body`.
    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>)
}

extension KeyframeTrackContent where Value == Body.Value {
    /// Content of the app's own is its body.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        body._resolve(into: &resolved)
    }
}

/// A track's keyframes, in order.
public struct _ResolvedKeyframeTrackContent<Value: Animatable> {
    var keyframes: [Keyframe<Value>] = []
}

/// One keyframe: where it goes, how long it takes, and how it gets there.
struct Keyframe<Value: Animatable> {
    enum Kind {
        case linear(UnitCurve)
        case cubic(startVelocity: Value?, endVelocity: Value?)
        case spring(Spring, startVelocity: Value?)
        case move
    }

    let target: Value
    /// `nil` for a spring that settles in its own time.
    let duration: TimeInterval?
    let kind: Kind
}

// MARK: - The timeline

/// A description of how a value changes over time, modeled using keyframes.
///
/// Unlike other animations (using ``Animation``), keyframes don't interpolate
/// between from and to values that state changes provide. Instead, keyframes
/// fully define the path that a value takes over time using the tracks that
/// make up their body. They have a set duration, and you can scrub and
/// evaluate them for any time within the duration:
///
/// ```swift
/// let keyframes = KeyframeTimeline(initialValue: 0.0) {
///     CubicKeyframe(100, duration: 0.3)
///     CubicKeyframe(0, duration: 0.7)
/// }
/// let value = keyframes.value(time: 0.45)
/// ```
///
/// Multiple nested tracks update the initial value in the order that they are
/// declared, each starting from the initial value. If several change the same
/// property, the value from the last one is used.
///
/// The curves are SwiftUI's (measured): adjacent cubic keyframes form a
/// Catmull–Rom spline, a cubic keyframe takes its starting velocity from a
/// keyframe of another kind before it, a spring keyframe without a duration
/// runs until it is within 0.0001 of its target, and a spring that is cut short
/// hands on the value and velocity it had reached. A time before the start is
/// the start, where SwiftUI extrapolates a spring backwards.
public struct KeyframeTimeline<Value> {
    private let initialValue: Value
    private let resolved: _ResolvedKeyframes<Value>

    /// Creates a new instance using the initial value and content that you
    /// provide.
    @MainActor
    public init(initialValue: Value, @KeyframesBuilder<Value> content: () -> some Keyframes<Value>) {
        self.initialValue = initialValue
        var resolved = _ResolvedKeyframes<Value>()
        content()._resolve(into: &resolved, initialValue: initialValue, initialVelocity: nil)
        self.resolved = resolved
    }

    /// The duration of the content in seconds.
    public var duration: TimeInterval { resolved.duration }

    /// Returns the interpolated value at the given time.
    @MainActor
    public func value(time: Double) -> Value {
        var value = initialValue
        for track in resolved.tracks { track.apply(&value, time) }
        return value
    }

    /// Returns the interpolated value at the given progress in the range zero
    /// to one.
    @MainActor
    public func value(progress: Double) -> Value {
        value(time: progress * duration)
    }
}
