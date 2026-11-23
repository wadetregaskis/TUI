//  🖥️ TUI — A Terminal UI framework for Swift
//  AreaResamplingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIImage

/// A picture shrunk to its cell grid averages every pixel each target pixel
/// covers, in one pass (owner 2026-11-22, O-36 (a)).
///
/// The read it replaced took 2 × 2 source pixels per target pixel however far
/// it shrank, so it saw a fraction of a large picture and fine detail broke
/// up into whichever pixels it happened to land on.
@Suite("Shrinking averages every pixel")
struct AreaResamplingTests {

    /// `side` × `side`, black with a one-pixel white line down every tenth
    /// column.
    private func fineLines(side: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(side * side)
        for _ in 0..<side {
            for x in 0..<side {
                pixels.append(x % 10 == 5 ? RGBA(r: 255, g: 255, b: 255) : RGBA(r: 0, g: 0, b: 0))
            }
        }
        return RGBAImage(width: side, height: side, pixels: pixels)
    }

    /// Noise of every channel, alpha included unless `opaque`.
    private func noise(_ width: Int, _ height: Int, seed: UInt64, opaque: Bool = false) -> RGBAImage {
        var state = seed | 1
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for _ in 0..<(width * height) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels.append(
                RGBA(
                    r: UInt8(truncatingIfNeeded: state >> 16),
                    g: UInt8(truncatingIfNeeded: state >> 24),
                    b: UInt8(truncatingIfNeeded: state >> 32),
                    a: opaque ? 255 : UInt8(truncatingIfNeeded: state >> 40)))
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Each target pixel covers ten columns, one of them white: a tenth of
    /// 255, 25.5, the same in every one of them. (Which way a Float's sum of
    /// tenths rounds that half is not the point; that every pixel agrees is.)
    /// The 2 × 2 read landed on columns 0, 10, 20, … and saw none of the
    /// lines: a black picture.
    @Test("One-pixel lines every ten pixels, shrunk ten times, read as one even grey")
    func fineLinesDoNotAlias() {
        let shrunk = fineLines(side: 200).resampled(to: 20, 20)
        #expect(shrunk.width == 20 && shrunk.height == 20)
        let levels = Set(shrunk.pixels.map { "\($0)" })
        #expect(levels.count == 1, "\(levels)")
        let first = shrunk.pixel(at: 0, 0)
        #expect((25...26).contains(first.r) && first.r == first.g && first.g == first.b && first.a == 255, "\(first)")
    }

    /// Weights that add up to one, as closely as a Float can, and a division
    /// by the coverage they add up to: a solid picture comes out exactly the
    /// colour and the coverage it went in with, at every ratio, either way.
    @Test(
        "A solid picture stays exactly solid",
        arguments: [(10, 7), (5, 3), (1, 1), (36, 22), (80, 50), (37, 5), (3, 40)])
    func solidStaysSolid(size: (Int, Int)) {
        for colour in [RGBA(r: 200, g: 17, b: 99), RGBA(r: 12, g: 250, b: 3, a: 77), RGBA(r: 255, g: 255, b: 255)] {
            let solid = RGBAImage(width: 37, height: 23, pixels: [RGBA](repeating: colour, count: 37 * 23))
            let out = solid.resampled(to: size.0, size.1)
            #expect(out.pixels.count == size.0 * size.1)
            #expect(out.pixels.allSatisfy { $0 == colour }, "\(size) \(colour): \(Set(out.pixels.map { "\($0)" }))")
        }
    }

    /// Premultiplied: a pixel counts by its coverage as well as its area. A
    /// transparent pixel's stored colour means nothing (here it is green, to
    /// show if it leaks) and lends none to the red beside it.
    @Test("A transparent edge lends no colour to the pixels it is averaged with")
    func transparentEdgeDoesNotBleed() {
        let red = RGBA(r: 255, g: 0, b: 0)
        let clear = RGBA(r: 0, g: 255, b: 0, a: 0)
        let source = RGBAImage(width: 6, height: 1, pixels: [red, red, red, red, clear, clear])
        // Six to four: each target pixel covers one and a half source pixels.
        let out = source.resampled(to: 4, 1)
        // The third covers pixel 3 whole (red) and half of pixel 4 (clear):
        // two thirds covered, and only red.
        let edge = out.pixel(at: 2, 0)
        #expect((edge.r, edge.g, edge.b) == (255, 0, 0), "\(edge)")
        #expect(edge.a == 170, "\(edge)")
        // The last covers nothing but clear: no colour to recover.
        #expect(out.pixel(at: 3, 0) == RGBA(r: 0, g: 0, b: 0, a: 0))
        // Half coverage counts half: red at 255 beside blue at 85 is three
        // parts red to one blue, at the mean coverage.
        let partial = RGBAImage(width: 2, height: 1, pixels: [red, RGBA(r: 0, g: 0, b: 255, a: 85)])
            .resampled(to: 1, 1).pixel(at: 0, 0)
        #expect((partial.r, partial.g, partial.b, partial.a) == (191, 0, 64, 170), "\(partial)")
    }

    /// Every source pixel's area is shared among the targets it falls in, and
    /// all of it is: so the mean of what comes out is the mean of what went
    /// in, whatever the ratio, short of each target's own rounding.
    @Test(
        "A shrink by a ratio that is not whole keeps the picture's total",
        arguments: [(37, 29, 10, 7), (101, 13, 7, 4), (64, 64, 9, 11), (1000, 3, 3, 1)])
    func nonIntegerRatiosConserve(shape: (Int, Int, Int, Int)) {
        let source = noise(shape.0, shape.1, seed: UInt64(shape.0 &* 31 &+ shape.2), opaque: true)
        let out = source.resampled(to: shape.2, shape.3)
        func mean(_ image: RGBAImage, _ channel: KeyPath<RGBA, UInt8>) -> Double {
            Double(image.pixels.reduce(0) { $0 + Int($1[keyPath: channel]) }) / Double(image.pixels.count)
        }
        for channel in [\RGBA.r, \RGBA.g, \RGBA.b] {
            let difference = abs(mean(out, channel) - mean(source, channel))
            #expect(difference <= 0.5, "\(shape) \(channel): \(mean(source, channel)) in, \(mean(out, channel)) out")
        }
        // And a single bright pixel is not lost between the reads: its 255
        // spread over the area of the target pixels it falls in.
        var spike = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: shape.0 * shape.1)
        spike[(shape.1 / 2) * shape.0 + shape.0 / 2] = RGBA(r: 255, g: 255, b: 255)
        let spread = RGBAImage(width: shape.0, height: shape.1, pixels: spike).resampled(to: shape.2, shape.3)
        let area = Double(shape.0 * shape.1) / Double(shape.2 * shape.3)
        let total = Double(spread.pixels.reduce(0) { $0 + Int($1.r) }) * area
        // Each of the (at most four) targets it touches rounds by half a level.
        #expect(abs(total - 255) <= 2 * area, "\(shape): \(total)")
    }

    /// Each axis is decided on its own: squeezed across, the lines average
    /// out; stretched down, the rows interpolate.
    @Test("A picture shrunk on one axis and enlarged on the other averages one and interpolates the other")
    func mixedAxes() {
        var pixels: [RGBA] = []
        for y in 0..<4 {
            for x in 0..<40 {
                let level = UInt8(y * 80)
                pixels.append(x % 4 == 1 ? RGBA(r: 255, g: level, b: 0) : RGBA(r: 0, g: level, b: 0))
            }
        }
        let out = RGBAImage(width: 40, height: 4, pixels: pixels).resampled(to: 10, 16)
        for y in 0..<16 {
            let row = (0..<10).map { out.pixel(at: $0, y) }
            #expect(Set(row.map(\.r)) == [64], "row \(y): \(row)")
            // Bilinear down: row y reads source row y / 4 and the next by
            // the fraction y % 4 / 4, clamped at the last.
            let low = y / 4
            let high = min(3, low + 1)
            let fraction = Double(y % 4) / 4
            let expected = UInt8((Double(low * 80) * (1 - fraction) + Double(high * 80) * fraction).rounded())
            #expect(row.allSatisfy { $0.g == expected }, "row \(y): \(row.map(\.g)) wanted \(expected)")
        }
    }

    /// A whole factor is the plain block average, rounded to nearest: what the
    /// box reduction gave, except that it truncated.
    @Test("A whole factor is the block average")
    func wholeFactorIsTheBlockAverage() {
        let source = noise(12, 8, seed: 99, opaque: true)
        let out = source.resampled(to: 3, 2)
        for y in 0..<2 {
            for x in 0..<3 {
                var sum = 0
                for dy in 0..<4 { for dx in 0..<4 { sum += Int(source.pixel(at: x * 4 + dx, y * 4 + dy).g) } }
                let mean = Double(sum) / 16
                #expect(abs(Double(out.pixel(at: x, y).g) - mean) <= 0.5, "\(x),\(y): \(out.pixel(at: x, y).g) vs \(mean)")
            }
        }
    }
}
