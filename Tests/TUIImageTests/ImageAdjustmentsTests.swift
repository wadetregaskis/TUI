//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageAdjustmentsTests.swift
//
//  Exposure, black point, highlights and contrast: each leaves a picture
//  alone at its default, and does what a photo editor's does (the owner,
//  2026-10-28, afternoon list #29).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIImage

@Suite("Image adjustments")
struct ImageAdjustmentsTests {
    /// The adjusted byte of `byte`.
    private func adjusted(_ byte: UInt8, _ adjustments: ImageAdjustments) -> UInt8 {
        adjustments.table()[Int(byte)]
    }

    @Test("Nothing given changes nothing")
    func identity() {
        #expect(ImageAdjustments.none.isIdentity)
        #expect(ImageAdjustments.none.table() == (0...255).map { UInt8($0) })
    }

    @Test("A stop of exposure doubles a channel's light, and clips at white")
    func exposure() {
        let brighter = ImageAdjustments(exposure: 1)
        #expect(adjusted(64, brighter) == 128)
        #expect(adjusted(200, brighter) == 255)
        #expect(adjusted(64, ImageAdjustments(exposure: -1)) == 32)
    }

    @Test("The black point sends what is at or below it to black and spreads the rest")
    func blackPoint() {
        let lifted = ImageAdjustments(blackPoint: 0.5)
        #expect(adjusted(100, lifted) == 0)
        #expect(adjusted(255, lifted) == 255)
        #expect(adjusted(191, lifted) == 127)
    }

    @Test("Contrast pushes tones from mid-grey, and at -1 flattens them to it")
    func contrast() {
        #expect(adjusted(64, ImageAdjustments(contrast: -1)) == 128)
        #expect(adjusted(200, ImageAdjustments(contrast: -1)) == 128)
        #expect(adjusted(160, ImageAdjustments(contrast: 1)) > 160)
        #expect(adjusted(96, ImageAdjustments(contrast: 1)) < 96)
    }

    @Test("Highlights move only the top half")
    func highlights() {
        let recovered = ImageAdjustments(highlights: -0.5)
        #expect(adjusted(100, recovered) == 100, "the bottom half is untouched")
        #expect(adjusted(255, recovered) < 255, "near-white drawn in")
    }

    @Test("Adjusting a picture keeps each pixel's alpha")
    func keepsAlpha() {
        var image = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 64, g: 64, b: 64, a: 77)])
        ImageAdjustments(exposure: 1).apply(to: &image)
        #expect(image.pixels[0] == RGBA(r: 128, g: 128, b: 128, a: 77))
    }
}
