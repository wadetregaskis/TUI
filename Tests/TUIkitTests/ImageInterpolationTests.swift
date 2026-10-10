//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageInterpolationTests.swift
//
//  `Image.interpolation(_:)` and `antialiased(_:)`: how many samples each
//  cell of a resampled raster takes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitBitmaps
@testable import TUIkitFoundation
@testable import TUIkitImage
@testable import TUIkitTestSupport

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
        return Image(
            .url("tuikit-test://checkerboard"),
            decoded: _DecodedImage(RGBAImage(width: 32, height: 32, pixels: pixels)))
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

    /// A solid red image, already decoded.
    private func red() -> Image {
        Image(
            .url("tuikit-test://red"),
            decoded: _DecodedImage(
                RGBAImage(width: 8, height: 8, pixels: Array(repeating: RGBA(r: 255, g: 0, b: 0), count: 64))))
    }

    private func drawn(_ view: some View) -> String {
        InputChainHarness(width: 8, height: 4)
            .frame(view.imageColorMode(.trueColor).frame(width: 8, height: 4)).lines.joined()
    }

    @Test("A template draws the pixels in the foreground style; the original draws them as they are")
    func templateRendering() {
        let blue = Color.rgb(0, 0, 255)
        let template = drawn(red().renderingMode(.template).foregroundStyle(blue))
        #expect(template.contains("0;0;255") && !template.contains("255;0;0"), "\(template.debugDescription)")
        let original = drawn(red().renderingMode(.original).foregroundStyle(blue))
        #expect(original.contains("255;0;0") && !original.contains("0;0;255"))
    }

    @Test("Images that draw differently are unequal, so a memo cannot serve one for the other")
    func equalityCoversTheDrawingModifiers() {
        let base = checkerboard()
        #expect(base == checkerboard())
        #expect(base != base.interpolation(.high))
        #expect(base != base.antialiased(false))
        #expect(base != base.renderingMode(.template))
        #expect(base.interpolation(.low) != base.interpolation(.high))
    }
}
