//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameTrace.swift
//
//  `TUI_FRAME_TRACE`: one line per frame to a file, saying what caused it, how long it
//  took and how many bytes it wrote. For an app's author asking why a screen is busy.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIView

/// Writes the trace. The run loop holds one of these only if the variable is set, so
/// a run without it pays for one stored optional's check at each place a cause is
/// noted and once a frame, as `ScrollCensus` does.
@MainActor
final class FrameTrace {
    /// What asked for a frame. A set, because the loop folds everything that happened
    /// since the last frame into one frame.
    struct Causes: OptionSet {
        let rawValue: UInt8

        /// The first frame of the run.
        static let launch = Self(rawValue: 1 << 0)
        /// Input was read: a key, the mouse, a report from the terminal.
        static let input = Self(rawValue: 1 << 1)
        /// State changed. With `input`, most likely because of it. Without it, from
        /// a timer or a task of the app's.
        static let state = Self(rawValue: 1 << 2)
        /// The terminal changed size.
        static let resize = Self(rawValue: 1 << 3)
        /// An animation clock ticked, and only a render could show it.
        static let tick = Self(rawValue: 1 << 4)
        /// An animation or a timeline asked for a frame at this instant.
        static let wake = Self(rawValue: 1 << 5)
        /// The process was stopped, and is running again.
        static let resume = Self(rawValue: 1 << 6)
        /// An animation clock ticked, and the frames a render left were written over
        /// the screen with no render.
        static let replay = Self(rawValue: 1 << 7)

        /// Every cause, in the order a line names them.
        private static let named: [(Self, String)] = [
            (.launch, "launch"), (.input, "input"), (.state, "state"), (.resize, "resize"),
            (.tick, "tick"), (.wake, "wake"), (.resume, "resume"), (.replay, "replay"),
        ]

        /// The names, in the order declared. `other` for a frame nothing above asked
        /// for, such as one a report of the window's size asks for.
        var names: String {
            let present = Self.named.filter { contains($0.0) }.map(\.1)
            return present.isEmpty ? "other" : present.joined(separator: "+")
        }
    }

    private let handle: FileHandle
    private let startedAtNanos: UInt64
    private var frame = 0
    private var pending: Causes = .launch
    private var statsAtLastFrame = RenderCache.Stats()
    private var bytesAtLastFrame = 0

    /// `nil` when `destination` is unset or empty, or names a file that can't be made,
    /// in which case the app runs as if it were unset.
    init?(destination: String?) {
        guard let destination, !destination.isEmpty else { return nil }
        _ = FileManager.default.createFile(atPath: destination, contents: nil)
        guard let opened = FileHandle(forWritingAtPath: destination) else { return nil }
        handle = opened
        startedAtNanos = MonotonicClock.nowNanoseconds
        handle.write(Data("#frame\tat_ms\tms\tbytes\thits\tmisses\tcause\n".utf8))
    }

    static func fromEnvironment() -> FrameTrace? {
        FrameTrace(destination: ProcessInfo.processInfo.environment["TUI_FRAME_TRACE"])
    }

    /// Notes a cause of the next frame.
    func note(_ causes: Causes) {
        pending.formUnion(causes)
    }

    /// Writes the line for a frame that began at `startNanos` and has just finished.
    ///
    /// - Parameters:
    ///   - totalBytes: What the terminal has been sent in frames so far, this one's
    ///     included.
    ///   - cache: The render cache, for what this frame found in it. A replay draws no
    ///     view, so its hits and misses are zero.
    func record(startNanos: UInt64, totalBytes: Int, cache: RenderCache) {
        let now = MonotonicClock.nowNanoseconds
        let bytes = totalBytes &- bytesAtLastFrame
        bytesAtLastFrame = totalBytes
        let stats = cache.stats.delta(since: statsAtLastFrame)
        statsAtLastFrame = cache.stats
        frame += 1
        let at = (startNanos &- startedAtNanos) / 1_000_000
        let tenths = (now &- startNanos) / 100_000
        let line =
            "\(frame)\t\(at)\t\(tenths / 10).\(tenths % 10)\t\(bytes)\t\(stats.hits)\t\(stats.misses)\t\(pending.names)\n"
        handle.write(Data(line.utf8))
        pending = []
    }

    /// Writes the line for a replay, which has a cause of its own, and leaves what is
    /// waiting for the next frame waiting. A tick that changed no cell wrote nothing,
    /// and is no frame.
    func recordReplay(startNanos: UInt64, totalBytes: Int, cache: RenderCache) {
        guard totalBytes != bytesAtLastFrame else { return }
        let waiting = pending
        pending = .replay
        record(startNanos: startNanos, totalBytes: totalBytes, cache: cache)
        pending = waiting
    }
}
