//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatedImage.swift
//
//  An animated picture's frames, its timing, and the bound on what it holds.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The frames of an animated file, and how long each shows.
///
/// Decoded once by ``AnimatedImageDecoder``. What it holds is bounded by
/// ``FramePlan``: at most ``AnimatedImageDecoder/byteBudget`` of pixels, however
/// long or large the file.
package struct AnimatedImage: Sendable {
    package struct Frame: Sendable {
        /// The whole picture at this frame, composited: at most the file's size,
        /// and smaller where the plan scaled it down.
        package let image: RGBAImage
        /// How long it shows, in nanoseconds, more than zero.
        package var delayNanos: Int64
        /// Which frame it is, for what a view has already made of it (a
        /// conversion, a picture in the terminal) to be known without holding
        /// its pixels.
        package let decode = ImageDecodeID()

        package init(image: RGBAImage, delayNanos: Int64) {
            self.image = image
            self.delayNanos = delayNanos
        }
    }

    /// The file's own size, whatever its frames were scaled to: what the
    /// picture is laid out as.
    package let width: Int
    package let height: Int
    package let frames: [Frame]
    /// How many times the frames play, or `nil` for forever.
    package let plays: Int?

    package init(width: Int, height: Int, frames: [Frame], plays: Int?) {
        self.width = width
        self.height = height
        self.frames = frames
        self.plays = plays
    }

    /// The frame showing `elapsed` nanoseconds after the first was shown, and
    /// how long after that first showing the next one is due: `nil` once the
    /// plays have ended, on the last frame, as a browser leaves it.
    ///
    /// From the time, not by counting steps: a frame drawn late, or a delay
    /// shorter than a frame of the display, skips what it missed rather than
    /// running slow.
    package func position(atElapsed elapsed: Int64) -> (index: Int, nextChange: Int64?) {
        let total = frames.reduce(0) { $0 + $1.delayNanos }
        guard total > 0, frames.count > 1 else { return (0, nil) }
        let elapsed = max(0, elapsed)
        if let plays {
            let (end, overflowed) = total.multipliedReportingOverflow(by: Int64(plays))
            if !overflowed, elapsed >= end { return (frames.count - 1, nil) }
        }
        let playStart = elapsed - elapsed % total
        var frameEnd = playStart
        for (index, frame) in frames.enumerated() {
            frameEnd += frame.delayNanos
            if elapsed < frameEnd { return (index, frameEnd) }
        }
        return (frames.count - 1, playStart + total)
    }

    /// A delay as a file states it, in milliseconds, as what it plays at.
    ///
    /// A delay of 10 ms or less shows for 100 ms, as every browser has it: such
    /// files exist, and were made expecting that. Anything longer is honoured
    /// (``position(atElapsed:)`` says what happens to one shorter than a frame).
    package static func delayNanos(milliseconds: Int) -> Int64 {
        (milliseconds <= 10 ? 100 : Int64(clamping: milliseconds)) &* 1_000_000
    }
}

/// How much of an animated file is kept: which frames, and at what size.
///
/// The bound: `frameLimit` frames, and `byteBudget` of pixels across them. A
/// file within both is kept whole. Past the frame limit, every `stride`th frame
/// is kept and shows for as long as the ones it stands for. Past the budget,
/// each is scaled down evenly until they fit: a picture that large in a terminal
/// has pixels to spare, and it takes many frames as well to come to this.
package struct FramePlan: Equatable, Sendable {
    /// Keep one frame in this many.
    package let stride: Int
    package let frameWidth: Int
    package let frameHeight: Int

    package init(canvasWidth: Int, canvasHeight: Int, frameCount: Int, byteBudget: Int, frameLimit: Int) {
        stride = max(1, (frameCount + frameLimit - 1) / max(1, frameLimit))
        let kept = max(1, (frameCount + stride - 1) / stride)
        let budgetPerFrame = max(4, byteBudget / kept)
        let (bytes, overflowed) = canvasWidth.multipliedReportingOverflow(by: canvasHeight * 4)
        guard overflowed || bytes > budgetPerFrame else {
            (frameWidth, frameHeight) = (canvasWidth, canvasHeight)
            return
        }
        let scale = (Double(budgetPerFrame) / (Double(canvasWidth) * Double(canvasHeight) * 4)).squareRoot()
        let height = max(1, Int(Double(canvasHeight) * scale))
        // Floored at one row, a very wide picture's width is what has to give.
        let width = max(1, min(Int(Double(canvasWidth) * scale), budgetPerFrame / 4 / height))
        (frameWidth, frameHeight) = (width, height)
    }
}

/// An ``AnimatedImage`` being put together from a decoder's frames, in order.
struct AnimatedImageBuilder {
    private let plan: FramePlan
    private var seen = 0
    private(set) var frames: [AnimatedImage.Frame] = []

    init(plan: FramePlan) {
        self.plan = plan
    }

    /// Adds the next frame of the file, shown for `delayNanos`. `pixels` is
    /// asked for only of a frame that is kept.
    mutating func add(delayNanos: Int64, pixels: () -> RGBAImage?) {
        defer { seen += 1 }
        guard seen.isMultiple(of: plan.stride), let image = pixels() else {
            if !frames.isEmpty { frames[frames.count - 1].delayNanos += delayNanos }
            return
        }
        let scaled =
            (image.width, image.height) == (plan.frameWidth, plan.frameHeight)
            ? image : image.scaledBilinear(to: plan.frameWidth, plan.frameHeight)
        frames.append(AnimatedImage.Frame(image: scaled, delayNanos: delayNanos))
    }
}
