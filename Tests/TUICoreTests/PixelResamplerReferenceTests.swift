//  🖥️ TUI — A Terminal UI framework for Swift
//  PixelResamplerReferenceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

/// The resampler's shrink (exact integer weights, down first, over
/// premultiplied planes) against the area average written out the plain way:
/// every target pixel straight from every source pixel it overlaps, in `Double`.
///
/// The shrink is a different route to the same number, taken for speed, so
/// this is what keeps it honest at ratios the other suites do not reach:
/// whole and not, either axis kept, one target pixel, translucent noise.
@Suite("The resampler's shrink agrees with a plain area average")
struct PixelResamplerReferenceTests {

    /// `width × height` RGBA noise; alpha too unless `opaque`.
    private func noise(_ width: Int, _ height: Int, seed: UInt64, opaque: Bool) -> [UInt8] {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[pixel * 4] = UInt8(truncatingIfNeeded: state >> 16)
            bytes[pixel * 4 + 1] = UInt8(truncatingIfNeeded: state >> 24)
            bytes[pixel * 4 + 2] = UInt8(truncatingIfNeeded: state >> 32)
            bytes[pixel * 4 + 3] = opaque ? 255 : UInt8(truncatingIfNeeded: state >> 40)
        }
        return bytes
    }

    /// The area average, the plain way: each target pixel's overlap with each
    /// source pixel as a fraction of its area, premultiplied, divided out and
    /// rounded half up.
    private func reference(_ source: [UInt8], _ width: Int, _ height: Int, to size: (Int, Int)) -> [UInt8] {
        let (targetWidth, targetHeight) = size
        var out = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        func bounds(_ index: Int, _ from: Int, _ to: Int) -> (low: Double, high: Double) {
            (Double(index * from) / Double(to), Double((index + 1) * from) / Double(to))
        }
        for row in 0..<targetHeight {
            let down = bounds(row, height, targetHeight)
            for column in 0..<targetWidth {
                let across = bounds(column, width, targetWidth)
                let area = (across.high - across.low) * (down.high - down.low)
                var sums = [0.0, 0.0, 0.0, 0.0]
                for y in Int(down.low)..<min(height, Int(down.high.rounded(.up))) {
                    let tall = min(down.high, Double(y + 1)) - max(down.low, Double(y))
                    for x in Int(across.low)..<min(width, Int(across.high.rounded(.up))) {
                        let wide = min(across.high, Double(x + 1)) - max(across.low, Double(x))
                        let at = (y * width + x) * 4
                        let coverage = wide * tall / area * Double(source[at + 3])
                        for channel in 0..<3 { sums[channel] += coverage * Double(source[at + channel]) }
                        sums[3] += coverage
                    }
                }
                let at = (row * targetWidth + column) * 4
                if sums[3] > 0 {
                    for channel in 0..<3 { out[at + channel] = UInt8(min(255, (sums[channel] / sums[3]).rounded())) }
                }
                out[at + 3] = UInt8(min(255, sums[3].rounded()))
            }
        }
        return out
    }

    /// The largest difference, in levels, of any channel of any pixel.
    private func largestDifference(_ one: [UInt8], _ other: [UInt8]) -> Int {
        zip(one, other).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    /// Within one level: the shrink divides in `Float`, the reference in
    /// `Double`, and a quotient on a half can round either way.
    @Test(
        "Within one level of the plain average, at whole and fractional ratios",
        arguments: [
            (64, 48, 16, 12), (60, 45, 30, 15), (90, 60, 30, 20), (64, 48, 13, 7), (91, 61, 30, 20),
            (37, 29, 36, 28), (100, 75, 7, 5), (50, 50, 49, 3), (300, 200, 1, 1), (1000, 3, 3, 1),
            (40, 30, 40, 7), (40, 30, 9, 30), (250, 140, 50, 28), (203, 117, 40, 13),
        ])
    func agreesWithTheReference(shape: (Int, Int, Int, Int)) {
        let (width, height, targetWidth, targetHeight) = shape
        for opaque in [true, false] {
            let source = noise(width, height, seed: UInt64(width &* 131 &+ targetWidth), opaque: opaque)
            let shrunk = PixelResampler.resampled(
                source, bytesPerPixel: 4, width: width, height: height, to: targetWidth, targetHeight)
            let expected = reference(source, width, height, to: (targetWidth, targetHeight))
            #expect(shrunk.count == expected.count)
            #expect(largestDifference(shrunk, expected) <= 1, "\(shape) opaque: \(opaque)")
        }
    }

    /// A window is what the whole resample gives there, to the byte: the
    /// terminal image store asks for one cell's pixels at a time.
    @Test(
        "A window of the target is that part of the whole",
        arguments: [
            (400, 300, 90, 70, 13..<41, 5..<66), (400, 300, 100, 75, 0..<1, 74..<75), (97, 61, 13, 7, 12..<13, 0..<7),
            (400, 300, 200, 100, 37..<90, 3..<4), (300, 300, 100, 75, 99..<100, 0..<75),
        ])
    func windowIsPartOfTheWhole(shape: (Int, Int, Int, Int, Range<Int>, Range<Int>)) {
        let (width, height, targetWidth, targetHeight, columns, rows) = shape
        let source = noise(width, height, seed: 7, opaque: false)
        let whole = PixelResampler.resampled(
            source, bytesPerPixel: 4, width: width, height: height, to: targetWidth, targetHeight)
        let part = PixelResampler.resampled(
            source, bytesPerPixel: 4, width: width, height: height, to: targetWidth, targetHeight,
            columns: columns, rows: rows)
        var expected: [UInt8] = []
        for row in rows {
            for column in columns {
                let at = (row * targetWidth + column) * 4
                expected.append(contentsOf: whole[at..<at + 4])
            }
        }
        #expect(part == expected, "\(columns) \(rows)")
    }

    /// RGB takes the general path, RGBA the shrink: an opaque picture comes
    /// out within a level the same either way.
    @Test("The general path and the shrink agree on an opaque picture")
    func generalPathAgrees() {
        let rgba = noise(123, 77, seed: 3, opaque: true)
        var rgb: [UInt8] = []
        for pixel in 0..<(123 * 77) { rgb.append(contentsOf: rgba[pixel * 4..<pixel * 4 + 3]) }
        let shrunk = PixelResampler.resampled(rgba, bytesPerPixel: 4, width: 123, height: 77, to: 31, 19)
        let general = PixelResampler.resampled(rgb, bytesPerPixel: 3, width: 123, height: 77, to: 31, 19)
        #expect(largestDifference(shrunk, general) <= 1)
    }
}
