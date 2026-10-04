//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LongPressGesture.swift
//
//  SwiftUI's `LongPressGesture`, with the behaviour macOS 15.8's SwiftUI was
//  measured to have.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A gesture that succeeds when the user performs a long press.
///
/// To recognize a long-press gesture on a view, create and configure the
/// gesture, then add it to the view using the ``View/gesture(_:including:)``
/// modifier:
///
/// ```swift
/// struct LongPressGestureView: View {
///     @GestureState private var isDetectingLongPress = false
///     @State private var completedLongPress = false
///
///     var longPress: some Gesture {
///         LongPressGesture(minimumDuration: 3)
///             .updating($isDetectingLongPress) { currentState, gestureState, transaction in
///                 gestureState = currentState
///             }
///             .onEnded { finished in
///                 self.completedLongPress = finished
///             }
///     }
///
///     var body: some View {
///         Text(isDetectingLongPress ? "Pressing" : completedLongPress ? "Done" : "Press me")
///             .gesture(longPress)
///     }
/// }
/// ```
///
/// The press is the left mouse button, held on the view. As measured on
/// macOS 15.8, the gesture's value is `true` from the moment the button goes
/// down — `onChanged` and `updating(_:body:)` hear it then — and it ends,
/// still `true`, once the button has been held for `minimumDuration`, without
/// waiting for the release. Letting go first, or moving further than
/// `maximumDistance`, fails it.
///
/// The end lands on a frame the run loop wakes for at the deadline, so it is
/// as punctual as the frame clock.
public struct LongPressGesture: Gesture {
    /// The minimum duration of the long press that must elapse before the
    /// gesture succeeds.
    public var minimumDuration: Double

    /// The maximum distance that the long press can move before the gesture
    /// fails, in cells along either axis — cells where SwiftUI counts points
    /// (§2.1 of `Documentation/SwiftUI-compatibility.md`).
    public var maximumDistance: Int

    /// Creates a long-press gesture with a minimum duration and a maximum
    /// distance that the interaction can move before the gesture fails.
    ///
    /// - Parameters:
    ///   - minimumDuration: The minimum duration of the long press that must
    ///     elapse before the gesture succeeds, in seconds.
    ///   - maximumDistance: The maximum distance that the cursor performing
    ///     the long press can move before the gesture fails: one cell by
    ///     default, the nearest a terminal comes to SwiftUI's ten points.
    public init(minimumDuration: Double = 0.5, maximumDistance: Int = 1) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    /// The type representing the gesture's value.
    public typealias Value = Bool

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Bool> {
        let node = inputs.node { LongPressGestureNode() }
        node.minimumDuration = gesture.minimumDuration
        node.maximumDistance = max(0, gesture.maximumDistance)
        return _GestureOutputs(node)
    }
}

// MARK: - Recognizer

/// Recognizes a press held still for a minimum duration.
final class LongPressGestureNode: GestureNode<Bool> {
    var minimumDuration: Double = 0.5
    var maximumDistance = 1

    private var origin = CellPoint.zero
    private var timer = GestureTimer()

    override func receive(_ input: GestureInput, deliver: Bool) {
        switch input {
        case .pointer(let pointer):
            receive(pointer)
        case .tick(let now):
            guard phase == .possible, timer.hasExpired(at: now) else { return }
            timer.disarm()
            phase = .ended
            report(true)
        }
    }

    private func receive(_ pointer: GesturePointer) {
        switch pointer.kind {
        case .down:
            origin = pointer.globalLocation
            if minimumDuration <= 0 {
                phase = .ended
                report(true)
            } else {
                phase = .possible
                timer.arm(seconds: minimumDuration)
                report(true)
            }
        case .moved:
            guard phase == .possible else { return }
            let location = pointer.globalLocation
            if max(abs(location.x - origin.x), abs(location.y - origin.y)) > maximumDistance {
                cancel()
            }
        case .up:
            // Released before the minimum duration: the press fails. Once it
            // has ended, the release adds nothing.
            if phase == .possible { cancel() }
        }
    }

    override func cancel() {
        timer.disarm()
        phase = .failed
        report(nil)
    }

    override var deadline: Int64? { phase == .possible ? timer.deadline : nil }
}
