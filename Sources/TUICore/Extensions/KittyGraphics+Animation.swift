//  🖥️ TUI — A Terminal UI framework for Swift
//  KittyGraphics+Animation.swift
//
//  The protocol's animation commands: `a=f` adds a frame to a picture, and `a=a`
//  drives it, so that the terminal can play a picture by itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

extension KittyGraphics {
    /// Whether this terminal plays a picture's frames by itself. Asked in the startup
    /// handshake, and only ever where pictures go by placeholders.
    ///
    /// **Defaults to `false`**, so a host nobody asked goes on being sent each frame.
    package static var playsFramesItself: Bool {
        get { taskPlaysFramesItself ?? processPlaysFramesItself.load(ordering: .relaxed) }
        set { processPlaysFramesItself.store(newValue, ordering: .relaxed) }
    }

    /// Atomic for the reason ``isSupported`` gives: written during startup and
    /// read by whoever draws after.
    private static let processPlaysFramesItself = Atomic(false)

    /// A task-scoped pin, bound by ``withPlaysFramesItself(_:operation:)``.
    @TaskLocal private static var taskPlaysFramesItself: Bool?

    /// Runs `operation` with ``playsFramesItself`` pinned on this task only: tests
    /// run in parallel.
    @discardableResult
    package static func withPlaysFramesItself<T>(
        _ plays: Bool, isolation: isolated (any Actor)? = #isolation, operation: () async throws -> T
    ) async rethrows -> T {
        try await $taskPlaysFramesItself.withValue(plays, operation: operation, isolation: isolation)
    }

    /// The escapes adding a frame to picture `id`, after those it has, shown for
    /// `gapMilliseconds`.
    ///
    /// `X=1`, replacing what is under it, over no `c` and so a clear canvas: `pixels`
    /// are the whole picture at this frame, whatever its file's disposal said having
    /// been done by the decoder, and a transparent pixel here has to stay transparent
    /// rather than show the frame before. Every chunk says `a=f`, which a continuation
    /// of any other transmission does not have to.
    package static func frame(
        pixels: [UInt8], format: PixelFormat, width: Int, height: Int, id: ImageID, gapMilliseconds: Int,
        compressed: Bool
    ) -> String {
        transmission(
            action: "a=f,X=1,z=\(gapMilliseconds)", continuation: "a=f,", pixels: pixels, format: format, width: width,
            height: height, id: id, compressed: compressed)
    }

    /// Sets how long frame `frame` (counted from 1) of picture `id` shows: the only
    /// way to say so of the first, which is sent as an ordinary picture.
    package static func frameGap(id: ImageID, frame: Int, milliseconds: Int) -> String {
        "\u{1B}_Ga=a,i=\(id),r=\(frame),z=\(milliseconds),q=2\u{1B}\\"
    }

    /// Makes frame `frame` (counted from 1) of picture `id` the one showing.
    package static func selectFrame(id: ImageID, frame: Int) -> String {
        "\u{1B}_Ga=a,i=\(id),c=\(frame),q=2\u{1B}\\"
    }

    /// Tells the terminal to play picture `id` from the frame showing. `loops` is the
    /// protocol's `v`: `1` for ever, and any other number that number less one passes.
    package static func runFrames(id: ImageID, loops: Int) -> String {
        "\u{1B}_Ga=a,i=\(id),s=3,v=\(loops),q=2\u{1B}\\"
    }

    /// Tells the terminal to hold picture `id` on the frame showing.
    package static func stopFrames(id: ImageID) -> String {
        "\u{1B}_Ga=a,i=\(id),s=1,q=2\u{1B}\\"
    }
}
