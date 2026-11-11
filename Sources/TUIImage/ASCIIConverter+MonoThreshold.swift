//  🖥️ TUI — A Terminal UI framework for Swift
//  ASCIIConverter+MonoThreshold.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension ASCIIConverter {

    /// Mid-luminance: the split every binary renderer used before there was a
    /// better answer, and the one they fall back to when there is not.
    static let midLuminance: Double = 128

    /// The luminance that best separates ink from background in this image.
    ///
    /// ## Why a fixed split is the wrong one
    ///
    /// Three of the renderers reduce a pixel to one bit — `.blocks(.solid)` and
    /// `.blocks(.fine)` in monochrome, and braille in every mode, whose dots
    /// carry the shape while colour is averaged separately. All three split at
    /// mid-luminance, which assumes the image's tones straddle the middle.
    /// Photographs mostly do not: the shipped demo image is **87% below
    /// mid-luminance**, so almost nothing crossed the line and the render came
    /// out nearly blank. Correcting the polarity (see ``isMonoInk(_:)``) fixed
    /// which side was ink; it could not fix a threshold sitting outside the
    /// tones entirely.
    ///
    /// ## Otsu's method
    ///
    /// Take the split that makes the two sides most unlike each other: the
    /// luminance maximising `wB · wF · (mB − mF)²`, where `w` are the two sides'
    /// pixel counts and `m` their mean luminances. One pass to build a 256-bin
    /// histogram and one pass over the bins — no iteration, no parameters — and
    /// it lands where a person would draw the line on a bimodal image, which is
    /// what a subject against a background is. On that same demo image it
    /// chooses 75.5 rather than 128, and the half-block render goes from 15% ink
    /// to 28% — a whole silhouette instead of pieces of one.
    ///
    /// ## When it declines
    ///
    /// A nearly-uniform image has no two sides to be unlike. Otsu will still
    /// return *a* split, and it will be sensor noise or gradient banding
    /// amplified into a field of speckle — strictly worse than the flat result
    /// the fixed threshold gives. So an image whose luminance spans less than
    /// ``minimumSeparableSpread`` keeps ``midLuminance``, and a flat image stays
    /// flat.
    ///
    /// - Parameter image: The image as the renderer will sample it — scaled,
    ///   area-reduced, and NOT yet dithered. Dithering quantises against this
    ///   threshold, so measuring after it would be measuring its own output.
    static func monoInkThreshold(for image: RGBAImage) -> Double {
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        addToInkHistogram(image, &histogram, &total)
        return inkThreshold(histogram: histogram, total: total)
    }

    /// Counts `image`'s pixels into `histogram`, by luminance, where
    /// ``monoInkThreshold(for:)`` would.
    private static func addToInkHistogram(_ image: RGBAImage, _ histogram: inout [Int], _ total: inout Int) {
        // Only the pixels the split decides. Every consumer asks coverage first —
        // `isMonoInk` is `pixel.a >= 128 && …`, braille's dot gate is
        // `coverage >= 128, …`, and the pixel path's mono quantiser and the dither
        // go through `isMonoInk` — so a pixel below half coverage is never ink
        // whatever this returns, and must not move where the line falls. It did:
        // the picture is no longer flattened over black (§42), both resamplers
        // write an uncovered pixel as `(0, 0, 0, 0)`, and a logo's transparent
        // surround was a spike at level 0 that Otsu split against instead of
        // splitting the subject. Tones of 110 and 190 behind a surround nine times
        // their size split at 0.5, not 110.5 — every covered pixel ink, the mark a
        // solid silhouette.
        //
        // The ½ rule and not `a > 0`, because that is the rule the consumers apply;
        // and not a coverage-weighted vote, which would re-admit exactly the pixels
        // no consumer will draw. An opaque picture's histogram is unchanged, and a
        // wholly transparent one falls to the `total > 0` guard below. See
        // "Opacity as composition" §72.2.
        for pixel in image.pixels where pixel.a >= 128 {
            // The same BT.601 luminance every renderer thresholds on, bucketed
            // to whole levels — the histogram's resolution IS the output's.
            histogram[min(255, max(0, Int(pixel.luminance)))] += 1
            total += 1
        }
    }

    /// Otsu's split of a histogram ``addToInkHistogram(_:_:_:)`` counted
    /// `total` pixels into.
    private static func inkThreshold(histogram: [Int], total: Int) -> Double {
        guard total > 0 else { return midLuminance }

        guard let lowest = histogram.firstIndex(where: { $0 > 0 }),
            let highest = histogram.lastIndex(where: { $0 > 0 }),
            highest - lowest >= minimumSeparableSpread
        else { return midLuminance }

        var weightedTotal = 0
        for level in lowest...highest { weightedTotal += level * histogram[level] }

        var backgroundCount = 0
        var backgroundWeighted = 0
        var bestVariance = -1.0
        var bestLevel = lowest
        for level in lowest..<highest {
            backgroundCount += histogram[level]
            backgroundWeighted += level * histogram[level]
            let foregroundCount = total - backgroundCount
            guard backgroundCount > 0, foregroundCount > 0 else { continue }
            let backgroundMean = Double(backgroundWeighted) / Double(backgroundCount)
            let foregroundMean =
                Double(weightedTotal - backgroundWeighted) / Double(foregroundCount)
            let separation = backgroundMean - foregroundMean
            let variance = Double(backgroundCount) * Double(foregroundCount) * separation
                * separation
            if variance > bestVariance {
                bestVariance = variance
                bestLevel = level
            }
        }
        // Between the two bins rather than on the lower one: `bestLevel` is the
        // last level counted as background, so the split sits above it.
        return Double(bestLevel) + 0.5
    }

    /// How far apart an image's darkest and brightest levels must be before a
    /// computed threshold beats a fixed one.
    ///
    /// Sixteen levels of 256 — a sixteenth of the range. Below that there is no
    /// subject to separate from a background, only noise, and Otsu would split
    /// the noise down the middle and render it as speckle.
    static let minimumSeparableSpread = 16

    /// The ink threshold an animation's frames share: Otsu's split of all of
    /// them together, as ``inkThreshold`` states one (`0...1`), for every frame
    /// to be converted with.
    ///
    /// ## Why one for all the frames
    ///
    /// Measured from each frame, the split moves with what moves in the
    /// picture, and a part that holds still can cross it. The Example's
    /// bouncing ball (the 80 × 40 one, before 2026-11-11) was a dark sky
    /// (luminance 29), a ground a little lighter (61) and a ball much lighter
    /// (102 to 221), whose split falls right by the ground's level. Resampled
    /// to the cells, the ball's edges blend into the pixels around them, and
    /// where the ball was moved the split from one side of the ground to the
    /// other: drawn in mono at 100 × 25 cells the ground was ink in 6 frames of
    /// 16 and paper in the rest, flashing white and black as the ball bounced
    /// (the owner, 2026-11-10, item 23). One split, from every frame, puts each
    /// tone on one side for the whole animation, so what holds still stays
    /// still.
    ///
    /// ## What it is measured on
    ///
    /// Each frame's tones as the converters read them: after the adjustments,
    /// the tone curve and the posterize, which move tones, and so where the
    /// split falls. Not after the resampling and the edge lift, which depend on
    /// the box a frame is drawn in and move only the pixels at an edge, so one
    /// measure serves every box, the glyphs' and the pixels' alike. A long or
    /// large animation is measured at a smaller size, up to
    /// ``sharedThresholdPixelBudget`` pixels in all: a histogram needs no more.
    ///
    /// - Parameter frames: Every frame of the animation, composited.
    package func sharedInkThreshold(of frames: [RGBAImage]) -> Double {
        let pixelCount = frames.reduce(0) { $0 + $1.width * $1.height }
        let scale = min(1, (Double(Self.sharedThresholdPixelBudget) / Double(max(1, pixelCount))).squareRoot())
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        for frame in frames where frame.width > 0 && frame.height > 0 {
            var tones =
                scale < 1
                ? frame.scaledBilinear(
                    to: max(1, Int(Double(frame.width) * scale)), max(1, Int(Double(frame.height) * scale)))
                : frame
            adjustments.apply(to: &tones)
            if let toneCurve, !toneCurve.isIdentity {
                tones.mapPixels(toneCurve.apply(to:))
            }
            Self.addToInkHistogram(posterized(tones), &histogram, &total)
        }
        return Self.inkThreshold(histogram: histogram, total: total) / 255
    }

    /// The most pixels ``sharedInkThreshold(of:)`` measures, across all the
    /// frames: a million, a few milliseconds of work.
    static let sharedThresholdPixelBudget = 1 << 20
}
