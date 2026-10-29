//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersImageTests.swift
//
//  Images drawn under hostile rendering options — zoom, cell aspect, edge
//  thresholds, supersampling, pixel budgets, cell geometry, aspect ratios:
//  each must draw without trapping or hanging. See HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIBitmaps
@testable import TUIFoundation
@testable import TUIImage
@testable import TUITestSupport

@MainActor
@Suite("Hostile numbers: images")
struct HostileNumbersImageTests {

    /// A small decoded gradient, so every option has pixels to work on.
    private func picture() -> Image {
        let pixels = (0..<(16 * 8)).map { (index: Int) -> RGBA in
            let red = UInt8(index % 16 * 16)
            let green = UInt8(index / 16 * 32)
            return RGBA(r: red, g: green, b: 128)
        }
        return Image(
            .url("tuikit-test://hostile"), decoded: _DecodedImage(RGBAImage(width: 16, height: 8, pixels: pixels)))
    }

    @Test("An image under any floating-point option draws", arguments: Hostile.doubles)
    func doubleOptions(value: Double) {
        drawHostile(picture().resizable().imageZoom(value))
        drawHostile(picture().imageZoom(value))
        drawHostile(picture().resizable().imageCellAspect(value))
        drawHostile(picture().resizable().imageEdgeThreshold(value))
        drawHostile(picture().resizable().imageEdgeContrast(value))
        drawHostile(picture().resizable().aspectRatio(value, contentMode: .fit))
        drawHostile(picture().resizable().aspectRatio(value, contentMode: .fill))
        drawHostile(picture().resizable().imageCellPoints(TerminalCellPoints(width: value, height: value)))
        drawHostile(picture().resizable().imageURLTimeout(value))
        drawHostile(picture().resizable().imageColorMode(.trueColor).imageZoom(value))
    }

    @Test("An image under any integer option draws", arguments: Hostile.ints)
    func intOptions(value: Int) {
        drawHostile(picture().resizable().imageSupersampling(value))
        drawHostile(picture().resizable().imageMaxPixelCount(value))
        drawHostile(picture().resizable().imageCellPixels(TerminalCellPixels(width: value, height: value)))
        drawHostile(picture().resizable().imageCellPixels(TerminalCellPixels(width: 8, height: value)))
        drawHostile(picture().resizable().frame(width: value, height: 4))
        drawHostile(picture().resizable().frame(width: 8, height: value))
        drawHostile(picture().resizable(capInsets: EdgeInsets(top: value, leading: value, bottom: value, trailing: value)))
    }

    @Test("A raster of any size resamples", arguments: Hostile.ints)
    func rasters(value: Int) {
        let image = RGBAImage(width: 4, height: 4, pixels: Array(repeating: RGBA(r: 1, g: 2, b: 3), count: 16))
        let size = min(max(value, -4), 64)
        _ = image.scaled(to: size, size)
        _ = image.scaledBilinear(to: size, size)
        _ = image.boxReduced(by: value)
        _ = image.sharpened(amount: 1, radiusX: size, radiusY: size)
    }
}
