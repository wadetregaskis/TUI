//  🖥️ TUI — A Terminal UI framework for Swift
//  PixelResampler.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The one resampler a picture's pixels are resized by: a file's, a URL's, a
/// decoded image's and an animation's frames (`RGBAImage.resampled(to:_:)`).
///
/// ## Shrinking: an area average, in one pass
///
/// Each target pixel is the average of EVERY source pixel it covers, each
/// weighted by how much of it the target covers: a target pixel `2.5` source
/// pixels wide takes two whole ones and half of a third, so a pixel on the
/// boundary between two targets is shared between them in proportion. Nothing
/// is skipped however large the source, so a one-pixel line still counts, and
/// the total of the picture is kept: the area each source pixel gives the
/// targets adds up to the whole pixel.
///
/// It replaced a bilinear read, which takes 2 × 2 source pixels per target
/// pixel however far it shrinks — a 4000 × 3000 photo drawn in a 40 × 12 box
/// read about 4 of every 39 pixels, and fine lines broke up — and, for files,
/// a box reduction by whole factors ahead of that read. The owner ruled for
/// one step on 2026-11-22 (O-36 (a): "one-step area average, files too"): two
/// steps are two roundings and two filters where one does the job exactly.
///
/// ## Enlarging: as it was
///
/// An axis the target is longer on (or as long) reads the source as it did
/// before: bilinearly, from the two nearest source pixels at
/// `x × source / target`, or, for a caller that asks, the one pixel that falls
/// there. Area averaging has nothing to add there: a target pixel smaller than
/// a source pixel covers at most two of them. Each axis is decided on its own,
/// so a picture squeezed across and stretched down averages across and
/// interpolates down.
///
/// ## Colour and alpha
///
/// Averaged in the sRGB-encoded values the pixels hold, as the bilinear read
/// and the box reduction both were: not linear light. Weighted by coverage
/// (premultiplied): each colour counts by its alpha as well as its area and is
/// divided back out by the total coverage, so a transparent pixel, whose
/// stored colour means nothing (decoders write it black), lends no colour to
/// its neighbours. A target with no coverage at all is `(0, 0, 0, 0)`.
///
/// ## Separable
///
/// Horizontally then vertically, with each axis's spans and weights worked out
/// once, before any pixel is read. Each source row is filtered across once,
/// into one of two rows of floats, and each target row sums the filtered rows
/// its vertical span covers; every read and write walks memory in order. Two
/// rows suffice because the spans only move forward: a shrinking span shares
/// at most its first row with the one before, and a bilinear one reads two.
package enum PixelResampler {

    /// How an axis the target is longer on reads the source.
    package enum Enlargement: Sendable {
        /// From the two nearest source pixels, weighted by distance.
        case bilinear
        /// The one source pixel the target pixel's leading edge falls in.
        case nearest
    }

    /// One target pixel's reach along one axis: `count` source pixels from
    /// `start`, weighted by `weights[offset ..< offset + count]`.
    struct Span {
        let start: Int
        let count: Int
        let offset: Int
    }

    /// Every target pixel's span along one axis, and their weights end to end.
    struct Axis {
        private(set) var spans: [Span] = []
        private(set) var weights: [Float] = []

        init(source: Int, target: Int, enlargement: Enlargement) {
            spans.reserveCapacity(target)
            if target < source {
                // Target pixel `i` covers source `[i × source / target, (i + 1) × source / target)`.
                // Each bound from an exact integer product, divided once, so a whole ratio's
                // bounds are whole and its weights exact.
                weights.reserveCapacity(source + target)
                for index in 0..<target {
                    let low = Double(index * source) / Double(target)
                    let high = index == target - 1 ? Double(source) : Double((index + 1) * source) / Double(target)
                    let first = Int(low)
                    let end = Swift.min(source, Int(high.rounded(.up)))
                    let offset = weights.count
                    // Divided by the span's own width, not by `source / target`: the weights then
                    // add up to one as closely as a Double can, which is what keeps a solid
                    // picture solid.
                    let width = high - low
                    for column in first..<end {
                        let covered = Swift.min(high, Double(column + 1)) - Swift.max(low, Double(column))
                        weights.append(Float(covered / width))
                    }
                    spans.append(Span(start: first, count: end - first, offset: offset))
                }
                return
            }
            weights.reserveCapacity(target * 2)
            switch enlargement {
            case .nearest:
                for index in 0..<target {
                    spans.append(Span(start: index * source / target, count: 1, offset: weights.count))
                    weights.append(1)
                }
            case .bilinear:
                // The bilinear read's own mapping, transcribed: `x × source / target`, clamped to
                // the last pixel, the fraction taken from the CLAMPED left neighbour.
                let ratio = Double(source) / Double(target)
                for index in 0..<target {
                    let position = Double(index) * ratio
                    var left = Int(position)
                    if left > source - 1 { left = source - 1 }
                    var right = left + 1
                    if right > source - 1 { right = source - 1 }
                    let fraction = position - Double(left)
                    let offset = weights.count
                    // One tap where the second would weigh nothing or be the same pixel.
                    if right == left || fraction == 0 {
                        weights.append(1)
                        spans.append(Span(start: left, count: 1, offset: offset))
                    } else {
                        weights.append(Float(1 - fraction))
                        weights.append(Float(fraction))
                        spans.append(Span(start: left, count: 2, offset: offset))
                    }
                }
            }
        }
    }

    /// `source` resampled to `targetWidth` × `targetHeight`, as straight-alpha
    /// RGBA bytes: all of it, or the `columns` × `rows` window of it.
    ///
    /// - Parameters:
    ///   - source: The picture, row by row, `bytesPerPixel` bytes a pixel:
    ///     4 for straight-alpha RGBA, 3 for RGB (opaque).
    ///   - width: The picture's width in pixels.
    ///   - height: Its height.
    ///   - targetWidth: The width to resample to.
    ///   - targetHeight: The height.
    ///   - columns: The target columns wanted; all of them by default.
    ///   - rows: The target rows wanted; all of them by default.
    ///   - enlargement: How an axis that grows reads the source.
    /// - Returns: `columns.count × rows.count` RGBA pixels, row by row; empty
    ///   when either size is empty, or the source is shorter than it says.
    package static func resampled(
        _ source: [UInt8], bytesPerPixel: Int, width: Int, height: Int,
        to targetWidth: Int, _ targetHeight: Int,
        columns: Range<Int>? = nil, rows: Range<Int>? = nil,
        enlargement: Enlargement = .bilinear
    ) -> [UInt8] {
        guard width > 0, height > 0, targetWidth > 0, targetHeight > 0, bytesPerPixel == 3 || bytesPerPixel == 4,
            source.count >= width * height * bytesPerPixel
        else { return [] }
        let columns = (columns ?? 0..<targetWidth).clamped(to: 0..<targetWidth)
        let rows = (rows ?? 0..<targetHeight).clamped(to: 0..<targetHeight)
        let count = columns.count * rows.count * 4
        guard count > 0 else { return [] }
        return unsafe [UInt8](unsafeUninitializedCapacity: count) { out, initialized in
            source.withUnsafeBytes { bytes in
                unsafe resample(
                    bytes, bytesPerPixel: bytesPerPixel, size: (width, height), to: (targetWidth, targetHeight),
                    window: (columns, rows), enlargement: enlargement, into: UnsafeMutableRawBufferPointer(out))
            }
            initialized = count
        }
    }

    /// The resample itself, into `destination`: `columns.count × rows.count`
    /// RGBA pixels, every byte written.
    ///
    /// The caller has checked the sizes: both positive, `source` holding
    /// `width × height × bytesPerPixel` bytes, the window inside the target,
    /// and `destination` four bytes for each pixel of it.
    ///
    /// Through unsafe pointers, and with no call in the inner loops that a
    /// debug build would make: this runs over every pixel of a picture, and a
    /// debug build is what the framework is developed and demoed in.
    package static func resample(
        _ source: UnsafeRawBufferPointer, bytesPerPixel: Int, size: (width: Int, height: Int),
        to target: (width: Int, height: Int), window: (columns: Range<Int>, rows: Range<Int>),
        enlargement: Enlargement, into destination: UnsafeMutableRawBufferPointer
    ) {
        let (width, height) = size
        let (columns, rows) = window
        guard !columns.isEmpty, !rows.isEmpty, let sourceBase = source.baseAddress,
            let destinationBase = destination.baseAddress
        else { return }
        precondition(source.count >= width * height * bytesPerPixel, "source shorter than its size")
        precondition(destination.count >= columns.count * rows.count * 4, "destination shorter than the window")
        let across = Axis(source: width, target: target.width, enlargement: enlargement)
        let down = Axis(source: height, target: target.height, enlargement: enlargement)
        let pixels = unsafe sourceBase.assumingMemoryBound(to: UInt8.self)
        let output = unsafe destinationBase.assumingMemoryBound(to: UInt8.self)
        let rowFloats = columns.count * 4
        // Two filtered source rows, and the sum for the target row being made.
        let lines = UnsafeMutablePointer<Float>.allocate(capacity: rowFloats * 2)
        let sum = UnsafeMutablePointer<Float>.allocate(capacity: rowFloats)
        defer {
            unsafe lines.deallocate()
            unsafe sum.deallocate()
        }
        // Which source row each of the two filtered rows holds; none yet.
        var heldFirst = -1
        var heldSecond = -1
        let rowBytes = width * bytesPerPixel
        let windowWidth = columns.count
        across.spans.withUnsafeBufferPointer { acrossSpans in
            across.weights.withUnsafeBufferPointer { acrossWeights in
                down.spans.withUnsafeBufferPointer { downSpans in
                    down.weights.withUnsafeBufferPointer { downWeights in
                        guard let acrossSpan = acrossSpans.baseAddress, let acrossWeight = acrossWeights.baseAddress,
                            let downSpan = downSpans.baseAddress, let downWeight = downWeights.baseAddress
                        else { return }
                        // `while`, not `for … in`, through every loop here: a debug build
                        // runs a range's iterator through protocol witnesses, a call or
                        // three per step, and that was most of a debug resample's time.
                        var written = 0
                        var row = rows.lowerBound
                        while row < rows.upperBound {
                            let span = unsafe downSpan[row]
                            unsafe sum.update(repeating: 0, count: rowFloats)
                            var tap = 0
                            while tap < span.count {
                                let sourceRow = span.start + tap
                                var slot = 0
                                if heldFirst == sourceRow {
                                    slot = 0
                                } else if heldSecond == sourceRow {
                                    slot = 1
                                } else {
                                    // The lower row goes: the spans only move forward.
                                    slot = heldFirst < heldSecond ? 0 : 1
                                    unsafe filterRow(
                                        pixels + sourceRow * rowBytes, bytesPerPixel: bytesPerPixel,
                                        spans: acrossSpan, weights: acrossWeight, columns: columns,
                                        into: lines + slot * rowFloats)
                                    if slot == 0 { heldFirst = sourceRow } else { heldSecond = sourceRow }
                                }
                                let weight = unsafe downWeight[span.offset + tap]
                                let line = unsafe lines + slot * rowFloats
                                var index = 0
                                while index < rowFloats {
                                    unsafe sum[index] += weight * line[index]
                                    index += 1
                                }
                                tap += 1
                            }
                            var at = 0
                            while at < windowWidth * 4 {
                                let coverage = unsafe sum[at + 3]
                                // Un-premultiplied: the colour is the coverage-weighted mean,
                                // `Σ(w·a·c) / Σ(w·a)`. Every term is non-negative, so `+ 0.5`
                                // and a truncation round to nearest; a target with no
                                // coverage has no colour to recover.
                                var red = 0, green = 0, blue = 0
                                if coverage > 0 {
                                    red = Int(unsafe sum[at] / coverage + 0.5)
                                    green = Int(unsafe sum[at + 1] / coverage + 0.5)
                                    blue = Int(unsafe sum[at + 2] / coverage + 0.5)
                                }
                                let alpha = Int(coverage + 0.5)
                                // Held to a byte: the weights add up to one only as closely
                                // as a Float can, so a solid 255 may come to 255.00002.
                                unsafe output[written] = red > 255 ? 255 : UInt8(truncatingIfNeeded: red)
                                unsafe output[written + 1] = green > 255 ? 255 : UInt8(truncatingIfNeeded: green)
                                unsafe output[written + 2] = blue > 255 ? 255 : UInt8(truncatingIfNeeded: blue)
                                unsafe output[written + 3] = alpha > 255 ? 255 : UInt8(truncatingIfNeeded: alpha)
                                written += 4
                                at += 4
                            }
                            row += 1
                        }
                    }
                }
            }
        }
    }

    /// One source row filtered across, into `out`: for each target column of
    /// `columns`, the premultiplied colour `Σ(w·a·c)` and the coverage `Σ(w·a)`.
    ///
    /// The two end taps of a span by their own weights; the ones between, which
    /// a shrinking span covers whole and so weighs alike, summed as integers and
    /// weighted once. Those are nearly all of a heavy shrink's pixels, and an
    /// integer sum of bytes is the cheapest arithmetic there is, and exact.
    ///
    /// `Float(Int(byte))`, not `Float(byte)`: there is no `Float.init(UInt8)`,
    /// so the short spelling binds the generic initializer, which an
    /// unspecialised debug build calls through a protocol witness. Same value.
    private static func filterRow(
        _ row: UnsafePointer<UInt8>, bytesPerPixel: Int, spans: UnsafePointer<Span>, weights: UnsafePointer<Float>,
        columns: Range<Int>, into out: UnsafeMutablePointer<Float>
    ) {
        var into = 0
        let opaque = bytesPerPixel == 3
        var column = columns.lowerBound
        while column < columns.upperBound {
            let span = unsafe spans[column]
            let first = span.start * bytesPerPixel
            let last = first + (span.count - 1) * bytesPerPixel
            // The first tap.
            var weight = unsafe weights[span.offset]
            var covered = opaque ? weight * 255 : weight * Float(Int(unsafe row[first + 3]))
            var red = covered * Float(Int(unsafe row[first]))
            var green = covered * Float(Int(unsafe row[first + 1]))
            var blue = covered * Float(Int(unsafe row[first + 2]))
            var coverage = covered
            // The ones between.
            if span.count > 2 {
                var sumRed = 0, sumGreen = 0, sumBlue = 0, sumCoverage = 0
                var at = first + bytesPerPixel
                if opaque {
                    while at < last {
                        sumRed += Int(unsafe row[at])
                        sumGreen += Int(unsafe row[at + 1])
                        sumBlue += Int(unsafe row[at + 2])
                        at += 3
                    }
                    sumRed *= 255
                    sumGreen *= 255
                    sumBlue *= 255
                    sumCoverage = 255 * (span.count - 2)
                } else {
                    while at < last {
                        let alpha = Int(unsafe row[at + 3])
                        sumRed += Int(unsafe row[at]) * alpha
                        sumGreen += Int(unsafe row[at + 1]) * alpha
                        sumBlue += Int(unsafe row[at + 2]) * alpha
                        sumCoverage += alpha
                        at += 4
                    }
                }
                let between = unsafe weights[span.offset + 1]
                red += between * Float(sumRed)
                green += between * Float(sumGreen)
                blue += between * Float(sumBlue)
                coverage += between * Float(sumCoverage)
            }
            // The last tap.
            if span.count > 1 {
                weight = unsafe weights[span.offset + span.count - 1]
                covered = opaque ? weight * 255 : weight * Float(Int(unsafe row[last + 3]))
                red += covered * Float(Int(unsafe row[last]))
                green += covered * Float(Int(unsafe row[last + 1]))
                blue += covered * Float(Int(unsafe row[last + 2]))
                coverage += covered
            }
            unsafe out[into] = red
            unsafe out[into + 1] = green
            unsafe out[into + 2] = blue
            unsafe out[into + 3] = coverage
            into += 4
            column += 1
        }
    }
}
