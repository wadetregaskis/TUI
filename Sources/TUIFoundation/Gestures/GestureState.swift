//  🖥️ TUI — A Terminal UI framework for Swift
//  GestureState.swift
//
//  SwiftUI's `@GestureState`: view state a gesture writes while it runs and
//  that goes back to its initial value when the gesture ends, however it ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A property wrapper type that updates a property while the user performs a
/// gesture and resets the property back to its initial state when the gesture
/// ends.
///
/// Declare a property as `@GestureState`, pass as a binding to it as a
/// parameter to a gesture's ``Gesture/updating(_:body:)`` callback, and
/// receive updates to it. A property that's declared as `@GestureState`
/// implicitly resets when the gesture becomes inactive, making it suitable
/// for tracking transient state.
///
/// ```swift
/// struct SimpleLongPressGestureView: View {
///     @GestureState private var isDetectingLongPress = false
///
///     var longPress: some Gesture {
///         LongPressGesture(minimumDuration: 3)
///             .updating($isDetectingLongPress) { currentState, gestureState, transaction in
///                 gestureState = currentState
///             }
///     }
///
///     var body: some View {
///         Text(isDetectingLongPress ? "Pressing" : "Press me")
///             .gesture(longPress)
///     }
/// }
/// ```
///
/// The reset happens when the gesture ends, fails or is cancelled by another
/// gesture taking the pointer, before any `onEnded` action runs (the order
/// measured on macOS 15.8) — and only for a gesture that wrote the state.
@propertyWrapper
public struct GestureState<Value>: DynamicProperty {
    /// The storage, bound to the view's identity like any `@State`.
    fileprivate var state: State<Value>

    /// What the property goes back to.
    fileprivate let initialValue: Value

    /// Called with the value being reset, to choose the reset's transaction.
    fileprivate let reset: (Value, inout Transaction) -> Void

    /// Creates a view state that's derived from a gesture.
    ///
    /// - Parameter wrappedValue: A wrapped value for the gesture state
    ///   property.
    public init(wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue, resetTransaction: Transaction())
    }

    /// Creates a view state that's derived from a gesture.
    ///
    /// - Parameter initialValue: An initial value for the gesture state
    ///   property.
    public init(initialValue: Value) {
        self.init(wrappedValue: initialValue, resetTransaction: Transaction())
    }

    /// Creates a view state that's derived from a gesture and a transaction
    /// to reset it.
    ///
    /// - Parameters:
    ///   - wrappedValue: A wrapped value for the gesture state property.
    ///   - resetTransaction: A transaction that provides metadata for view
    ///     updates.
    public init(wrappedValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: wrappedValue) { _, transaction in transaction = resetTransaction }
    }

    /// Creates a view state that's derived from a gesture and a transaction
    /// to reset it.
    ///
    /// - Parameters:
    ///   - initialValue: An initial value for the gesture state property.
    ///   - resetTransaction: A transaction that provides metadata for view
    ///     updates.
    public init(initialValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: initialValue, resetTransaction: resetTransaction)
    }

    /// Creates a view state that's derived from a gesture and a closure that
    /// provides a transaction to reset it.
    ///
    /// - Parameters:
    ///   - wrappedValue: A wrapped value for the gesture state property.
    ///   - reset: A callback in which you can modify the transaction used to
    ///     reset the property, given the value being reset.
    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        self.state = State(wrappedValue: wrappedValue)
        self.initialValue = wrappedValue
        self.reset = reset
    }

    /// Creates a view state that's derived from a gesture and a closure that
    /// provides a transaction to reset it.
    ///
    /// - Parameters:
    ///   - initialValue: An initial value for the gesture state property.
    ///   - reset: A callback in which you can modify the transaction used to
    ///     reset the property, given the value being reset.
    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        self.init(wrappedValue: initialValue, reset: reset)
    }

    /// The wrapped value referenced by the gesture state property.
    public var wrappedValue: Value {
        state.wrappedValue
    }

    /// A binding to the gesture state property — the gesture state itself,
    /// which ``Gesture/updating(_:body:)`` takes.
    public var projectedValue: GestureState<Value> {
        self
    }

    /// Nothing to do before the body runs: the storage is bound with the
    /// view's other state.
    public mutating func update() {}

    // MARK: Writing

    /// Writes `value` as a gesture's update, in `transaction`.
    @MainActor
    func write(_ value: Value, transaction: Transaction) {
        let state = self.state
        withTransaction(transaction) { state.wrappedValue = value }
    }

    /// Puts the initial value back, in the transaction `reset` chooses.
    @MainActor
    func resetToInitialValue() {
        var transaction = Transaction()
        reset(state.wrappedValue, &transaction)
        write(initialValue, transaction: transaction)
    }
}

/// Its `@State` is bound with the view's, but its `update()` does nothing, so
/// a view holding it is not one whose app properties are updated.
extension GestureState: FrameworkPropertyContainer {}

extension GestureState where Value: ExpressibleByNilLiteral {
    /// Creates a view state that's derived from a gesture with an initial
    /// value of `nil`, and a transaction to reset it.
    ///
    /// - Parameter resetTransaction: A transaction that provides metadata for
    ///   view updates.
    public init(resetTransaction: Transaction = Transaction()) {
        self.init(wrappedValue: nil, resetTransaction: resetTransaction)
    }

    /// Creates a view state that's derived from a gesture with an initial
    /// value of `nil`, and a closure that provides a transaction to reset it.
    ///
    /// - Parameter reset: A callback in which you can modify the transaction
    ///   used to reset the property, given the value being reset.
    public init(reset: @escaping (Value, inout Transaction) -> Void) {
        self.init(wrappedValue: nil, reset: reset)
    }
}

// MARK: - updating(_:body:)

extension Gesture {
    /// Updates the provided gesture state property as the gesture's value
    /// changes.
    ///
    /// - Parameters:
    ///   - state: A binding to a view's ``GestureState`` property.
    ///   - body: The callback that is invoked as the gesture's value changes.
    ///     Its `currentState` parameter is the updated state of the gesture.
    ///     The `gestureState` parameter is the previous state of the gesture,
    ///     and the `transaction` is the context of the gesture.
    /// - Returns: A version of the gesture that updates the provided `state`
    ///   as the originating gesture's value changes and that resets the
    ///   `state` to its initial value when the user or the system ends or
    ///   cancels the gesture.
    public func updating<State>(
        _ state: GestureState<State>,
        body: @escaping (Value, inout State, inout Transaction) -> Void
    ) -> GestureStateGesture<Self, State> {
        GestureStateGesture(base: self, state: state, body: body)
    }
}

/// A gesture that updates the state provided by a gesture's updating callback.
///
/// A gesture's ``Gesture/updating(_:body:)`` callback returns a
/// `GestureStateGesture` instance for updating a transient state property
/// that's annotated with the ``GestureState`` property wrapper.
public struct GestureStateGesture<Base: Gesture, State>: Gesture {
    /// The type representing the gesture's value.
    public typealias Value = Base.Value

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    /// The originating gesture.
    public var base: Base

    /// A value that changes as the user performs the gesture.
    public var state: GestureState<State>

    /// The updating gesture containing the originating gesture's value, the
    /// updated state of the gesture, and a transaction.
    public var body: (GestureStateGesture<Base, State>.Value, inout State, inout Transaction) -> Void

    /// Creates a new gesture that's the result of an ongoing gesture.
    ///
    /// - Parameters:
    ///   - base: The originating gesture.
    ///   - state: The wrapped value of a ``GestureState`` property.
    ///   - body: The callback that SwiftUI invokes as the gesture's value
    ///     changes.
    public init(
        base: Base, state: GestureState<State>,
        body: @escaping (GestureStateGesture<Base, State>.Value, inout State, inout Transaction) -> Void
    ) {
        self.base = base
        self.state = state
        self.body = body
    }

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { GestureStateGestureNode<Value, State>() }
        node.child = Base._makeGesture(gesture: gesture.base, inputs: inputs.child(0)).node
        node.state = gesture.state
        node.update = gesture.body
        return _GestureOutputs(node)
    }
}

// MARK: - Recognizer

/// Writes the gesture's value into a `@GestureState` while it runs, and resets
/// it when the gesture is over.
final class GestureStateGestureNode<Value, State>: PassThroughGestureNode<Value> {
    var state: GestureState<State>?
    var update: (Value, inout State, inout Transaction) -> Void = { _, _, _ in }

    /// The child's report this node last wrote.
    private var writtenVersion: Int?

    /// Whether the gesture under way has written the state, and so owes it a
    /// reset.
    private var touched = false

    override func deliverOwn() {
        guard let state else { return }
        switch phase {
        case .possible, .active:
            guard let value, writtenVersion != version else { return }
            writtenVersion = version
            var current = state.wrappedValue
            var transaction = Transaction()
            update(value, &current, &transaction)
            state.write(current, transaction: transaction)
            touched = true
        case .ended, .failed, .idle:
            writtenVersion = nil
            guard touched else { return }
            touched = false
            state.resetToInitialValue()
        }
    }

    override func receive(_ input: GestureInput, deliver: Bool) {
        super.receive(input, deliver: deliver)
        // A reset is owed whatever is holding delivery back: it undoes a write
        // that was delivered, never one that was not.
        if !deliver, phase.isTerminal, touched { deliverOwn() }
    }
}
