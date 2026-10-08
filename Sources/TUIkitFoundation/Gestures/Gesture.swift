//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Gesture.swift
//
//  SwiftUI's `Gesture` protocol: a value that matches a sequence of pointer
//  events and reports a value for each of its states.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// An instance that matches a sequence of events to a gesture, and returns a
/// stream of values for each of its states.
///
/// Create custom gestures by declaring types that conform to the `Gesture`
/// protocol, composing the built-in ones in their `body`:
///
/// ```swift
/// struct DoubleTapOrDrag: Gesture {
///     var body: some Gesture {
///         TapGesture(count: 2).exclusively(before: DragGesture())
///     }
/// }
/// ```
///
/// Attach one with ``View/gesture(_:including:)``,
/// ``View/highPriorityGesture(_:including:)`` or
/// ``View/simultaneousGesture(_:including:)``.
///
/// ## What a terminal changes
///
/// A gesture is the **pointer's** API: the left mouse button, as the terminal
/// reports it in SGR mouse mode. Geometry is in whole cells — a location is a
/// ``CellPoint``, a translation a ``CellSize`` and a velocity a ``CellVector``
/// (§2.2 of `Documentation/SwiftUI-compatibility.md`) — and distances are
/// counted in cells along either axis. A terminal reports no touches, pressure,
/// pinch or rotation, so `MagnifyGesture`, `RotateGesture` and the other
/// multi-touch gestures are absent.
///
/// A gesture has no keyboard route of its own, on macOS or here: a keyboard
/// user reaches a control through its own action (a `Button`'s Return), and an
/// app that puts behaviour behind a gesture on a plain view gives it a key as
/// well (`focusable()` and `onKeyPress(_:action:)`), or a terminal without
/// mouse reporting cannot reach it.
@MainActor @preconcurrency
public protocol Gesture<Value> {
    /// The type representing the gesture's value.
    associatedtype Value

    /// The type of gesture representing the body of `Self`.
    associatedtype Body: Gesture

    /// The content and behavior of the gesture.
    var body: Body { get }

    /// Builds the recognizer for `gesture`. Framework plumbing, SwiftUI's
    /// spelling: a gesture made of other gestures inherits it from its `body`,
    /// and the built-in gestures provide their own.
    static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value>
}

extension Gesture where Value == Body.Value {
    /// A gesture composed of others is recognized as its body is.
    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        Body._makeGesture(gesture: gesture.body, inputs: inputs)
    }
}

extension Gesture where Body == Never {
    /// A primitive gesture has no body: it is recognized by its own
    /// `_makeGesture(gesture:inputs:)`, which never asks for this.
    public var body: Never {
        fatalError("\(Self.self) is a primitive gesture and has no body")
    }
}

// MARK: - Never

extension Never: Gesture {
    /// `Never` is the body of every primitive gesture, and has no value.
    public typealias Value = Never
}

// MARK: - Plumbing

/// What a gesture is built against: where its recognizers live between frames.
///
/// Framework plumbing, as SwiftUI's type of the same name is; nothing outside
/// TUIkit makes one.
public struct _GestureInputs {
    /// The recognizers of the gesture this belongs to, kept across frames.
    let cache: GestureNodeCache

    /// This gesture's place in the gesture tree, so a recognizer comes back to
    /// the same gesture at the next build.
    let path: Int

    init(cache: GestureNodeCache, path: Int = 0) {
        self.cache = cache
        self.path = path
    }

    /// The inputs of this gesture's `index`-th component.
    func child(_ index: Int) -> Self {
        Self(cache: cache, path: path &* 8 &+ index &+ 1)
    }

    /// The recognizer at this place in the tree — the last build's if it was
    /// one of the same type, else a new one.
    @MainActor
    func node<Node: GestureNodeBase>(at slot: Int = 0, _ make: () -> Node) -> Node {
        cache.node(at: path &* 8 &+ slot, make)
    }
}

/// What a gesture is built into: its recognizer.
///
/// Framework plumbing, as SwiftUI's type of the same name is.
public struct _GestureOutputs<Value> {
    /// The recognizer.
    let node: GestureNode<Value>

    init(_ node: GestureNode<Value>) {
        self.node = node
    }
}
