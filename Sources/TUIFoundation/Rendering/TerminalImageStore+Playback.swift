//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalImageStore+Playback.swift
//
//  A picture whose frames the terminal holds and plays by itself. Its cells never
//  change, so a tick costs nothing: no bytes and no wake. What the frame clock used
//  to do by simply not being asked, the frame on screen now does here.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// What the store knows of an image the terminal holds several frames of.
///
/// **The first pass** goes as it does on any terminal: a frame is sent when the
/// frame clock reaches it (a large file is not a stall on its first frame), and
/// here selected by number rather than by rewriting the cells. **After the last
/// frame** the terminal is told to run, and the view asks for no more wakes.
///
/// **Stopping.** While the terminal runs it, no render says the picture is wanted,
/// and a view not drawn asks for nothing: which is how every other picture stops,
/// and here would stop nothing. So each frame written looks for the picture's cells
/// (``TerminalImageStore/updatePlayedPictures(onScreen:nowNanos:)``). No cell on
/// screen, for whatever reason (scrolled off, `.hidden()`, Reduce Motion drawing the
/// still, covered), and it is stopped; back, and it runs on from the frame the
/// terminal stopped on. Nothing changes on screen without a frame being written, so
/// there is nothing to poll. A view that has gone deletes the image, and starts
/// again from its first frame if it returns, as on any terminal.
///
/// Kept per image rather than per view: a picture sent again (a theme change, a new
/// size) is under a new id, and starts by sending frames again.
struct PlayedPicture {
    var framesSent = 1
    var shownFrame = 0
    /// Whether the terminal has every frame and was told to run.
    var isHandedOver = false
    var isRunning = false
    let durationNanos: Int64
    let plays: Int?
    /// How long it had run when it last stopped, for how many plays are left.
    var ranNanos: Int64 = 0
    /// When it last started running.
    var runningSince: Int64 = 0
    /// Whether anything has read this image's pixels, which are its first frame's.
    var wasCopied = false
    var whenCopied: (() -> Void)?

    /// The `v` to run with, or `nil` if its plays are over. A terminal plays `v - 1`
    /// passes counting the one it is in, `v = 1` being for ever, and stopping it
    /// resets that count.
    var loopKey: Int? {
        guard let plays else { return 1 }
        let done = durationNanos > 0 ? Int(ranNanos / durationNanos) : 0
        let left = plays - done
        return left > 0 ? left + 1 : nil
    }
}

/// How an animation stands against its clock, for ``TerminalImageStore/advancePlayedPicture(token:to:timing:delayNanos:size:pixels:whenCopied:)``.
package struct PlayedPictureTiming {
    let frameCount: Int
    let durationNanos: Int64
    let plays: Int?
    let elapsedNanos: Int64
    let nowNanos: Int64

    package init(frameCount: Int, durationNanos: Int64, plays: Int?, elapsedNanos: Int64, nowNanos: Int64) {
        self.frameCount = frameCount
        self.durationNanos = durationNanos
        self.plays = plays
        self.elapsedNanos = elapsedNanos
        self.nowNanos = nowNanos
    }
}

extension TerminalImageStore {
    /// Whether the terminal has been told to run the picture `token` draws.
    package func hasHandedOverPlayedPicture(token: String) -> Bool {
        guard let id = entries[token] else { return false }
        return played[id]?.isHandedOver == true
    }

    /// Brings the picture `token` draws up to frame `index`: the frames it does not
    /// have yet, one at a clock tick and several only after the picture was sent
    /// again part way through; that frame selected; and, once it has them all, the
    /// terminal told to run.
    package func advancePlayedPicture(
        token: String, to index: Int, timing: PlayedPictureTiming, delayNanos: (Int) -> Int64,
        size: (width: Int, height: Int), pixels: (Int) -> (bytes: [UInt8], format: KittyGraphics.PixelFormat),
        whenCopied: @escaping () -> Void
    ) {
        guard let id = entries[token] else { return }
        var picture =
            played[id] ?? {
                pending += KittyGraphics.frameGap(id: id, frame: 1, milliseconds: Self.milliseconds(delayNanos(0)))
                return PlayedPicture(durationNanos: timing.durationNanos, plays: timing.plays)
            }()
        picture.whenCopied = whenCopied
        guard !picture.isHandedOver else {
            played[id] = picture
            return
        }
        while picture.framesSent <= index {
            let payload = pixels(picture.framesSent)
            pending += KittyGraphics.frame(
                pixels: payload.bytes, format: payload.format, width: size.width, height: size.height, id: id,
                gapMilliseconds: Self.milliseconds(delayNanos(picture.framesSent)),
                compressed: KittyGraphics.isCompressionSupported)
            picture.framesSent += 1
        }
        if picture.shownFrame != index {
            pending += KittyGraphics.selectFrame(id: id, frame: index + 1)
            picture.shownFrame = index
        }
        if picture.framesSent == timing.frameCount {
            picture.isHandedOver = true
            picture.ranNanos = timing.elapsedNanos
            picture.runningSince = timing.nowNanos
            if let loops = picture.loopKey {
                pending += KittyGraphics.runFrames(id: id, loops: loops)
                picture.isRunning = true
            }
        }
        played[id] = picture
    }

    /// Stops what the terminal is playing that `lines`, the frame about to be
    /// written, does not show, and runs what it now shows again. Hands back a
    /// picture something made a copy of, which would otherwise be of its first frame.
    ///
    /// Nothing at all with nothing played, and the rows searched only where the
    /// terminal is playing something.
    package func updatePlayedPictures(onScreen lines: [String], nowNanos: Int64) {
        guard !played.isEmpty else { return }
        for (id, picture) in played where picture.wasCopied {
            picture.whenCopied?()
            played[id]?.wasCopied = false
            played[id]?.whenCopied = nil
        }
        guard played.values.contains(where: \.isHandedOver) else { return }
        var shown = Set<KittyGraphics.ImageID>()
        forEachPictureCell(in: lines) { shown.insert($0.id) }
        for (id, picture) in played.sorted(by: { $0.key < $1.key }) where picture.isHandedOver {
            let isShown = shown.contains(id)
            if picture.isRunning, !isShown {
                pending += KittyGraphics.stopFrames(id: id)
                played[id]?.isRunning = false
                played[id]?.ranNanos = picture.ranNanos &+ (nowNanos &- picture.runningSince)
            } else if !picture.isRunning, isShown, let loops = picture.loopKey {
                pending += KittyGraphics.runFrames(id: id, loops: loops)
                played[id]?.isRunning = true
                played[id]?.runningSince = nowNanos
            }
        }
    }

    /// A delay as the protocol's gap: whole milliseconds, and at least one, as `0`
    /// means "unchanged" there and a negative is a frame never shown.
    private static func milliseconds(_ nanos: Int64) -> Int {
        max(1, Int((nanos + 500_000) / 1_000_000))
    }
}
