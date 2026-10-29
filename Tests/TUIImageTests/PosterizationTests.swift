//  🖥️ TUI — A Terminal UI framework for Swift
//  PosterizationTests.swift
//
//  True colour reduces nothing, so a dither there had no error to spread and
//  did nothing. A posterization is a reduction of its own — N evenly spaced
//  levels a channel — which the dither then spreads the error of, in any
//  colour mode (the owner, 2026-10-28). These pin the levels it keeps, the
//  pattern a flat field dithers to, and that true colour without one is the
//  picture it always was.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage
@testable import TUIStyling

@Suite("Posterization")
struct PosterizationTests {

    /// A ramp across every byte on all three channels, red rising, green
    /// falling, blue in steps — far more than four distinct values on each.
    private static func ramp(width: Int = 64, height: Int = 16) -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8(x * 255 / (width - 1))
                pixels.append(RGBA(r: value, g: 255 - value, b: UInt8(y * 255 / (height - 1))))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private static func flat(_ pixel: RGBA, width: Int = 40, height: Int = 20) -> RGBAImage {
        RGBAImage(width: width, height: height, pixels: [RGBA](repeating: pixel, count: width * height))
    }

    /// The distinct values on each channel.
    private static func values(_ pixels: [RGBA]) -> (r: Set<UInt8>, g: Set<UInt8>, b: Set<UInt8>) {
        (Set(pixels.map(\.r)), Set(pixels.map(\.g)), Set(pixels.map(\.b)))
    }

    @Test("Four levels are 0, 85, 170 and 255, and every byte rounds to the nearest")
    func levelsAreEvenAndNearest() {
        let levels = ChannelLevels(count: 4)
        #expect(Set(levels.table) == [0, 85, 170, 255])
        for value in 0...255 {
            let level = Int(levels.table[value])
            for other in [0, 85, 170, 255] {
                #expect(abs(level - value) <= abs(other - value), "\(value) rounds to \(level), not \(other)")
            }
        }
        #expect(Set(ChannelLevels(count: 2).table) == [0, 255])
    }

    @Test("A dithered true-colour ramp keeps exactly the four levels on every channel")
    func trueColourDithersToTheLevels() {
        let converter = ASCIIConverter(
            colorMode: .trueColor, dithering: .floydSteinberg, posterizationLevels: 4)
        let out = converter.recoloured(Self.ramp(), width: 64, height: 16)
        let (red, green, blue) = Self.values(out.pixels)
        #expect(red == [0, 85, 170, 255])
        #expect(green == [0, 85, 170, 255])
        #expect(blue == [0, 85, 170, 255])
    }

    @Test("A flat mid-grey dithers to a pattern of the two levels either side of it, averaging to it")
    func flatGreyBecomesAPattern() {
        let source = Self.flat(RGBA(r: 128, g: 128, b: 128))
        let out = ASCIIConverter(colorMode: .trueColor, dithering: .floydSteinberg, posterizationLevels: 4)
            .recoloured(source, width: source.width, height: source.height)
        #expect(Set(out.pixels.map(\.r)) == [85, 170])
        #expect(out.pixels.allSatisfy { $0.r == $0.g && $0.g == $0.b }, "a grey stays grey")
        let mean = Double(out.pixels.reduce(0) { $0 + Int($1.r) }) / Double(out.pixels.count)
        #expect(abs(mean - 128) < 2, "the field's mean is \(mean)")

        // Two levels: black and white, in about equal measure.
        let binary = ASCIIConverter(colorMode: .trueColor, dithering: .floydSteinberg, posterizationLevels: 2)
            .recoloured(source, width: source.width, height: source.height)
        #expect(Set(binary.pixels.map(\.r)) == [0, 255])
    }

    @Test("Without dithering a posterization is a plain map: a flat field stays flat")
    func unditheredIsAPlainMap() {
        let source = Self.flat(RGBA(r: 128, g: 40, b: 230))
        let out = ASCIIConverter(colorMode: .trueColor, posterizationLevels: 4)
            .recoloured(source, width: source.width, height: source.height)
        #expect(out.pixels.allSatisfy { $0 == RGBA(r: 170, g: 0, b: 255) })
    }

    @Test("Without a posterization, dithering leaves true colour exactly as it was")
    func trueColourWithoutLevelsIsUnchanged() {
        let image = Self.ramp()
        let plain = ASCIIConverter(colorMode: .trueColor)
        let dithered = ASCIIConverter(colorMode: .trueColor, dithering: .floydSteinberg)
        #expect(dithered.recoloured(image, width: 32, height: 8).pixels == plain.recoloured(image, width: 32, height: 8).pixels)
        ColorDepth.withCurrent(.truecolor) {
            #expect(dithered.convert(image, width: 16, height: 4) == plain.convert(image, width: 16, height: 4))
        }
    }

    @Test("256 levels is every byte, and is stored as no posterization at all")
    func everyByteIsNone() {
        #expect(ASCIIConverter(posterizationLevels: 256).posterizationLevels == nil)
        #expect(ASCIIConverter(posterizationLevels: 1).posterizationLevels == 2)
        #expect(ASCIIConverter(posterizationLevels: 7).posterizationLevels == 7)
    }

    @Test("Transparent pixels keep their alpha and hand on no error")
    func alphaIsKept() {
        var pixels = [RGBA](repeating: RGBA(r: 128, g: 128, b: 128, a: 0), count: 64)
        pixels[0] = RGBA(r: 100, g: 100, b: 100, a: 255)
        // The loop itself: the resampler a conversion runs first stores a
        // transparent pixel as transparent black, which would hide the carry.
        var out = RGBAImage(width: 8, height: 8, pixels: pixels)
        var dithered = out.pixels
        ChannelLevels(count: 2).dither(&dithered, width: 8, height: 8)
        out = RGBAImage(width: 8, height: 8, pixels: dithered)
        #expect(out.pixels.map(\.a) == pixels.map(\.a))
        // 100 rounds to black. Each transparent 128 rounds to white and carries
        // none of its -127, so none pushes the next below the split: every one
        // is white. Carried, every other one would have come out black.
        #expect(out.pixels[0] == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(out.pixels.dropFirst().allSatisfy { $0 == RGBA(r: 255, g: 255, b: 255, a: 0) })
    }

    /// Every colour a glyph rendering states, as RGB triples.
    private static func statedColours(_ art: ASCIIArt) -> [[Int]] {
        art.lines.flatMap { line in
            line.matches(of: /[34]8;2;(\d+);(\d+);(\d+)/).map { [Int($0.1)!, Int($0.2)!, Int($0.3)!] }
        }
    }

    /// The glyph renderers whose cells average several pixels — braille's dots,
    /// a shape-matched cell — would draw a colour between two levels without
    /// the cell itself being posterized.
    @Test("Every glyph renderer states only the levels, including those that average a cell")
    func glyphRenderersStateOnlyTheLevels() {
        let image = Self.ramp(width: 128, height: 64)
        for converter in [
            ASCIIConverter(characterSet: .blocks(.fine), colorMode: .trueColor),
            ASCIIConverter(characterSet: .blocks(.braille), colorMode: .trueColor),
            ASCIIConverter(characterSet: .ascii, shapeAware: true, colorMode: .trueColor),
            ASCIIConverter(characterSet: .ascii, colorMode: .trueColor),
        ] {
            for dithering in [DitheringMode.none, .floydSteinberg] {
                let posterized = ASCIIConverter(
                    characterSet: converter.characterSet, shapeAware: converter.shapeAware,
                    colorMode: .trueColor, dithering: dithering, posterizationLevels: 2)
                let art = ColorDepth.withCurrent(.truecolor) { posterized.convert(image, width: 24, height: 8) }
                let colours = Self.statedColours(art)
                #expect(!colours.isEmpty)
                #expect(
                    colours.allSatisfy { $0.allSatisfy { $0 == 0 || $0 == 255 } },
                    "\(converter.characterSet), \(dithering): \(Set(colours.flatMap { $0 }).sorted())")
            }
        }
    }

    @Test("A colour mode that reduces again draws the posterized picture in its own colours")
    func aPaletteModeDrawsThePosterizedPicture() {
        let source = Self.flat(RGBA(r: 128, g: 128, b: 128))
        let plain = ASCIIConverter(colorMode: .ansi256).recoloured(source, width: source.width, height: source.height)
        let posterized = ASCIIConverter(colorMode: .ansi256, posterizationLevels: 2)
            .recoloured(source, width: source.width, height: source.height)
        #expect(plain.pixels != posterized.pixels)
        // 128 rounds up to white, which the 256 colours hold exactly.
        #expect(posterized.pixels.allSatisfy { $0 == RGBA(r: 255, g: 255, b: 255) })
    }
}
