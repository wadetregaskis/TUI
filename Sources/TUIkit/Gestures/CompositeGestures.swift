//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeGestures.swift
//
//  SwiftUI's gesture algebra: two gestures at once, one after the other, or
//  one in place of the other — each as measured on macOS 15.8.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension Gesture {
    /// Combines a gesture with another gesture to create a new gesture that
    /// recognizes both gestures at the same time.
    ///
    /// Both see every event. The combined gesture ends once neither is still
    /// undecided, if either succeeded; a part that failed reports `nil` from
    /// then on (measured on macOS 15.8).
    ///
    /// - Parameter other: A gesture that you want to combine with your gesture
    ///   to create a new, combined gesture.
    /// - Returns: A gesture with two simultaneous gestures.
    public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> {
        SimultaneousGesture(self, other)
    }

    /// Sequences a gesture with another one to create a new gesture, which
    /// results in the second gesture only receiving events after the first
    /// gesture succeeds.
    ///
    /// The second gesture's first event is the first one after the first
    /// gesture succeeded — a long press that succeeds with the button still
    /// down hands a following drag the next move as its start. The sequence
    /// ends when the second gesture does (measured on macOS 15.8).
    ///
    /// - Parameter other: A gesture you want to combine with another gesture
    ///   to create a new, sequenced gesture.
    /// - Returns: A gesture that's a sequence of two gestures.
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> {
        SequenceGesture(self, other)
    }

    /// Combines two gestures exclusively to create a new gesture where only
    /// one gesture succeeds, giving precedence to the first gesture.
    ///
    /// The second gesture is held back while the first is undecided: it
    /// reports nothing until the first fails, and is cancelled if the first
    /// succeeds — so `TapGesture(count: 2).exclusively(before: TapGesture())`
    /// answers a single click only once the double-tap interval has passed.
    ///
    /// - Parameter other: A gesture you combine with your gesture, to create a
    ///   new, combined gesture.
    /// - Returns: A gesture that's the result of combining two gestures where
    ///   only one of them can succeed. TUIkit gives precedence to the first
    ///   gesture.
    public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> {
        ExclusiveGesture(self, other)
    }
}

// MARK: - SimultaneousGesture

/// A gesture containing two gestures that can happen at the same time with
/// neither of them preceding the other.
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
    /// The value of a simultaneous gesture that indicates which of its two
    /// gestures receives events.
    public struct Value {
        /// The value of the first gesture, while it reports one.
        public var first: First.Value?

        /// The value of the second gesture, while it reports one.
        public var second: Second.Value?
    }

    /// The first of two gestures that can happen simultaneously.
    public var first: First

    /// The second of two gestures that can happen simultaneously.
    public var second: Second

    /// Creates a gesture with two gestures that can receive updates or succeed
    /// independently of each other.
    ///
    /// - Parameters:
    ///   - first: The first of two gestures that can happen simultaneously.
    ///   - second: The second of two gestures that can happen simultaneously.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { SimultaneousGestureNode<First, Second>() }
        node.first = First._makeGesture(gesture: gesture.first, inputs: inputs.child(0)).node
        node.second = Second._makeGesture(gesture: gesture.second, inputs: inputs.child(1)).node
        return _GestureOutputs(node)
    }
}

extension SimultaneousGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}
extension SimultaneousGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension SimultaneousGesture.Value: Hashable where First.Value: Hashable, Second.Value: Hashable {}

// MARK: - SequenceGesture

/// A gesture that's a sequence of two gestures.
public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
    /// The value of a sequence gesture that helps to detect whether the first
    /// gesture succeeded, so the second gesture can start.
    public enum Value {
        /// The first gesture hasn't ended.
        case first(First.Value)

        /// The first gesture has ended; the second, with its value once it
        /// reports one.
        case second(First.Value, Second.Value?)
    }

    /// The first gesture in a sequence of two gestures.
    public var first: First

    /// The second gesture in a sequence of two gestures.
    public var second: Second

    /// Creates a sequence gesture with two gestures.
    ///
    /// - Parameters:
    ///   - first: The first gesture of the sequence.
    ///   - second: The second gesture of the sequence.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { SequenceGestureNode<First, Second>() }
        node.first = First._makeGesture(gesture: gesture.first, inputs: inputs.child(0)).node
        node.second = Second._makeGesture(gesture: gesture.second, inputs: inputs.child(1)).node
        return _GestureOutputs(node)
    }
}

extension SequenceGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}
extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

// MARK: - ExclusiveGesture

/// A gesture that consists of two gestures where only one of them can
/// succeed.
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
    /// The value of an exclusive gesture that indicates which of two gestures
    /// succeeded.
    public enum Value {
        /// The first of two gestures succeeded.
        case first(First.Value)

        /// The second of two gestures succeeded.
        case second(Second.Value)
    }

    /// The first of two gestures.
    public var first: First

    /// The second of two gestures.
    public var second: Second

    /// Creates a gesture from two gestures where only one of them succeeds.
    ///
    /// - Parameters:
    ///   - first: The first of two gestures. This gesture has precedence over
    ///     the other gesture.
    ///   - second: The second of two gestures.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { ExclusiveGestureNode<First, Second>() }
        node.first = First._makeGesture(gesture: gesture.first, inputs: inputs.child(0)).node
        node.second = Second._makeGesture(gesture: gesture.second, inputs: inputs.child(1)).node
        return _GestureOutputs(node)
    }
}

extension ExclusiveGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}
extension ExclusiveGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

// MARK: - Recognizers

/// Whether a part of a combined gesture has nothing more to say: it finished,
/// or never took part.
private func isSettled(_ phase: GesturePhase) -> Bool {
    phase.isTerminal || phase == .idle
}

/// Feeds both parts every input.
final class SimultaneousGestureNode<First: Gesture, Second: Gesture>: GestureNode<SimultaneousGesture<First, Second>.Value> {
    var first = GestureNode<First.Value>()
    var second = GestureNode<Second.Value>()

    override func receive(_ input: GestureInput, deliver: Bool) {
        first.receive(input, deliver: deliver)
        second.receive(input, deliver: deliver)
        recompute()
    }

    override func flush() {
        first.flush()
        second.flush()
    }

    override func cancel() {
        first.cancel()
        second.cancel()
        recompute()
    }

    override var deadline: Int64? {
        [first.deadline, second.deadline].compactMap { $0 }.min()
    }

    private func recompute() {
        let phases = (first.phase, second.phase)
        if phases.0 == .idle, phases.1 == .idle {
            phase = .idle
        } else if isSettled(phases.0), isSettled(phases.1) {
            phase = phases.0 == .ended || phases.1 == .ended ? .ended : .failed
        } else if phases.0.hasRecognized || phases.1.hasRecognized {
            phase = .active
        } else {
            phase = .possible
        }
        let firstValue = phases.0 == .failed ? nil : first.value
        let secondValue = phases.1 == .failed ? nil : second.value
        report(firstValue == nil && secondValue == nil ? nil : SimultaneousGesture<First, Second>.Value(first: firstValue, second: secondValue))
    }
}

/// Feeds the first part until it succeeds, then the second.
final class SequenceGestureNode<First: Gesture, Second: Gesture>: GestureNode<SequenceGesture<First, Second>.Value> {
    var first = GestureNode<First.Value>()
    var second = GestureNode<Second.Value>()

    /// Whether the first part has succeeded and the second is being fed.
    private var onSecond = false

    /// Whether the second part has had its first event.
    private var secondStarted = false

    override func receive(_ input: GestureInput, deliver: Bool) {
        if case .pointer(let pointer) = input, pointer.kind == .down, !onSecond || isSettled(phase) {
            onSecond = false
            secondStarted = false
        }
        if onSecond {
            feedSecond(input, deliver: deliver)
        } else {
            first.receive(input, deliver: deliver)
            if first.phase == .ended { onSecond = true }
        }
        recompute()
    }

    /// The second part takes the first event after the first part succeeded as
    /// its press: a move becomes its start, a release its start and end.
    private func feedSecond(_ input: GestureInput, deliver: Bool) {
        guard case .pointer(let pointer) = input, !secondStarted else {
            second.receive(input, deliver: deliver)
            return
        }
        secondStarted = true
        second.receive(.pointer(pointer.asDown), deliver: deliver)
        if pointer.kind == .up { second.receive(input, deliver: deliver) }
    }

    override func flush() {
        first.flush()
        if onSecond { second.flush() }
    }

    override func cancel() {
        first.cancel()
        if onSecond { second.cancel() }
        recompute()
    }

    override var deadline: Int64? { onSecond ? second.deadline : first.deadline }

    private func recompute() {
        guard onSecond else {
            phase = first.phase
            report(first.value.map { .first($0) })
            return
        }
        guard let firstValue = first.value else {
            phase = .failed
            report(nil)
            return
        }
        switch second.phase {
        case .ended: phase = .ended
        case .failed: phase = .failed
        default: phase = .active
        }
        report(phase == .failed ? nil : .second(firstValue, second.value))
    }
}

/// Feeds both parts, holding the second back until the first fails.
final class ExclusiveGestureNode<First: Gesture, Second: Gesture>: GestureNode<ExclusiveGesture<First, Second>.Value> {
    var first = GestureNode<First.Value>()
    var second = GestureNode<Second.Value>()

    /// Whether the second part has been told it may report — the first having
    /// failed — during the gesture under way.
    private var secondReleased = false

    override func receive(_ input: GestureInput, deliver: Bool) {
        if case .pointer(let pointer) = input, pointer.kind == .down, isSettled(phase) {
            secondReleased = false
        }
        first.receive(input, deliver: deliver)
        if first.phase.hasRecognized {
            if !isSettled(second.phase) { second.cancel() }
        } else if first.phase == .failed {
            // Fed first, then told: what it held back is what it has now, as
            // macOS reports a gesture that won only when the one ahead of it
            // gave up — its end alone, if it had already ended.
            second.receive(input, deliver: deliver && secondReleased)
            if deliver, !secondReleased {
                secondReleased = true
                second.flush()
            }
        } else {
            second.receive(input, deliver: false)
        }
        recompute()
    }

    override func flush() {
        first.flush()
        if first.phase == .failed {
            secondReleased = true
            second.flush()
        }
    }

    override func cancel() {
        first.cancel()
        second.cancel()
        recompute()
    }

    override var deadline: Int64? {
        [first.deadline, second.deadline].compactMap { $0 }.min()
    }

    private func recompute() {
        if first.phase == .failed {
            phase = second.phase
            report(second.value.map { .second($0) })
        } else if first.phase.hasRecognized {
            phase = first.phase
            report(first.value.map { .first($0) })
        } else {
            phase = first.phase == .idle && second.phase == .idle ? .idle : .possible
            report(first.value.map { .first($0) })
        }
    }
}
