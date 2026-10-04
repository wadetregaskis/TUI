//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyGesture.swift
//
//  SwiftUI's type-erased gesture, and an optional gesture.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
    /// The erased gesture, kept as the one thing a recognizer needs of it.
    private let makeGesture: @MainActor (_GestureInputs) -> _GestureOutputs<Value>

    /// Creates an instance from another gesture.
    ///
    /// - Parameter gesture: A gesture that you use to create a new gesture.
    public init<T: Gesture>(_ gesture: T) where Value == T.Value {
        makeGesture = { T._makeGesture(gesture: gesture, inputs: $0) }
    }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        gesture.makeGesture(inputs.child(0))
    }
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
