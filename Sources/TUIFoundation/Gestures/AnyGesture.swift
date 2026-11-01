//  🖥️ TUI — A Terminal UI framework for Swift
//  AnyGesture.swift
//
//  SwiftUI's type-erased gesture, and an optional gesture.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A type-erased gesture.
///
/// ```swift
/// var gesture: AnyGesture<Void> {
///     isEditing ? AnyGesture(TapGesture(count: 2)) : AnyGesture(TapGesture())
/// }
/// ```
///
/// When the wrapped gesture changes type, its recognizer starts afresh, as a
/// view's state does when its type changes.
public struct AnyGesture<Value>: Gesture {
    /// The erased gesture: what a recognizer needs of it, and the named spaces
    /// it reports locations in (`PointerSpaceReporting`), each of which needs
    /// the main actor, where an `AnyGesture` can be made anywhere. A reference
    /// the memos hash by its address, as they hashed the closure's context this
    /// replaced.
    private let erased: ErasedGesture<Value>

    /// Creates an instance from another gesture.
    ///
    /// - Parameter gesture: A gesture that you use to create a new gesture.
    public init<T: Gesture>(_ gesture: T) where Value == T.Value {
        erased = ConcreteErasedGesture(gesture: gesture)
    }

    /// The named spaces the erased gesture reports locations in.
    var pointerSpaces: [CoordinateSpace] { erased.pointerSpaces }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        gesture.erased.make(inputs.child(0))
    }
}

/// What ``AnyGesture`` keeps. Its methods alone are on the main actor, so that
/// one can be made anywhere and read where gestures are made.
private class ErasedGesture<Value> {
    // swiftlint:disable:next unavailable_function
    @MainActor func make(_ inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError("ConcreteErasedGesture overrides this")
    }

    @MainActor var pointerSpaces: [CoordinateSpace] {
        fatalError("ConcreteErasedGesture overrides this")
    }
}

private final class ConcreteErasedGesture<G: Gesture>: ErasedGesture<G.Value> {
    let gesture: G

    init(gesture: G) {
        self.gesture = gesture
    }

    @MainActor override func make(_ inputs: _GestureInputs) -> _GestureOutputs<G.Value> {
        G._makeGesture(gesture: gesture, inputs: inputs)
    }

    @MainActor override var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: gesture) }
}

// MARK: - Optional

extension Optional: Gesture where Wrapped: Gesture {
    /// An absent gesture recognizes nothing; a present one is recognized as
    /// itself — what lets `.gesture(isEnabled ? drag : nil)` compile.
    public typealias Value = Wrapped.Value

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Wrapped.Value> {
        switch gesture {
        case .some(let wrapped):
            Wrapped._makeGesture(gesture: wrapped, inputs: inputs.child(0))
        case .none:
            _GestureOutputs(inputs.node(at: 1) { InertGestureNode<Wrapped.Value>() })
        }
    }
}

/// The recognizer of a gesture that never recognizes — an absent optional
/// gesture.
final class InertGestureNode<Value>: GestureNode<Value> {
    override func receive(_ input: GestureInput, deliver: Bool) {
        if case .pointer(let pointer) = input, pointer.kind == .down { phase = .failed }
    }
}
