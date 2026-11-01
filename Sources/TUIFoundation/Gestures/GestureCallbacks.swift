//  🖥️ TUI — A Terminal UI framework for Swift
//  GestureCallbacks.swift
//
//  What a gesture does when it changes and when it ends, and the two
//  adaptors SwiftUI puts beside them: `map(_:)` and `modifiers(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension Gesture {
    /// Adds an action to perform when the gesture ends.
    ///
    /// - Important: The action is only performed if the gesture ends
    ///   successfully. Use a ``GestureState`` property to track state that is
    ///   reset regardless of how the gesture ends.
    ///
    /// - Parameter action: The action to perform when this gesture ends. The
    ///   `action` closure's parameter contains the final value of the gesture.
    /// - Returns: A gesture that triggers `action` when the gesture ends.
    @inlinable
    nonisolated public func onEnded(_ action: @escaping (Value) -> Void) -> _EndedGesture<Self> {
        _EndedGesture(content: self, action: action)
    }

    /// Returns a gesture that uses the given closure to map over this
    /// gesture's value.
    nonisolated public func map<T>(_ body: @escaping (Value) -> T) -> _MapGesture<Self, T> {
        _MapGesture(content: self, transform: body)
    }

    /// Combines a gesture with keyboard modifiers.
    ///
    /// The gesture receives updates while the user presses the modifier keys
    /// that correspond to the given modifiers option set.
    ///
    /// The keys are the ones a terminal reports with a mouse event: Shift,
    /// Option (Alt) and Control, from the SGR modifier bits. They are read at
    /// the press, and the gesture runs if they include every key asked for —
    /// letting go of one mid-drag does not stop it (both measured on macOS
    /// 15.8). Command is never reported, so a gesture that requires it never
    /// runs.
    ///
    /// - Parameter modifiers: A set of flags that correspond to the modifier
    ///   keys that the user needs to hold down.
    /// - Returns: A new gesture that combines a gesture with keyboard
    ///   modifiers.
    nonisolated public func modifiers(_ modifiers: EventModifiers) -> _ModifiersGesture<Self> {
        _ModifiersGesture(content: self, modifiers: modifiers)
    }
}

extension Gesture where Value: Equatable {
    /// Adds an action to perform when the gesture's value changes.
    ///
    /// A long press reports `true` the moment the button goes down; a drag
    /// reports each move once it has started. The final value goes to
    /// ``onEnded(_:)`` alone.
    ///
    /// - Parameter action: The action to perform when this gesture's value
    ///   changes. The `action` closure's parameter contains the gesture's new
    ///   value.
    /// - Returns: A gesture that triggers `action` when this gesture's value
    ///   changes.
    nonisolated public func onChanged(_ action: @escaping (Value) -> Void) -> _ChangedGesture<Self> {
        _ChangedGesture(content: self, action: action)
    }
}

// MARK: - The gesture types

/// A gesture that runs an action when its content ends — what
/// ``Gesture/onEnded(_:)`` returns.
///
/// ``Gesture/onEnded(_:)`` is `@inlinable` because
/// ``View/onTapGesture(count:perform:)`` is: an app's specialised copy of
/// the tap modifier then builds this struct itself, from metadata it caches,
/// where calling into TUIFoundation's unspecialised `onEnded` looked
/// `_EndedGesture<TapGesture>`'s metadata up at run time on every call
/// (CONTRIBUTING.md, "Crossing a module boundary").
nonisolated public struct _EndedGesture<Content: Gesture>: Gesture {
    @usableFromInline let content: Content
    @usableFromInline let action: (Content.Value) -> Void

    /// The memberwise initializer, spelled out to be `@inlinable` for
    /// ``Gesture/onEnded(_:)``: the synthesized one cannot carry the
    /// attribute, and a call to it would bring the metadata lookup back.
    @inlinable
    init(content: Content, action: @escaping (Content.Value) -> Void) {
        self.content = content
        self.action = action
    }

    public typealias Value = Content.Value
    public typealias Body = Never

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { EndedGestureNode<Value>() }
        node.child = Content._makeGesture(gesture: gesture.content, inputs: inputs.child(0)).node
        node.action = gesture.action
        return _GestureOutputs(node)
    }
}

/// A gesture that runs an action when its content's value changes — what
/// ``Gesture/onChanged(_:)`` returns.
nonisolated public struct _ChangedGesture<Content: Gesture>: Gesture where Content.Value: Equatable {
    let content: Content
    let action: (Content.Value) -> Void

    public typealias Value = Content.Value
    public typealias Body = Never

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { ChangedGestureNode<Value>() }
        node.child = Content._makeGesture(gesture: gesture.content, inputs: inputs.child(0)).node
        node.action = gesture.action
        return _GestureOutputs(node)
    }
}

/// A gesture whose value is its content's, transformed — what
/// ``Gesture/map(_:)`` returns.
nonisolated public struct _MapGesture<Content: Gesture, Value>: Gesture {
    let content: Content
    let transform: (Content.Value) -> Value

    public typealias Body = Never

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { MapGestureNode<Content.Value, Value>() }
        node.child = Content._makeGesture(gesture: gesture.content, inputs: inputs.child(0)).node
        node.transform = gesture.transform
        return _GestureOutputs(node)
    }
}

/// A gesture that runs only when the press came with certain modifier keys —
/// what ``Gesture/modifiers(_:)`` returns.
nonisolated public struct _ModifiersGesture<Content: Gesture>: Gesture {
    let content: Content
    let modifiers: EventModifiers

    public typealias Value = Content.Value
    public typealias Body = Never

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { ModifiersGestureNode<Value>() }
        node.child = Content._makeGesture(gesture: gesture.content, inputs: inputs.child(0)).node
        node.required = gesture.modifiers
        return _GestureOutputs(node)
    }
}

// MARK: - Recognizers

/// A recognizer that wraps another and reports what it does — the shared half
/// of every adaptor: the phase, value and timer are the child's.
class WrappingGestureNode<ChildValue, Value>: GestureNode<Value> {
    /// The recognizer wrapped: a placeholder until the gesture is built.
    var child = GestureNode<ChildValue>()

    override func receive(_ input: GestureInput, deliver: Bool) {
        child.receive(input, deliver: deliver)
        mirror()
        if deliver { deliverOwn() }
    }

    override func flush() {
        child.flush()
        mirror()
        deliverOwn()
    }

    override func cancel() {
        child.cancel()
        mirror()
        deliverOwn()
    }

    override var deadline: Int64? { child.deadline }

    /// The child's value as this node reports it — `nil`, reporting nothing,
    /// until an adaptor says otherwise.
    func transformed(_ value: ChildValue) -> Value? { nil }

    /// Takes the child's phase and value as this node's.
    func mirror() {
        phase = child.phase
        if version != child.version {
            version = child.version
            value = child.value.flatMap(transformed)
        }
    }

    /// Runs this node's own callback, if what the child did calls for it.
    func deliverOwn() {}
}

/// An adaptor that reports its child's value unchanged.
class PassThroughGestureNode<Value>: WrappingGestureNode<Value, Value> {
    override func transformed(_ value: Value) -> Value? { value }
}

/// Runs `action` once per successful gesture.
final class EndedGestureNode<Value>: PassThroughGestureNode<Value> {
    var action: (Value) -> Void = { _ in }

    /// Whether `action` has run for the end the child is at.
    private var delivered = false

    /// Re-arms the action at every press, and whenever the child is anywhere
    /// but its end — on every input, delivered or not.
    ///
    /// The press is what begins a gesture: a long press with no minimum
    /// duration goes from one end straight to the next, never through a phase
    /// that is not an end, so it ran its action at the first press alone
    /// (macOS 15.8 runs it at each). Not a new report: a combination reports
    /// at every input, and two such presses together, ended at the press,
    /// would run again at the release. Cleared only in ``deliverOwn()``, the
    /// mark stayed set across a gesture held back from start to end: a single
    /// tap behind a double tap is fed each click with delivery off, so after
    /// it ran once, every later click's end, released when the double tap
    /// gave up, was taken for the end it had already reported.
    override func receive(_ input: GestureInput, deliver: Bool) {
        if case .pointer(let pointer) = input, pointer.kind == .down { delivered = false }
        super.receive(input, deliver: deliver)
    }

    override func mirror() {
        super.mirror()
        if phase != .ended { delivered = false }
    }

    override func deliverOwn() {
        guard phase == .ended, !delivered, let value else { return }
        delivered = true
        action(value)
    }
}

/// Runs `action` with each new value while the gesture is under way.
final class ChangedGestureNode<Value: Equatable>: PassThroughGestureNode<Value> {
    var action: (Value) -> Void = { _ in }

    /// The value `action` last ran with, in the gesture under way.
    private var lastDelivered: Value?

    /// Forgets the last value once the gesture is over (or never began), on
    /// every input, delivered or not: its next one reports its first value
    /// even if it equals this one's last, as a second press of a long press
    /// reports `true` again. Forgotten only in ``deliverOwn()``, a gesture
    /// that ended while held back — fed with delivery off — kept its last
    /// value, and the next one's equal first value, released by ``flush()``,
    /// was dropped as no change.
    override func mirror() {
        super.mirror()
        if phase != .possible, phase != .active { lastDelivered = nil }
    }

    override func deliverOwn() {
        guard phase == .possible || phase == .active, let value, value != lastDelivered else { return }
        lastDelivered = value
        action(value)
    }
}

/// Reports its child's value transformed.
final class MapGestureNode<In, Out>: WrappingGestureNode<In, Out> {
    var transform: ((In) -> Out)?

    override func transformed(_ value: In) -> Out? { transform?(value) }
}

/// Lets a gesture begin only on a press with the required modifier keys.
final class ModifiersGestureNode<Value>: PassThroughGestureNode<Value> {
    var required: EventModifiers = []

    /// Whether the press under way came with the required keys.
    private var admitted = false

    override func receive(_ input: GestureInput, deliver: Bool) {
        if case .pointer(let pointer) = input, pointer.kind == .down {
            admitted = pointer.modifiers.isSuperset(of: required)
            if !admitted {
                if !child.phase.isTerminal, child.phase != .idle { child.cancel() }
                phase = .failed
                value = nil
                version &+= 1
                return
            }
        }
        guard admitted else { return }
        super.receive(input, deliver: deliver)
    }
}
