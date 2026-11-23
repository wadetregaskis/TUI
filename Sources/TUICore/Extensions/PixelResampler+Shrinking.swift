//  🖥️ TUI — A Terminal UI framework for Swift
//  PixelResampler+Shrinking.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The resampler's shrink: a picture no larger than its source on either axis,
/// in whole numbers, down first.
///
/// The same area average as the general path (``PixelResampler``), so the same
/// answer within a rounding, by a cheaper route: a picture's shrink reads every
/// source pixel (owner 2026-11-22, O-36 (a)), so that read is what has to be
/// cheap. The commit that added this has the measurements.
///
/// ## Exact weights
///
/// Along an axis of `source` pixels shrunk to `target`, both divided by their
/// greatest common divisor to `s` and `t`, target pixel `i` covers
/// `[i × s, (i + 1) × s)` in units of `1 / t` of a source pixel, and source pixel
/// `c` covers `[c × t, (c + 1) × t)`: every overlap is a whole number of units,
/// from 1 to `t`, and a span's add up to `s`. So the weights are integers and
/// exact, a pixel the span covers whole weighs `t`, and a whole ratio (`t` is 1)
/// weighs every pixel 1. The sums are exact too, until the last division.
///
/// ## Down, then across
///
/// Each target row's source rows are summed first, premultiplied as they are
/// read, into one row of four `UInt32` planes (red, green, blue and coverage,
/// each contiguous: the loop over a source row is then plain element-wise
/// arithmetic, which the compiler vectorises, sixteen pixels a step). That pass
/// reads every source pixel once and is most of a large shrink's work. Then that
/// one row is summed across, per target pixel, and divided out. Down first
/// because across is the half that cannot vectorise, the spans being of
/// different lengths: it then runs over `targetHeight × width` sums, not over
/// every source pixel.
///
/// The rows a span covers whole are summed unweighted, two at a time (one
/// read-and-write of the row per two source rows), and the two edge rows are
/// added last by their own weights, with one multiplication by `t` of what was
/// summed before them.
///
/// ## Limits
///
/// A span's down sum is at most `s × 255 × 255`, so it fits a `UInt32` while
/// `s` is at most 66,051; a taller picture with an awkward ratio goes to the
/// general path. So does RGB (three bytes a pixel: the terminal image store's
/// small copies, which are small), and any axis that grows.
extension PixelResampler {

    /// One shrinking axis: every target pixel's span, in exact whole-number
    /// weights (see the extension's notes).
    struct ShrinkingAxis {
        private(set) var spans: [Span] = []
        private(set) var weights: [UInt32] = []
        /// What each span's weights add up to: `s`, the source length over the
        /// greatest common divisor.
        let total: Int
        /// The weight of a pixel a span covers whole: `t`, the target length
        /// over the greatest common divisor. One for a whole ratio.
        let whole: UInt32

        init(source: Int, target: Int) {
            var divisor = source
            var remainder = target
            while remainder != 0 { (divisor, remainder) = (remainder, divisor % remainder) }
            let span = source / divisor
            let unit = target / divisor
            total = span
            whole = UInt32(unit)
            spans.reserveCapacity(target)
            weights.reserveCapacity(source + target)
            var index = 0
            while index < target {
                let low = index * span
                let high = low + span
                let first = low / unit
                let end = (high + unit - 1) / unit
                let offset = weights.count
                var pixel = first
                while pixel < end {
                    weights.append(UInt32(Swift.min(high, (pixel + 1) * unit) - Swift.max(low, pixel * unit)))
                    pixel += 1
                }
                spans.append(Span(start: first, count: end - first, offset: offset))
                index += 1
            }
        }
    }

    /// Whether every channel of a shrink's down sums fits a `UInt32`: see the
    /// extension's limits.
    static let largestExactSpan = Int(UInt32.max) / (255 * 255)

    /// `resample`'s shrink, when it applies: RGBA, and no axis growing. `false`,
    /// with nothing written, when it does not.
    ///
    /// The arguments are `resample`'s, already checked.
    static func shrink(
        _ pixels: UnsafePointer<UInt8>, bytesPerPixel: Int, size: (width: Int, height: Int),
        to target: (width: Int, height: Int), window: (columns: Range<Int>, rows: Range<Int>),
        into output: UnsafeMutablePointer<UInt8>
    ) -> Bool {
        let (width, height) = size
        let (columns, rows) = window
        guard bytesPerPixel == 4, target.width <= width, target.height <= height else { return false }
        let down = ShrinkingAxis(source: height, target: target.height)
        guard down.total <= largestExactSpan else { return false }
        let across = ShrinkingAxis(source: width, target: target.width)
        // The source columns the window's spans read, and one plane of the row for each.
        let firstColumn = across.spans[columns.lowerBound].start
        let lastSpan = across.spans[columns.upperBound - 1]
        let plane = lastSpan.start + lastSpan.count - firstColumn
        let line = UnsafeMutablePointer<UInt32>.allocate(capacity: plane * 4)
        let sums = UnsafeMutablePointer<Float>.allocate(capacity: columns.count * 4)
        defer {
            unsafe line.deallocate()
            unsafe sums.deallocate()
        }
        let rowBytes = width * 4
        // A target pixel's coverage sum is its alpha times every weight of both axes.
        let alphaScale = 1 / Float(down.total * across.total)
        // A whole ratio across of 2, 3 or 4 whose sums fit a `UInt32`: `sumAcrossWhole`.
        let wholeRatio = across.whole == 1 && (2...4).contains(across.total)
            && across.total * down.total <= largestExactSpan ? across.total : 0
        var written = 0
        across.spans.withUnsafeBufferPointer { acrossSpans in
            across.weights.withUnsafeBufferPointer { acrossWeights in
                down.spans.withUnsafeBufferPointer { downSpans in
                    down.weights.withUnsafeBufferPointer { downWeights in
                        guard let acrossSpan = acrossSpans.baseAddress, let acrossWeight = acrossWeights.baseAddress,
                            let downSpan = downSpans.baseAddress, let downWeight = downWeights.baseAddress
                        else { return }
                        var row = rows.lowerBound
                        while row < rows.upperBound {
                            let span = unsafe downSpan[row]
                            let top = unsafe pixels + span.start * rowBytes + firstColumn * 4
                            unsafe sumDown(
                                from: top, rowBytes: rowBytes, span: span, weights: downWeight + span.offset,
                                whole: down.whole, into: line, plane: plane)
                            if wholeRatio > 0 {
                                unsafe sumAcrossWhole(line, plane: plane, ratio: wholeRatio, count: columns.count, into: sums)
                            } else {
                                unsafe sumAcross(
                                    line, plane: plane, spans: acrossSpan, weights: acrossWeight, columns: columns,
                                    firstColumn: firstColumn, into: sums)
                            }
                            unsafe writePixels(sums, count: columns.count, alphaScale: alphaScale, into: output + written)
                            written += columns.count * 4
                            row += 1
                        }
                    }
                }
            }
        }
        return true
    }

    /// One target row's source rows, from `top`, premultiplied and summed by
    /// their weights into `line`'s four planes.
    private static func sumDown(
        from top: UnsafePointer<UInt8>, rowBytes: Int, span: Span, weights: UnsafePointer<UInt32>, whole: UInt32,
        into line: UnsafeMutablePointer<UInt32>, plane: Int
    ) {
        if whole == 1 {
            // A whole ratio: every row weighs one, so all of them are summed alike.
            var tap = 0
            while tap < span.count {
                let lower = tap + 1 < span.count ? unsafe top + (tap + 1) * rowBytes : nil
                unsafe addRows(top + tap * rowBytes, lower, first: tap == 0, into: line, plane: plane)
                tap += 2
            }
            return
        }
        let bottom = unsafe top + (span.count - 1) * rowBytes
        if span.count == 1 {
            // Inside one source row: it alone, by the whole span's weight.
            unsafe addEdges(top, bottom, weights: (weights[0], 0), whole: 0, onto: false, into: line, plane: plane)
            return
        }
        // The rows between the two edges, which the span covers whole.
        var tap = 1
        while tap < span.count - 1 {
            let lower = tap + 1 < span.count - 1 ? unsafe top + (tap + 1) * rowBytes : nil
            unsafe addRows(top + tap * rowBytes, lower, first: tap == 1, into: line, plane: plane)
            tap += 2
        }
        let edges = unsafe (weights[0], weights[span.count - 1])
        unsafe addEdges(top, bottom, weights: edges, whole: whole, onto: span.count > 2, into: line, plane: plane)
    }

    /// `upper`'s premultiplied pixels and `lower`'s (when there is one), each
    /// weighing one, into `line`'s planes: stored when `first`, else added.
    ///
    /// `UInt16` products: a channel times its alpha is at most 255 × 255, which
    /// fits, and a byte-by-byte multiply into sixteen bits is what the vector
    /// unit does in one step. Every `&` operator is safe here (see the
    /// extension's limits) and spares a debug build an overflow check a step.
    @inline(__always)
    private static func addRows(
        _ upper: UnsafePointer<UInt8>, _ lower: UnsafePointer<UInt8>?, first: Bool,
        into line: UnsafeMutablePointer<UInt32>, plane: Int
    ) {
        let reds = unsafe line
        let greens = unsafe line + plane
        let blues = unsafe line + 2 * plane
        let alphas = unsafe line + 3 * plane
        var x = 0
        guard let lower = unsafe lower else {
            if first {
                while x < plane {
                    let at = x * 4
                    let alpha = UInt16(unsafe upper[at + 3])
                    unsafe reds[x] = UInt32(UInt16(upper[at]) &* alpha)
                    unsafe greens[x] = UInt32(UInt16(upper[at + 1]) &* alpha)
                    unsafe blues[x] = UInt32(UInt16(upper[at + 2]) &* alpha)
                    unsafe alphas[x] = UInt32(alpha)
                    x += 1
                }
            } else {
                while x < plane {
                    let at = x * 4
                    let alpha = UInt16(unsafe upper[at + 3])
                    unsafe reds[x] &+= UInt32(UInt16(upper[at]) &* alpha)
                    unsafe greens[x] &+= UInt32(UInt16(upper[at + 1]) &* alpha)
                    unsafe blues[x] &+= UInt32(UInt16(upper[at + 2]) &* alpha)
                    unsafe alphas[x] &+= UInt32(alpha)
                    x += 1
                }
            }
            return
        }
        // Two loops, not one with `first` inside it: the compiler does not split the loop on
        // it, and the test in the loop kept it from vectorising.
        if first {
            while x < plane {
                let at = x * 4
                let upperAlpha = UInt16(unsafe upper[at + 3])
                let lowerAlpha = UInt16(unsafe lower[at + 3])
                unsafe reds[x] = UInt32(UInt16(upper[at]) &* upperAlpha) &+ UInt32(UInt16(lower[at]) &* lowerAlpha)
                unsafe greens[x] =
                    UInt32(UInt16(upper[at + 1]) &* upperAlpha) &+ UInt32(UInt16(lower[at + 1]) &* lowerAlpha)
                unsafe blues[x] =
                    UInt32(UInt16(upper[at + 2]) &* upperAlpha) &+ UInt32(UInt16(lower[at + 2]) &* lowerAlpha)
                unsafe alphas[x] = UInt32(upperAlpha &+ lowerAlpha)
                x += 1
            }
        } else {
            while x < plane {
                let at = x * 4
                let upperAlpha = UInt16(unsafe upper[at + 3])
                let lowerAlpha = UInt16(unsafe lower[at + 3])
                unsafe reds[x] &+= UInt32(UInt16(upper[at]) &* upperAlpha) &+ UInt32(UInt16(lower[at]) &* lowerAlpha)
                unsafe greens[x] &+=
                    UInt32(UInt16(upper[at + 1]) &* upperAlpha) &+ UInt32(UInt16(lower[at + 1]) &* lowerAlpha)
                unsafe blues[x] &+=
                    UInt32(UInt16(upper[at + 2]) &* upperAlpha) &+ UInt32(UInt16(lower[at + 2]) &* lowerAlpha)
                unsafe alphas[x] &+= UInt32(upperAlpha &+ lowerAlpha)
                x += 1
            }
        }
    }

    /// A span's two edge rows, `upper` and `lower`, premultiplied and by their
    /// own weights, into `line`'s planes: onto `whole` times what the planes
    /// hold when `onto` (the rows between, summed unweighted), else stored.
    @inline(__always)
    private static func addEdges(
        _ upper: UnsafePointer<UInt8>, _ lower: UnsafePointer<UInt8>, weights: (UInt32, UInt32), whole: UInt32,
        onto: Bool, into line: UnsafeMutablePointer<UInt32>, plane: Int
    ) {
        let reds = unsafe line
        let greens = unsafe line + plane
        let blues = unsafe line + 2 * plane
        let alphas = unsafe line + 3 * plane
        let (upperWeight, lowerWeight) = weights
        var x = 0
        // Two loops, as in `addRows`; the first scales what the planes hold to the edges'
        // units, `whole` to a pixel.
        if onto {
            while x < plane {
                let at = x * 4
                let upperAlpha = UInt16(unsafe upper[at + 3])
                let lowerAlpha = UInt16(unsafe lower[at + 3])
                unsafe reds[x] = reds[x] &* whole &+ UInt32(UInt16(upper[at]) &* upperAlpha) &* upperWeight
                    &+ UInt32(UInt16(lower[at]) &* lowerAlpha) &* lowerWeight
                unsafe greens[x] = greens[x] &* whole &+ UInt32(UInt16(upper[at + 1]) &* upperAlpha) &* upperWeight
                    &+ UInt32(UInt16(lower[at + 1]) &* lowerAlpha) &* lowerWeight
                unsafe blues[x] = blues[x] &* whole &+ UInt32(UInt16(upper[at + 2]) &* upperAlpha) &* upperWeight
                    &+ UInt32(UInt16(lower[at + 2]) &* lowerAlpha) &* lowerWeight
                unsafe alphas[x] = alphas[x] &* whole &+ UInt32(upperAlpha) &* upperWeight
                    &+ UInt32(lowerAlpha) &* lowerWeight
                x += 1
            }
        } else {
            while x < plane {
                let at = x * 4
                let upperAlpha = UInt16(unsafe upper[at + 3])
                let lowerAlpha = UInt16(unsafe lower[at + 3])
                unsafe reds[x] = UInt32(UInt16(upper[at]) &* upperAlpha) &* upperWeight
                    &+ UInt32(UInt16(lower[at]) &* lowerAlpha) &* lowerWeight
                unsafe greens[x] = UInt32(UInt16(upper[at + 1]) &* upperAlpha) &* upperWeight
                    &+ UInt32(UInt16(lower[at + 1]) &* lowerAlpha) &* lowerWeight
                unsafe blues[x] = UInt32(UInt16(upper[at + 2]) &* upperAlpha) &* upperWeight
                    &+ UInt32(UInt16(lower[at + 2]) &* lowerAlpha) &* lowerWeight
                unsafe alphas[x] = UInt32(upperAlpha) &* upperWeight &+ UInt32(lowerAlpha) &* lowerWeight
                x += 1
            }
        }
    }

    /// `line`'s planes summed across, each window column's span by its
    /// weights, into `sums`' four planes of `columns.count` floats.
    ///
    /// In `Int`: the sums of both axes reach `s × s′ × 255 × 255`, past a
    /// `UInt32` at an awkward ratio. The edge taps by their weights, the ones
    /// between summed and multiplied once.
    private static func sumAcross(
        _ line: UnsafeMutablePointer<UInt32>, plane: Int, spans: UnsafePointer<Span>, weights: UnsafePointer<UInt32>,
        columns: Range<Int>, firstColumn: Int, into sums: UnsafeMutablePointer<Float>
    ) {
        let reds = unsafe line - firstColumn
        let greens = unsafe reds + plane
        let blues = unsafe reds + 2 * plane
        let alphas = unsafe reds + 3 * plane
        let count = columns.count
        var index = 0
        var column = columns.lowerBound
        while column < columns.upperBound {
            let span = unsafe spans[column]
            let first = span.start
            let last = first + span.count - 1
            var weight = Int(unsafe weights[span.offset])
            var red = unsafe weight &* Int(reds[first])
            var green = unsafe weight &* Int(greens[first])
            var blue = unsafe weight &* Int(blues[first])
            var coverage = unsafe weight &* Int(alphas[first])
            if span.count > 2 {
                var betweenRed = 0
                var betweenGreen = 0
                var betweenBlue = 0
                var betweenCoverage = 0
                var at = first + 1
                while at < last {
                    unsafe betweenRed &+= Int(reds[at])
                    unsafe betweenGreen &+= Int(greens[at])
                    unsafe betweenBlue &+= Int(blues[at])
                    unsafe betweenCoverage &+= Int(alphas[at])
                    at += 1
                }
                weight = Int(unsafe weights[span.offset + 1])
                red &+= weight &* betweenRed
                green &+= weight &* betweenGreen
                blue &+= weight &* betweenBlue
                coverage &+= weight &* betweenCoverage
            }
            if span.count > 1 {
                weight = Int(unsafe weights[span.offset + span.count - 1])
                red &+= unsafe weight &* Int(reds[last])
                green &+= unsafe weight &* Int(greens[last])
                blue &+= unsafe weight &* Int(blues[last])
                coverage &+= unsafe weight &* Int(alphas[last])
            }
            unsafe sums[index] = Float(red)
            unsafe sums[count + index] = Float(green)
            unsafe sums[2 * count + index] = Float(blue)
            unsafe sums[3 * count + index] = Float(coverage)
            index += 1
            column += 1
        }
    }

    /// `sumAcross` for a whole ratio of 2, 3 or 4: each target pixel the plain
    /// sum of the `ratio` pixels from `ratio × index`, which is where the
    /// window's first span starts (`line` begins at it).
    ///
    /// One loop per ratio with the taps written out, rather than one loop over
    /// `ratio` taps: the compiler reads a fixed stride of 2, 3 or 4 as one
    /// de-interleaving load and vectorises the loop; over a runtime count it
    /// does not, and a loop over five taps or more measured slower than
    /// `sumAcross`, so those go there. A `UInt32` sum: the caller checks it fits.
    private static func sumAcrossWhole(
        _ line: UnsafeMutablePointer<UInt32>, plane: Int, ratio: Int, count: Int, into sums: UnsafeMutablePointer<Float>
    ) {
        var channel = 0
        while channel < 4 {
            let from = unsafe line + channel * plane
            let into = unsafe sums + channel * count
            var index = 0
            switch ratio {
            case 2:
                while index < count {
                    unsafe into[index] = Float(from[index * 2] &+ from[index * 2 + 1])
                    index += 1
                }
            case 3:
                while index < count {
                    unsafe into[index] = Float(from[index * 3] &+ from[index * 3 + 1] &+ from[index * 3 + 2])
                    index += 1
                }
            default:
                while index < count {
                    let at = index * 4
                    unsafe into[index] = Float(from[at] &+ from[at + 1] &+ from[at + 2] &+ from[at + 3])
                    index += 1
                }
            }
            channel += 1
        }
    }

    /// `sums`' four planes divided out into `count` straight-alpha RGBA pixels.
    ///
    /// The colour is `Σ(w·a·c) / Σ(w·a)`; the alpha, the coverage over every
    /// weight. Rounded half up, as the general path rounds, and held to 255
    /// (a Float's quotient of an exact multiple can come out a hair over). No
    /// coverage: `(0, 0, 0, 0)`.
    ///
    /// `(value.rounded() + 2²³).bitPattern & 0xFF` is the byte, not a trick on
    /// the rounding: a Float from 2²³ up to 2²⁴ is spaced one apart, so adding
    /// 2²³ to a whole number from 0 to 255 is exact and leaves it in the low
    /// byte of the bit pattern. Unlike `UInt8(value)` it has no range check to
    /// trap on, so the loop has no branch and vectorises, four pixels a step.
    private static func writePixels(
        _ sums: UnsafeMutablePointer<Float>, count: Int, alphaScale: Float, into output: UnsafeMutablePointer<UInt8>
    ) {
        let greens = unsafe sums + count
        let blues = unsafe sums + 2 * count
        let alphas = unsafe sums + 3 * count
        let bytes = UnsafeMutableRawPointer(output)
        let exponent: Float = 8_388_608
        var index = 0
        while index < count {
            let coverage = unsafe alphas[index]
            let scale: Float = coverage > 0 ? 1 / coverage : 0
            // Ternaries, not `min`: a debug build calls the generic `min` through a witness.
            var red = unsafe sums[index] * scale
            var green = unsafe greens[index] * scale
            var blue = unsafe blues[index] * scale
            var alpha = coverage * alphaScale
            red = red > 255 ? 255 : red
            green = green > 255 ? 255 : green
            blue = blue > 255 ? 255 : blue
            alpha = alpha > 255 ? 255 : alpha
            let pixel = ((red.rounded() + exponent).bitPattern & 0xFF)
                | ((green.rounded() + exponent).bitPattern & 0xFF) << 8
                | ((blue.rounded() + exponent).bitPattern & 0xFF) << 16
                | ((alpha.rounded() + exponent).bitPattern & 0xFF) << 24
            unsafe bytes.storeBytes(of: pixel.littleEndian, toByteOffset: index * 4, as: UInt32.self)
            index += 1
        }
    }
}
