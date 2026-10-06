//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureNode.swift
//
//  The recognizers a gesture is built into. A `Gesture` is a value rebuilt
//  with its view every frame; its recognizer is the object that remembers
//  where the pointer went between them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Phase

/// Where a recognizer is in one gesture.
enum GesturePhase: Equatable {
    /// Not engaged: no press has started it, or it finished and nothing new
    /// has begun.
    case idle

    /// Engaged and undecided. It may already have a value to report —
    /// a long press is `true` from the moment the button goes down — but it
    /// has not recognized, so it does not yet keep another gesture from
    /// recognizing.
    case possible

    /// Recognized and still going: a drag past its minimum distance. It
    /// claims the pointer from the gestures it takes precedence over.
    case active

    /// Succeeded. Terminal until the next press starts it again.
    case ended

    /// Failed or was cancelled. Terminal until the next press.
    case failed

    /// Whether the gesture is over, one way or the other.
    var isTerminal: Bool { self == .ended || self == .failed }

    /// Whether the gesture has recognized, which is what takes the pointer
    /// away from every gesture it takes precedence over.
    var hasRecognized: Bool { self == .active || self == .ended }
}

// MARK: - Input

/// One pointer report, in the cells of the view the gesture is attached to.
struct GesturePointer {
    enum Kind: Equatable {
        case down
        case moved
        case up
    }

    var kind: Kind

    /// Where the pointer is, measured from the view's own top-left cell.
    var location: CellPoint

    /// Where the pointer is, measured from the terminal's top-left cell.
    var globalLocation: CellPoint

    /// The modifier keys the terminal reported with the event.
    var modifiers: EventModifiers

    /// When the report arrived, on the run loop's monotonic clock.
    var timeNanos: Int64

    /// Whether the pointer is over the view.
    var isInside: Bool

    /// Whether this press is already over: the press ``asDown`` makes of a
    /// release. A long press reads it as not pressing.
    var isOver = false

    /// This report, standing in for a press: how the second gesture of a
    /// sequence takes the event that ended the first, or the first event
    /// after a first that ended on its clock. A release makes a press that
    /// is already over (``isOver``), and so does a press that already was:
    /// a sequence that is itself a second part hands its own second part the
    /// over press it was handed. Measured on macOS 15.8, a tap before a
    /// sequence of two zero-duration long presses ends both `false`; a press
    /// made live again ended the second `true`.
    var asDown: Self {
        var down = self
        down.kind = .down
        down.isOver = isOver || kind == .up
        return down
    }

    /// The location in the requested coordinate space.
    func location(in space: CoordinateSpace) -> CellPoint {
        space == .global ? globalLocation : location
    }
}

/// What a recognizer is fed: a pointer report, or the passing of time.
enum GestureInput {
    case pointer(GesturePointer)

    /// The frame clock has reached this instant — what ends a long press, and
    /// what fails a tap waiting for a second click that never came.
    case tick(Int64)
}

// MARK: - Recognizers

/// The type-erased half of a recognizer: everything the arbitration between
/// gestures needs, none of which depends on the value type.
@MainActor
class GestureNodeBase {
    /// Where the gesture is.
    var phase = GesturePhase.idle

    /// Bumped each time the recognizer computes its value afresh, so a wrapper
    /// can tell a new report from the one it already acted on — including a
    /// value equal to the last one, which `updating(_:body:)` still hears.
    var version = 0

    /// Feeds one input to the recognizer.
    ///
    /// - Parameters:
    ///   - input: The pointer report or clock tick.
    ///   - deliver: Whether the gesture's callbacks may run. `false` while a
    ///     gesture that takes precedence over this one is still undecided:
    ///     the recognizer keeps up, and holds what it would have reported
    ///     until ``flush()``.
    func receive(_ input: GestureInput, deliver: Bool) {}

    /// Runs what was held back while delivery was off, as of the current
    /// state: the value it has now, or its end.
    func flush() {}

    /// Ends the gesture without success: another gesture recognized ahead of
    /// it, its view went away, or its press was given to something else. A
    /// `@GestureState` it updated resets.
    func cancel() {
        phase = .failed
    }

    /// The next instant the recognizer has to be told about, if any — a long
    /// press's minimum duration, a tap's wait for its next click.
    var deadline: Int64? { nil }

    /// Starts a fresh gesture if the last one is over, as the press that
    /// begins a new one does.
    func beginIfFinished() {
        if phase == .idle || phase.isTerminal { phase = .possible }
    }
}

/// A recognizer that reports values of type `Value`.
@MainActor
class GestureNode<Value>: GestureNodeBase {
    /// The value the gesture currently reports: provisional while it is
    /// possible, its last while active, its final once ended. `nil` when it
    /// has nothing to report.
    var value: Value?

    /// Records a newly computed value.
    func report(_ newValue: Value?) {
        value = newValue
        version &+= 1
    }
}

// MARK: - Cache

/// The recognizers of one attached gesture, kept between frames by their place
/// in the gesture tree.
///
/// Each build of the gesture value — the latest frame's, when the arena next
/// looks (``GestureParticipant``) — is handed the recognizers the last build
/// left; a place whose gesture changed type gets a new one, and a place no
/// longer visited drops its recognizer at the end of the build.
@MainActor
final class GestureNodeCache {
    private struct Key: Hashable {
        let path: Int
        let type: ObjectIdentifier
    }

    private var nodes: [Key: GestureNodeBase] = [:]
    private var visited: [Key: GestureNodeBase] = [:]

    func node<Node: GestureNodeBase>(at path: Int, _ make: () -> Node) -> Node {
        let key = Key(path: path, type: ObjectIdentifier(Node.self))
        let node = (nodes[key] as? Node) ?? make()
        visited[key] = node
        return node
    }

    /// Ends a build: what this build's gesture visited is what the next build
    /// will find.
    func commit() {
        swap(&nodes, &visited)
        visited.removeAll(keepingCapacity: true)
    }
}
