//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragGesture.swift
//
//  SwiftUI's `DragGesture`, in cells, with a velocity read from the times the
//  terminal's motion reports arrive.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

/// A dragging motion that invokes an action as the drag-event sequence
/// changes.
///
/// To recognize a drag gesture on a view, create and configure the gesture,
/// and then add it to the view using the ``View/gesture(_:including:)``
/// modifier:
///
/// ```swift
/// struct DragGestureView: View {
///     @State private var isDragging = false
///
///     var drag: some Gesture {
///         DragGesture()
///             .onChanged { _ in self.isDragging = true }
///             .onEnded { _ in self.isDragging = false }
///     }
///
///     var body: some View {
///         Text(isDragging ? "Dragging" : "Drag me")
///             .gesture(drag)
///     }
/// }
/// ```
///
/// The drag is the left mouse button, held and moved. It starts once the
/// pointer is `minimumDistance` cells from the press along either axis — at
/// the press itself when that is zero — and ends with the release, which
/// `onEnded` hears only if the drag started. Its value is in cells
/// (§2.2 of `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`).
public struct DragGesture: Gesture {
    /// The attributes of a drag gesture.
    public struct Value: Equatable, Sendable {
        /// The time associated with the drag gesture's current event.
        public var time: Date

        /// The location of the drag gesture's current event.
        public var location: CellPoint

        /// The location of the drag gesture's first event.
        public var startLocation: CellPoint

        /// The current drag velocity, in cells per second: a rate, so
        /// fractional where a position is whole (a ``CellVector``, the
        /// counterpart of the `CGSize` SwiftUI reports).
        ///
        /// Estimated from the times the terminal's motion reports arrived, as a
        /// Mac mouse's is from its events' timestamps, and smoothed across
        /// reports. A pointer held still sends no reports, so the velocity is
        /// the last motion's — as macOS 15.8's is, measured.
        public internal(set) var velocity: CellVector

        /// The total translation from the start of the drag gesture to the
        /// current event of the drag gesture.
        ///
        /// This is equivalent to `location.{x,y} - startLocation.{x,y}`.
        public var translation: CellSize {
            CellSize(width: location.x - startLocation.x, height: location.y - startLocation.y)
        }

        /// A prediction, based on the current drag velocity, of where the
        /// final location will be if dragging stopped now: a quarter of a
        /// second at the current velocity on from the location, the horizon
        /// SwiftUI's own `velocity` is defined against.
        public var predictedEndLocation: CellPoint {
            CellPoint(
                x: location.x + Int((velocity.dx * Self.predictionHorizon).rounded()),
                y: location.y + Int((velocity.dy * Self.predictionHorizon).rounded()))
        }

        /// A prediction, based on the current drag velocity, of what the final
        /// translation will be if dragging stopped now.
        public var predictedEndTranslation: CellSize {
            let end = predictedEndLocation
            return CellSize(width: end.x - startLocation.x, height: end.y - startLocation.y)
        }

        /// How far ahead the prediction looks, in seconds. SwiftUI defines its
        /// velocity as four times the predicted end's distance from the
        /// location, so its prediction is a quarter-second one.
        static let predictionHorizon = 0.25
    }

    /// The minimum dragging distance before the gesture succeeds, in cells
    /// along either axis.
    public var minimumDistance: Int

    /// The coordinate space in which to receive location values.
    public var coordinateSpace: CoordinateSpace

    /// Creates a dragging gesture with the minimum dragging distance before
    /// the gesture succeeds and the coordinate space of the gesture's
    /// location.
    ///
    /// - Parameters:
    ///   - minimumDistance: The minimum dragging distance for the gesture to
    ///     succeed, in cells along either axis: one by default — the smallest
    ///     move a terminal reports, the nearest it comes to SwiftUI's ten
    ///     points.
    ///   - coordinateSpace: The coordinate space of the dragging gesture's
    ///     location: `.local`, the view's own top-left cell, or `.global`.
    public init(minimumDistance: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.init(minimumDistance: minimumDistance, coordinateSpace: coordinateSpace.coordinateSpace)
    }

    /// Creates a dragging gesture with the coordinate space given as a
    /// ``CoordinateSpace`` value — the form SwiftUI deprecated for the
    /// protocol one, kept as `onTapGesture(count:coordinateSpace:perform:)`
    /// keeps it.
    ///
    /// - Parameters:
    ///   - minimumDistance: The minimum dragging distance for the gesture to
    ///     succeed, in cells along either axis.
    ///   - coordinateSpace: `.local` or `.global`.
    @_disfavoredOverload
    public init(minimumDistance: Int = 1, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { DragGestureNode() }
        node.minimumDistance = max(0, gesture.minimumDistance)
        node.coordinateSpace = gesture.coordinateSpace
        return _GestureOutputs(node)
    }
}

// MARK: - Recognizer

/// Recognizes a press moved at least a minimum distance, and follows it to
/// its release.
final class DragGestureNode: GestureNode<DragGesture.Value> {
    var minimumDistance = 1
    var coordinateSpace = CoordinateSpace.local

    private var start = CellPoint.zero
    private var last = CellPoint.zero
    private var lastTime: Int64 = 0
    private var velocity = CellVector(dx: 0, dy: 0)
    private var hasVelocity = false

    override func receive(_ input: GestureInput, deliver: Bool) {
        guard case .pointer(let pointer) = input else { return }
        let location = pointer.location(in: coordinateSpace)
        switch pointer.kind {
        case .down:
            start = location
            last = location
            lastTime = pointer.timeNanos
            velocity = CellVector(dx: 0, dy: 0)
            hasVelocity = false
            if minimumDistance == 0 {
                phase = .active
                report(currentValue(at: location))
            } else {
                phase = .possible
                report(nil)
            }
        case .moved:
            guard phase == .possible || phase == .active else { return }
            track(location, at: pointer.timeNanos)
            if phase == .possible,
                max(abs(location.x - start.x), abs(location.y - start.y)) >= minimumDistance
            {
                phase = .active
            }
            if phase == .active { report(currentValue(at: location)) }
        case .up:
            switch phase {
            case .active:
                track(location, at: pointer.timeNanos)
                phase = .ended
                report(currentValue(at: location))
            case .possible:
                cancel()
            default:
                break
            }
        }
    }

    override func cancel() {
        phase = .failed
        report(nil)
    }

    /// Folds one report into the velocity: the speed of the move it made,
    /// averaged with the estimate so far. A report that did not move — a
    /// release where the last drag left the pointer — leaves it as it was.
    private func track(_ location: CellPoint, at time: Int64) {
        let elapsed = Double(time - lastTime) / 1_000_000_000
        guard location != last, elapsed > 0 else { return }
        let instant = CellVector(
            dx: Double(location.x - last.x) / elapsed, dy: Double(location.y - last.y) / elapsed)
        velocity = hasVelocity
            ? CellVector(dx: (velocity.dx + instant.dx) / 2, dy: (velocity.dy + instant.dy) / 2)
            : instant
        hasVelocity = true
        last = location
        lastTime = time
    }

    private func currentValue(at location: CellPoint) -> DragGesture.Value {
        DragGesture.Value(time: Date(), location: location, startLocation: start, velocity: velocity)
    }
}
