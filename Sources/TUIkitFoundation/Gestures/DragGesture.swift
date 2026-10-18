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
        /// Mac mouse's is from its events' timestamps: a least-squares fit of
        /// the moves of the last 100 ms, as UIKit's pan recognizer fits them.
        /// A pointer held still sends no reports, so the velocity is the last
        /// motion's — as macOS 15.8's is, measured.
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
    /// protocol one, internal here: what the public form builds by (owner's
    /// ruling of 2026-10-12, no deprecated SwiftUI API).
    ///
    /// - Parameters:
    ///   - minimumDistance: The minimum dragging distance for the gesture to
    ///     succeed, in cells along either axis.
    ///   - coordinateSpace: `.local` or `.global`.
    @_disfavoredOverload
    init(minimumDistance: Int = 1, coordinateSpace: CoordinateSpace = .local) {
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
    private var velocity = CellVector(dx: 0, dy: 0)

    /// The press and the moves since, as far back as a fit reaches
    /// (``track(_:at:)``).
    private var samples: [DragSample] = []

    override func receive(_ input: GestureInput, deliver: Bool) {
        guard case .pointer(let pointer) = input else { return }
        let location = pointer.location(in: coordinateSpace)
        switch pointer.kind {
        case .down:
            start = location
            velocity = CellVector(dx: 0, dy: 0)
            samples.removeAll(keepingCapacity: true)
            samples.append(DragSample(time: pointer.timeNanos, location: location))
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

    /// Folds one report into the velocity. A report that did not move — a
    /// release where the last drag left the pointer — leaves it as it was.
    ///
    /// Otherwise the velocity is the least-squares slope of the press and
    /// the moves since, over the last ``DragSample/window`` up to this report
    /// (decisions B91). Anchored at the last report rather than at the
    /// clock, so a pointer held still keeps its velocity, which macOS 15.8
    /// was measured to do. A fit reads past several reports, so one pair of
    /// them close together cannot spike it: TUIkit stamps a report when it
    /// dispatches it, and reports the terminal sent over a frame and read at
    /// once arrive microseconds apart. When the window holds too little to
    /// fit — one report, after a pause; or a burst read at once and nothing
    /// before it — it reaches back to the report before it.
    private func track(_ location: CellPoint, at time: Int64) {
        guard let previous = samples.last, location != previous.location else { return }
        samples.append(DragSample(time: time, location: location))
        // What no later fit reaches: everything before the last report
        // older than the window, which a short window reaches back to.
        let horizon = time &- DragSample.window
        if let inside = samples.firstIndex(where: { $0.time >= horizon }), inside > 1 {
            samples.removeFirst(inside - 1)
        }
        if samples.count > DragSample.capacity { samples.removeFirst(samples.count - DragSample.capacity) }
        if let fitted = DragSample.fit(samples, horizon: horizon) { velocity = fitted }
    }

    private func currentValue(at location: CellPoint) -> DragGesture.Value {
        DragGesture.Value(time: Date(), location: location, startLocation: start, velocity: velocity)
    }
}

/// One report a drag's velocity is fitted to: when it arrived, and where.
struct DragSample {
    var time: Int64
    var location: CellPoint

    /// How far back a fit reads: 100 ms, UIKit's pan recognizer's window.
    static let window: Int64 = 100_000_000

    /// The shortest span of report times a fit is made over: reports closer
    /// together than 1 ms were read at once, not sent apart.
    static let minimumSpan: Int64 = 1_000_000

    /// The most reports kept: a terminal reporting a move per cell, across
    /// a fast drag, sends hundreds a second, and a fit over the last 64 of
    /// them is as good as one over 100 ms.
    static let capacity = 64

    /// The least-squares velocity of `samples`, in cells per second, over
    /// those at or after `horizon` — or, where those span less than
    /// ``minimumSpan``, over them and the one before. `nil` when even that
    /// spans no time at all.
    static func fit(_ samples: [Self], horizon: Int64) -> CellVector? {
        guard let last = samples.last else { return nil }
        var first = samples.firstIndex { $0.time >= horizon } ?? samples.count - 1
        if first > 0, last.time &- samples[first].time < minimumSpan { first -= 1 }
        let fitted = samples[first...]
        guard fitted.count >= 2 else { return nil }
        // Times in nanoseconds before the last report, so the sums stay
        // small whatever the clock reads, and whole numbers: a fit through
        // two reports comes out exact, 40 cells a second and not 39.999….
        let count = Double(fitted.count)
        var meanT = 0.0
        var meanX = 0.0
        var meanY = 0.0
        for sample in fitted {
            meanT += Double(sample.time &- last.time)
            meanX += Double(sample.location.x)
            meanY += Double(sample.location.y)
        }
        meanT /= count
        meanX /= count
        meanY /= count
        var spread = 0.0
        var alongX = 0.0
        var alongY = 0.0
        for sample in fitted {
            let t = Double(sample.time &- last.time) - meanT
            spread += t * t
            alongX += t * (Double(sample.location.x) - meanX)
            alongY += t * (Double(sample.location.y) - meanY)
        }
        guard spread > 0 else { return nil }
        return CellVector(dx: alongX * 1_000_000_000 / spread, dy: alongY * 1_000_000_000 / spread)
    }
}
