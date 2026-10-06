//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TapGesture.swift
//
//  SwiftUI's `TapGesture` and `SpatialTapGesture`, with the thresholds macOS
//  15.8's SwiftUI was measured to use.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A gesture that recognizes one or more taps.
///
/// To recognize a tap gesture on a view, create and configure the gesture, and
/// then add it to the view using the ``View/gesture(_:including:)`` modifier:
///
/// ```swift
/// struct TapGestureView: View {
///     @State private var tapped = false
///
///     var tap: some Gesture {
///         TapGesture(count: 1)
///             .onEnded { _ in self.tapped = !self.tapped }
///     }
///
///     var body: some View {
///         Text(tapped ? "On" : "Off")
///             .gesture(tap)
///     }
/// }
/// ```
///
/// A tap is a click of the left mouse button, recognized on its release, with
/// the rules SwiftUI's measured on macOS 15.8 (`Documentation/SwiftUI-compatibility.md`):
///
/// - the release has to land on the view, and the pointer may not stray
///   more than five columns or two rows from the press — about the 40 points
///   macOS allows;
/// - the button may be held for at most 0.75 seconds;
/// - for a `count` above one, each next click has to be released within 0.35
///   seconds of the release before it — a press that comes in time but is
///   held past that gives the tap up then, with the button still down.
///
/// A tap that waits for a second click holds up whatever gesture it takes
/// precedence over until it fails: `.onTapGesture(count: 2)` inside
/// `.onTapGesture` delays the single tap by the double-tap interval, so that a
/// double-click runs only the double tap — as on macOS. When it is the second
/// click that gives the double tap up, held too long or strayed, the single
/// tap runs once, for the first click, and not again for the second — as on
/// macOS too. A click on another view meanwhile does not give the double tap
/// up: it waits out its interval, and the single tap runs for the first click
/// then.
public struct TapGesture: Gesture {
    /// The required number of tap events.
    public var count: Int

    /// Creates a tap gesture with the number of required taps.
    ///
    /// - Parameter count: The required number of taps to complete the tap
    ///   gesture.
    public init(count: Int = 1) {
        self.count = count
    }

    /// The type representing the gesture's value.
    public typealias Value = Void

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Void> {
        let node = inputs.node { TapGestureNode<Void>() }
        node.count = max(1, gesture.count)
        node.makeValue = { _ in () }
        return _GestureOutputs(node)
    }

    // MARK: Thresholds

    /// How far, in columns, the pointer may move from the press before a tap
    /// fails. macOS's SwiftUI keeps a tap through 40 points of travel and
    /// fails it at 45 (measured on macOS 15.8), which is five columns of a
    /// typical eight-point-wide cell.
    static let slopColumns = 5

    /// How far, in rows, the pointer may move from the press before a tap
    /// fails: the same 40 points over a typical seventeen-point-tall row.
    static let slopRows = 2

    /// The longest the button may be held for a press to count as a tap:
    /// 0.75 s, measured on macOS 15.8 (a 0.753 s press tapped, a 0.78 s one
    /// did not).
    static let maximumHold: Double = 0.75

    /// How soon after a release the next click must be released to continue
    /// a multi-tap: 0.35 s, measured on macOS 15.8 — shorter than the system's
    /// 0.5 s double-click interval, which SwiftUI's taps do not use. Release to
    /// release: a second press 0.12 s after the first release and held 0.15 s
    /// double-taps, held 0.25 s does not, and the tap gives up 0.35 s after the
    /// first release while that press is still down (also measured there).
    static let multiTapInterval: Double = 0.35
}

/// A gesture that recognizes one or more taps and reports their location.
///
/// ```swift
/// struct TapGestureView: View {
///     @State private var location: CellPoint = .zero
///
///     var tap: some Gesture {
///         SpatialTapGesture()
///             .onEnded { event in
///                 self.location = event.location
///             }
///     }
///
///     var body: some View {
///         Text("Tapped at \(location.x), \(location.y)")
///             .gesture(tap)
///     }
/// }
/// ```
///
/// The location is the release's cell, a ``CellPoint`` where SwiftUI's is a
/// `CGPoint` (§2.2 of `Documentation/SwiftUI-compatibility.md`). It is
/// recognized as ``TapGesture`` is, and like it reports nothing until it ends —
/// SwiftUI's `onChanged` on a spatial tap never runs either (measured on
/// macOS 15.8).
public struct SpatialTapGesture: Gesture {
    /// The attributes of a tap gesture.
    public struct Value: Equatable, Sendable {
        /// The location of the tap gesture's current event.
        public var location: CellPoint
    }

    /// The required number of tap events.
    public var count: Int

    /// The coordinate space in which to receive location values.
    public var coordinateSpace: CoordinateSpace

    /// Creates a tap gesture with the number of required taps and the
    /// coordinate space of the gesture's location.
    ///
    /// - Parameters:
    ///   - count: The required number of taps to complete the tap gesture.
    ///   - coordinateSpace: The coordinate space of the tap gesture's
    ///     location: `.local`, the view's own top-left cell, or `.global`.
    public init(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.init(count: count, coordinateSpace: coordinateSpace.coordinateSpace)
    }

    /// Creates a tap gesture with the number of required taps and the
    /// coordinate space of the gesture's location, given as a
    /// ``CoordinateSpace`` value — the form SwiftUI deprecated for the
    /// protocol one, kept as `onTapGesture(count:coordinateSpace:perform:)`
    /// keeps it.
    ///
    /// - Parameters:
    ///   - count: The required number of taps to complete the tap gesture.
    ///   - coordinateSpace: `.local` or `.global`.
    @_disfavoredOverload
    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) {
        self.count = count
        self.coordinateSpace = coordinateSpace
    }

    /// The type of gesture representing the body of `Self`.
    public typealias Body = Never

    public static func _makeGesture(gesture: Self, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        let node = inputs.node { TapGestureNode<Value>() }
        node.count = max(1, gesture.count)
        let space = gesture.coordinateSpace
        node.makeValue = { Value(location: $0.location(in: space)) }
        return _GestureOutputs(node)
    }
}

// MARK: - Recognizer

/// Recognizes `count` clicks, each short and close to its press, released on
/// the view — the recognizer behind ``TapGesture`` and ``SpatialTapGesture``.
final class TapGestureNode<Value>: GestureNode<Value> {
    var count = 1
    var makeValue: (GesturePointer) -> Value = { _ in fatalError("unconfigured tap") }

    /// Clicks completed in the sequence under way.
    private var clicks = 0

    /// Whether the button is down for a click of this sequence.
    private var pressing = false

    /// Where and when the current click's press landed.
    private var pressLocation = CellPoint.zero
    private var pressTime: Int64 = 0

    /// When the last click of the sequence was released, on the event clock.
    private var releaseTime: Int64 = 0

    /// The running timer, on the frame clock: a first press that may not be
    /// held past it, or a release whose next click may not end after it.
    /// Armed by the event, set by the first tick after it — so the event clock
    /// and the frame clock are never compared.
    private var timer = GestureTimer()

    override func receive(_ input: GestureInput, deliver: Bool) {
        switch input {
        case .pointer(let pointer):
            receive(pointer)
        case .tick(let now):
            if phase == .possible, timer.hasExpired(at: now) { fail() }
        }
    }

    private func receive(_ pointer: GesturePointer) {
        switch pointer.kind {
        case .down:
            let continues = phase == .possible && clicks > 0 && !pressing
                && pointer.timeNanos - releaseTime <= GestureTimer.nanos(TapGesture.multiTapInterval)
            if !continues {
                clicks = 0
                phase = .possible
                report(nil)
                // A sequence's first press may be held for the hold limit. A
                // later one runs on the wait its release started, which the
                // press does not stop: macOS gives a double tap up 0.35 s
                // after the first release with the second press still down.
                timer.arm(seconds: TapGesture.maximumHold)
            }
            pressing = true
            pressLocation = pointer.globalLocation
            pressTime = pointer.timeNanos
        case .moved:
            guard phase == .possible, pressing else { return }
            if strayed(to: pointer.globalLocation) { fail() }
        case .up:
            guard phase == .possible, pressing else {
                pressing = false
                return
            }
            pressing = false
            // The event-clock half of the timer: a release that arrives after
            // its deadline, before the frame that would have failed it.
            guard pointer.isInside, !strayed(to: pointer.globalLocation),
                pointer.timeNanos - pressTime <= GestureTimer.nanos(TapGesture.maximumHold),
                clicks == 0
                    || pointer.timeNanos - releaseTime <= GestureTimer.nanos(TapGesture.multiTapInterval)
            else {
                fail()
                return
            }
            clicks += 1
            if clicks >= count {
                clicks = 0
                timer.disarm()
                phase = .ended
                report(makeValue(pointer))
            } else {
                releaseTime = pointer.timeNanos
                timer.arm(seconds: TapGesture.multiTapInterval)
            }
        }
    }

    override func cancel() {
        fail()
    }

    override var deadline: Int64? { phase == .possible ? timer.deadline : nil }

    private func fail() {
        clicks = 0
        timer.disarm()
        phase = .failed
        report(nil)
    }

    /// Whether `location` is further from the press than a tap allows.
    private func strayed(to location: CellPoint) -> Bool {
        abs(location.x - pressLocation.x) > TapGesture.slopColumns
            || abs(location.y - pressLocation.y) > TapGesture.slopRows
    }
}

// MARK: - Timer

/// A recognizer's timer: armed by an event with a duration, and given its
/// deadline by the first frame-clock tick after — the event clock (when a
/// report arrived) and the frame clock (what a frame reads as now) are the
/// same clock in an app but not in a test harness, so a deadline is never
/// computed from one and compared with the other.
struct GestureTimer {
    private var duration: Int64?
    private var expiry: Int64?

    /// Starts the timer: it expires `seconds` after the next tick.
    mutating func arm(seconds: Double) {
        duration = Self.nanos(seconds)
        expiry = nil
    }

    mutating func disarm() {
        duration = nil
        expiry = nil
    }

    /// Whether the timer has run out at `now` — setting its deadline from
    /// `now` if this is the first tick since it was armed.
    mutating func hasExpired(at now: Int64) -> Bool {
        guard let duration else { return false }
        guard let expiry else {
            expiry = now &+ duration
            return duration <= 0
        }
        return now >= expiry
    }

    /// When the timer runs out: its deadline once a tick has set one, or `0`
    /// — "as soon as possible" — while it waits for that tick.
    var deadline: Int64? {
        guard duration != nil else { return nil }
        return expiry ?? 0
    }

    /// `seconds` in nanoseconds, never negative.
    static func nanos(_ seconds: Double) -> Int64 {
        Int64((max(0, seconds) * 1_000_000_000).rounded())
    }
}
