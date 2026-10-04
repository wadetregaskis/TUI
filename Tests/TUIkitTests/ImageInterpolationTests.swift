//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageInterpolationTests.swift
//
//  `Image.interpolation(_:)` and `antialiased(_:)`: how many samples each
//  cell of a resampled raster takes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

@MainActor
@Suite("Image interpolation and antialiasing")
struct ImageInterpolationTests {

    /// A fine black-and-white checkerboard, already decoded, so averaging its
    /// pixels and picking one of them draw different cells.
    private func checkerboard() -> Image {
        let pixels = (0..<(32 * 32)).map { index -> RGBA in
            let on = (index % 32 + index / 32).isMultiple(of: 2)
            return on ? RGBA(r: 255, g: 255, b: 255) : RGBA(r: 0, g: 0, b: 0)
        }
        var image = Image(.url("tuikit-test://checkerboard"))
        image.decoded = _DecodedImage(RGBAImage(width: 32, height: 32, pixels: pixels))
        return image
    }

    private func lines(_ image: Image) -> [String] {
        let harness = InputChainHarness(width: 8, height: 4)
        return harness.frame(image.imageColorMode(.trueColor).frame(width: 8, height: 4)).lines
    }

    @Test("No interpolation picks a pixel; high interpolation averages them")
    func qualityChangesTheCells() {
        let nearest = lines(checkerboard().interpolation(.none))
        let averaged = lines(checkerboard().interpolation(.high))
        #expect(nearest != averaged)
    }

    @Test("antialiased(false) is no interpolation, and antialiased(true) changes nothing")
    func antialiasing() {
        #expect(lines(checkerboard().antialiased(false)) == lines(checkerboard().interpolation(.none)))
        #expect(lines(checkerboard().antialiased(true)) == lines(checkerboard()))
    }
}
