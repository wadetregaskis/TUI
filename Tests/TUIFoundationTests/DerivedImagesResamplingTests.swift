//  🖥️ TUI — A Terminal UI framework for Swift
//  DerivedImagesResamplingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation

/// The small copy the terminal image store keeps of a picture it sent, to
/// derive dimmed and frosted copies from, is shrunk by the resampler every
/// picture is (`PixelResampler`; owner 2026-11-22, O-36 (a)).
@Suite("A sent picture's small copy is shrunk as every picture is")
struct DerivedImagesResamplingTests {

    /// It averaged straight colour beside alpha, so a transparent pixel's
    /// stored colour (green here, to show if it leaks) bled into its opaque
    /// neighbour: half red and half green, at half coverage.
    @Test("A transparent pixel lends the small copy no colour")
    func transparentLendsNoColour() {
        let red: [UInt8] = [255, 0, 0, 255]
        let clear: [UInt8] = [0, 255, 0, 0]
        // Three to two: the second covers half of the red and all of the clear.
        let out = DerivedImages.downsampled((red + red + clear, .rgba, 3, 1), to: (2, 1))
        #expect(Array(out[0..<4]) == [255, 0, 0, 255], "\(out)")
        #expect(Array(out[4..<8]) == [255, 0, 0, 85], "\(out)")
    }

    /// A ratio that is not whole shares the pixel on the boundary between the
    /// two it falls in, where it went whole to one of them.
    @Test("A fractional ratio shares the boundary pixel; RGB comes out opaque")
    func fractionalRatioShares() {
        let out = DerivedImages.downsampled(([0, 0, 0, 255, 255, 255, 0, 0, 0], .rgb, 3, 1), to: (2, 1))
        #expect(out == [85, 85, 85, 255, 85, 85, 85, 255], "\(out)")
    }

    /// Enlarging is as it was: each pixel the one it falls in.
    @Test("Enlarging repeats the pixel each falls in")
    func enlargingRepeats() {
        let out = DerivedImages.downsampled(([10, 20, 30, 200, 100, 50], .rgb, 2, 1), to: (4, 1))
        #expect(out == [10, 20, 30, 255, 10, 20, 30, 255, 200, 100, 50, 255, 200, 100, 50, 255], "\(out)")
    }

    @Test("An empty size or picture gives nothing to draw, not a trap")
    func emptyIsTransparent() {
        #expect(DerivedImages.downsampled(([], .rgba, 0, 0), to: (2, 1)) == [UInt8](repeating: 0, count: 8))
        #expect(DerivedImages.downsampled(([1, 2, 3, 4], .rgba, 1, 1), to: (0, 3)).isEmpty)
    }
}
