//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyframeCurve.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

/// One track's keyframes, resolved into segments with every start, value and
/// velocity known, so a value at any time is one segment's arithmetic.
///
/// The rules are SwiftUI's, measured on its own timelines
/// (`w12/probe/p6.swift`, `p7.swift`):
///
/// - A **cubic** keyframe is a Hermite segment. Its start velocity is the one
///   it names, else — after another cubic — the Catmull–Rom tangent through
///   the points either side, else the velocity the segment before ended at
///   (zero at the very start and after a move). Its end velocity is the one it
///   names, else the next keyframe's: a cubic's named start velocity or the
///   Catmull–Rom tangent, a linear one's starting slope, a spring's named start
///   velocity, or zero.
/// - A **linear** keyframe follows its unit curve.
/// - A **spring** keyframe starts at the velocity it names or the one the
///   segment before ended at, runs for its duration — or until it is within
///   0.0001 of its target — and hands on the value and velocity it reached,
///   which need not be the target.
/// - A **move** keyframe jumps, and leaves the value at rest.
@MainActor
struct KeyframeCurve<Value: Animatable> {
    typealias Data = Value.AnimatableData

    private enum Shape {
        case linear(UnitCurve)
        case cubic(start: Data, end: Data)
        case spring(Spring, startVelocity: Data)
        case move
    }

    private struct Segment {
        let start: TimeInterval
        let duration: TimeInterval
        let from: Data
        let to: Data
        /// What the segment's values are written into: its keyframe's value.
        let template: Value
        let shape: Shape

        var end: TimeInterval { start + duration }
    }

    private let initial: Value
    private let segments: [Segment]

    /// How long the track runs.
    let duration: TimeInterval

    init(from initial: Value, keyframes: [Keyframe<Value>]) {
        self.initial = initial
        var segments: [Segment] = []
        var time: TimeInterval = 0
        var from = initial.animatableData
        // The velocity the last segment ended at, and whether it was a cubic
        // (whose successor then takes a Catmull–Rom tangent instead).
        var incoming = Data.zero
        var previousCubic: Segment?

        for (index, keyframe) in keyframes.enumerated() {
            let target = keyframe.target.animatableData
            let next = keyframes.indices.contains(index + 1) ? keyframes[index + 1] : nil
            switch keyframe.kind {
            case .move:
                segments.append(
                    Segment(start: time, duration: 0, from: from, to: target, template: keyframe.target, shape: .move))
                from = target
                incoming = .zero
                previousCubic = nil

            case .linear(let curve):
                let length = max(0, keyframe.duration ?? 0)
                segments.append(
                    Segment(
                        start: time, duration: length, from: from, to: target, template: keyframe.target,
                        shape: .linear(curve)))
                incoming = Self.slope(from: from, to: target, over: length, scaledBy: curve.velocity(at: 1))
                from = target
                time += length
                previousCubic = nil

            case .cubic(let named, let namedEnd):
                let length = max(0, keyframe.duration ?? 0)
                let startVelocity: Data =
                    named?.animatableData
                    ?? previousCubic.map {
                        Self.slope(from: $0.from, to: target, over: time + length - $0.start, scaledBy: 1)
                    } ?? incoming
                let endVelocity: Data =
                    namedEnd?.animatableData
                    ?? Self.velocity(
                        enteringAfter: target, at: time + length, next: next, segmentStart: time, segmentFrom: from)
                let segment = Segment(
                    start: time, duration: length, from: from, to: target, template: keyframe.target,
                    shape: .cubic(start: startVelocity, end: endVelocity))
                segments.append(segment)
                incoming = endVelocity
                from = target
                time += length
                previousCubic = segment

            case .spring(let spring, let named):
                let startVelocity = named?.animatableData ?? incoming
                let change = target - from
                let length = max(
                    0,
                    keyframe.duration
                        ?? spring.settlingDuration(target: change, initialVelocity: startVelocity, epsilon: 1e-4))
                let reached = from + spring.value(target: change, initialVelocity: startVelocity, time: length)
                segments.append(
                    Segment(
                        start: time, duration: length, from: from, to: target, template: keyframe.target,
                        shape: .spring(spring, startVelocity: startVelocity)))
                incoming = spring.velocity(target: change, initialVelocity: startVelocity, time: length)
                from = reached
                time += length
                previousCubic = nil
            }
        }
        self.segments = segments
        duration = time
    }

    /// The value at `time`: the start before it, the end after it.
    func value(at time: TimeInterval) -> Value {
        // The segment in force is the last to have started before `time`, so a
        // keyframe's end is shown at exactly its end time and a move takes
        // effect only after it.
        guard let segment = segments.last(where: { $0.start < time }) else { return initial }
        let progress = segment.duration > 0 ? min(1, (time - segment.start) / segment.duration) : 1
        var value = segment.template
        value.animatableData = Self.data(segment, at: progress)
        return value
    }

    private static func data(_ segment: Segment, at progress: Double) -> Data {
        let (from, to) = (segment.from, segment.to)
        switch segment.shape {
        case .move:
            return to
        case .linear(let curve):
            return from + (to - from).scaled(by: curve.value(at: progress))
        case .cubic(let start, let end):
            // Hermite basis, with the velocities in units per second scaled to
            // the segment's length.
            let (t, t2, t3) = (progress, progress * progress, progress * progress * progress)
            let length = segment.duration
            return from.scaled(by: 2 * t3 - 3 * t2 + 1)
                + start.scaled(by: (t3 - 2 * t2 + t) * length)
                + to.scaled(by: -2 * t3 + 3 * t2)
                + end.scaled(by: (t3 - t2) * length)
        case .spring(let spring, let startVelocity):
            return from
                + spring.value(
                    target: to - from, initialVelocity: startVelocity, time: progress * segment.duration)
        }
    }

    /// `(to − from) / length`, times `scale` — a straight segment's velocity.
    private static func slope(from: Data, to: Data, over length: TimeInterval, scaledBy scale: Double) -> Data {
        guard length > 0 else { return .zero }
        return (to - from).scaled(by: scale / length)
    }

    /// The velocity a cubic keyframe ending at `point` at `time` ends with,
    /// from the keyframe after it.
    private static func velocity(
        enteringAfter point: Data, at time: TimeInterval, next: Keyframe<Value>?,
        segmentStart: TimeInterval, segmentFrom: Data
    ) -> Data {
        guard let next else { return .zero }
        let nextTarget = next.target.animatableData
        switch next.kind {
        case .cubic(let named, _):
            // Catmull–Rom: from the point before to the point after.
            return named?.animatableData
                ?? slope(
                    from: segmentFrom, to: nextTarget,
                    over: time + max(0, next.duration ?? 0) - segmentStart, scaledBy: 1)
        case .linear(let curve):
            return slope(
                from: point, to: nextTarget, over: max(0, next.duration ?? 0),
                scaledBy: curve.velocity(at: 0))
        case .spring(_, let named):
            return named?.animatableData ?? .zero
        case .move:
            return .zero
        }
    }
}
