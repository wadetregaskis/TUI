//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipCues.swift
//
//  The app's end of the cue pipe: the player writes a cue a line at a time,
//  and the app reads them here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The cues the player sends a clip's app, as they arrive.
///
/// The pipe's read end is inherited across the player's `forkpty` and `exec`,
/// and its number handed over in ``environmentKey``. Outside the player (the
/// app run on its own, for a look at it) there is no pipe and no cue ever
/// arrives.
enum ClipCues {
    static let environmentKey = "SCREENCLIPS_CUE_FD"

    /// The cues, one per line the player writes, ending when the player closes
    /// the pipe. Read with a view's `.task`, which is on the main actor, so a
    /// cue's change to the app's state is made where the app's state lives.
    static func stream() -> AsyncStream<String> {
        guard let text = ProcessInfo.processInfo.environment[environmentKey], let descriptor = Int32(text) else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            // A thread of its own, blocked in read(2): the pipe is quiet for
            // seconds at a time, and nothing else waits on it.
            let thread = Thread {
                var pending = Data()
                var buffer = [UInt8](repeating: 0, count: 256)
                while true {
                    let count = read(descriptor, &buffer, buffer.count)
                    if count <= 0 { break }
                    pending.append(contentsOf: buffer[0..<count])
                    while let newline = pending.firstIndex(of: 0x0A) {
                        continuation.yield(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    }
                }
                continuation.finish()
            }
            thread.start()
        }
    }
}
