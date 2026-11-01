//  🖥️ TUI — A Terminal UI framework for Swift
//  CompositeGestures.swift
//
//  SwiftUI's gesture algebra: two gestures at once, one after the other, or
//  one in place of the other — each as measured on macOS 15.8.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

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
    nonisolated public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> {
        SimultaneousGesture(self, other)
    }

    /// Sequences a gesture with another one to create a new gesture, which
    /// results in the second gesture only receiving events after the first
    /// gesture succeeds.
    ///
    /// The second gesture starts with the event that ended the first, when
    /// an event did: a tap's release is a following tap's press and release,
    /// so `TapGesture().sequenced(before: TapGesture())` ends at one click,
    /// and a long press with no minimum duration hands a following drag its
    /// press. A release is a press already over, of which the second gesture
    /// reports only how it ends: after a tap, a drag or a long press fails
    /// at once, so `TapGesture().sequenced(before: DragGesture())` never
    /// ends, and holds nothing back — inside `.onTapGesture`, every click
    /// runs both taps — while a long press with no minimum duration ends
    /// there, `false`.
    /// A second gesture that is itself a sequence hands its own second that
    /// press, still over: after a tap, two zero-duration long presses in
    /// sequence both end `false`, the first's `onEnded` before the second's.
    /// A long press that ends on its clock, the button still down, hands a
    /// following drag the next move as its start. The sequence ends when the
    /// second gesture does (all measured on macOS 15.8).
    ///
    /// - Parameter other: A gesture you want to combine with another gesture
    ///   to create a new, sequenced gesture.
    /// - Returns: A gesture that's a sequence of two gestures.
    nonisolated public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> {
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
    ///   only one of them can succeed. TUI gives precedence to the first
    ///   gesture.
    nonisolated public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> {
        ExclusiveGesture(self, other)
    }
}

// MARK: - SimultaneousGesture

/// A gesture containing two gestures that can happen at the same time with
/// neither of them preceding the other.
nonisolated public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
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

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
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
nonisolated public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
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

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
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
nonisolated public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
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

    @MainActor public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
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

    /// Whether the second part has had its first event in the sequence under
    /// way. Until it has, the second part is where the LAST sequence left it
    /// — ended, most likely — and nothing of it is read: a sequence that
    /// restarted at a press and whose first part then ended took that old end
    /// for its own and ran `onEnded` with the old value, at the press for a
    /// long press with no minimum duration and at the end tick for any other,
    /// then again at the release.
    private var secondStarted = false

    /// Whether the first part ended with delivery off, and has not reported
    /// that end yet. Only a sequence that is itself a second part sees this
    /// without a ``flush()`` to follow: it is handed the press already over
    /// (``GesturePointer/isOver``) with delivery off and the release with
    /// it on, and the release goes to its second part alone. Measured on
    /// macOS 15.8, a tap before a sequence of two zero-duration long presses
    /// runs the first long press's `onEnded` at the tap's release, before
    /// the second's; until then it never ran.
    private var firstHeld = false

    override func receive(_ input: GestureInput, deliver: Bool) {
        if case .pointer(let pointer) = input, pointer.kind == .down, !onSecond || isSettled(phase) {
            onSecond = false
            secondStarted = false
            firstHeld = false
        }
        if onSecond {
            if deliver, firstHeld {
                firstHeld = false
                first.flush()
            }
            feedSecond(input, deliver: deliver)
        } else {
            first.receive(input, deliver: deliver)
            if first.phase == .ended {
                onSecond = true
                firstHeld = !deliver
                // The event that ended the first part is the second's first,
                // as on macOS 15.8: fed only the events after it, a tap
                // before a tap waited for a second click, and a drag after a
                // long press with no minimum duration started at the first
                // move, not at the press. A first part that ended on a tick
                // leaves the second to the next event.
                feedSecond(input, deliver: deliver)
            }
        }
        recompute()
    }

    /// Feeds the second part, which takes its first pointer event as its
    /// press: a move becomes its start; a release, a press already over
    /// (``GesturePointer/isOver``), heard with the release, of which the
    /// second part reports only how it ends. Measured on macOS 15.8, after
    /// a tap: a long press runs no `onChanged` and fails, or with no
    /// minimum duration ends `false`; a drag with no minimum distance ends
    /// without an `onChanged`. Fed as a press and then a release, the long
    /// press ran `onChanged(true)` and ended `true`, and the drag reported
    /// its start. A tick before the first pointer event is not the second
    /// part's to hear.
    private func feedSecond(_ input: GestureInput, deliver: Bool) {
        if secondStarted {
            second.receive(input, deliver: deliver)
        } else if case .pointer(let pointer) = input {
            secondStarted = true
            let isRelease = pointer.kind == .up
            second.receive(.pointer(pointer.asDown), deliver: deliver && !isRelease)
            if isRelease { second.receive(input, deliver: deliver) }
        }
    }

    override func flush() {
        firstHeld = false
        first.flush()
        if secondStarted { second.flush() }
    }

    override func cancel() {
        firstHeld = false
        first.cancel()
        if secondStarted { second.cancel() }
        recompute()
    }

    override var deadline: Int64? {
        guard onSecond else { return first.deadline }
        return secondStarted ? second.deadline : nil
    }

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
        guard secondStarted else {
            // Under way, the second part not yet begun (`secondStarted`).
            phase = .active
            report(.second(firstValue, nil))
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
        var begins = false
        if case .pointer(let pointer) = input, pointer.kind == .down, isSettled(phase) {
            begins = true
            secondReleased = false
        }
        // An end the second part reached while held back is kept until the
        // first fails, and the second hears nothing more meanwhile — not even
        // a press that would start it again. The arena's rule for a gesture
        // held back behind another (`GestureArena`), between the two parts.
        let secondHoldsEnd = !begins && !secondReleased && second.phase == .ended
        first.receive(input, deliver: deliver)
        if first.phase.hasRecognized {
            if !isSettled(second.phase) { second.cancel() }
        } else if first.phase == .failed, secondHoldsEnd {
            // The end came before this input: reported first, and the input
            // then goes to it as to any gesture under way.
            if deliver {
                secondReleased = true
                second.flush()
                second.receive(input, deliver: true)
            }
        } else if first.phase == .failed {
            // Fed first, then told: what it held back is what it has now, as
            // macOS reports a gesture that won only when the one ahead of it
            // gave up — its end alone, if it had already ended.
            second.receive(input, deliver: deliver && secondReleased)
            if deliver, !secondReleased {
                secondReleased = true
                second.flush()
            }
        } else if !secondHoldsEnd {
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
