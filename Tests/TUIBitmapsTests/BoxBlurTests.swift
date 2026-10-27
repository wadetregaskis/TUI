//  🖥️ TUI — A Terminal UI framework for Swift
//  BoxBlurTests.swift
//
//  The box blur a frost and a blurred copy are made with: a running sum along
//  each line, which must draw exactly what summing each window afresh drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation

@Suite("The frost's box blur")
struct BoxBlurTests {

    /// Each window summed afresh, the edges held: what the blur was before it
    /// slid a running sum.
    private func reference(_ pixels: [UInt8], width: Int, height: Int, radius: (across: Int, down: Int)) -> [UInt8] {
        var out = pixels
        for y in 0..<height {
            for x in 0..<width {
                var sums = [0, 0, 0, 0]
                var count = 0
                for dy in -radius.down...radius.down {
                    for dx in -radius.across...radius.across {
                        let at = (min(height - 1, max(0, y + dy)) * width + min(width - 1, max(0, x + dx))) * 4
                        for channel in 0..<4 { sums[channel] += Int(pixels[at + channel]) }
                        count += 1
                    }
                }
                for channel in 0..<4 { out[(y * width + x) * 4 + channel] = UInt8(sums[channel] / count) }
            }
        }
        return out
    }

    /// Bytes that are not a pattern a blur could get right by accident: a
    /// fixed linear congruential sequence.
    private func noise(_ count: Int) -> [UInt8] {
        var state: UInt32 = 0x1234_5678
        return (0..<count).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
    }

    @Test(
        "A running sum draws what summing each window drew",
        arguments: [(1, 1), (7, 3), (16, 9), (3, 20)])
    func matchesTheReference(size: (width: Int, height: Int)) {
        let pixels = noise(size.width * size.height * 4)
        for radius in [(1, 0), (0, 1), (2, 0), (0, 4), (9, 0), (0, 25)] {
            let blurred = DerivedImages.boxBlurred(pixels, width: size.width, height: size.height, radius: radius)
            #expect(
                blurred == reference(pixels, width: size.width, height: size.height, radius: radius),
                "\(size.width)x\(size.height), radius \(radius)")
        }
    }
}
