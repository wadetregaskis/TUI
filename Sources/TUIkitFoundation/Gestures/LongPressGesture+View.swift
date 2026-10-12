//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LongPressGesture+View.swift
//
//  SwiftUI's `onLongPressGesture`: a ``LongPressGesture`` attached with
//  `gesture(_:including:)`, with a pressing callback beside its action.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension View {
    /// Adds an action to perform when this view recognizes a long press
    /// gesture.
    ///
    /// ```swift
    /// Text(item.name)
    ///     .onLongPressGesture {
    ///         showDetails(item)
    ///     } onPressingChanged: { pressing in
    ///         isHighlighted = pressing
    ///     }
    /// ```
    ///
    /// The ``LongPressGesture`` it attaches with ``gesture(_:including:)``, and so
    /// ranked as that is: a gesture inside the view, or the view's own press if
    /// it is a control, comes first — a `Button`'s press runs the button however
    /// long it is held, and a tap inside the view that is still undecided holds
    /// the long press up (both measured on macOS 15.8).
    ///
    /// `onPressingChanged` hears `true` when the button goes down and `false`
    /// when the press is over: when it succeeds — just before the action runs,
    /// the order macOS uses — when the button comes up first, or when the
    /// pointer strays.
    ///
    /// - Parameters:
    ///   - minimumDuration: The minimum duration of the long press that must
    ///     elapse before the gesture succeeds, in seconds.
    ///   - maximumDistance: How far, in cells along either axis, the pointer
    ///     may move from where the press began before the gesture fails —
    ///     cells where SwiftUI counts points (§2.1 of
    ///     `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`). One cell by default, the
    ///     nearest a terminal comes to SwiftUI's ten points.
    ///   - action: The action to perform when a long press is recognized.
    ///   - onPressingChanged: A closure to run when the pressing state of the
    ///     gesture changes, passing the current state as a parameter.
    /// - Returns: The view, with the long press attached.
    public func onLongPressGesture(
        minimumDuration: Double = 0.5, maximumDistance: Int = 1, perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        gesture(
            _PressingLongPressGesture(
                base: LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance),
                onPressingChanged: onPressingChanged
            )
            .onEnded { _ in action() })
    }
}

/// A long press that reports when it starts and stops being pressed — the
/// gesture behind ``View/onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)``.
struct _PressingLongPressGesture: Gesture {
    let base: LongPressGesture
    let onPressingChanged: ((Bool) -> Void)?

    typealias Value = Bool
    typealias Body = Never

    static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Bool> {
        let base = LongPressGesture._makeGesture(gesture: gesture.base, inputs: inputs.child(0))
        guard let onPressingChanged = gesture.onPressingChanged else { return base }
        let node = inputs.node { PressingGestureNode() }
        node.child = base.node
        node.onPressingChanged = onPressingChanged
        return _GestureOutputs(node)
    }
}

/// Reports `true` once the press it wraps is under way and `false` once it is
/// over, however it ends.
final class PressingGestureNode: PassThroughGestureNode<Bool> {
    var onPressingChanged: (Bool) -> Void = { _ in }
    private var pressing = false

    override func deliverOwn() {
        let isPressing = phase == .possible || phase == .active
        guard isPressing != pressing else { return }
        pressing = isPressing
        onPressingChanged(isPressing)
    }
}
