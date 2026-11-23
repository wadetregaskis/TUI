//  🖥️ TUI — A Terminal UI framework for Swift
//  RGBAImageScalingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIImage

/// The resamplers, and the channel one of them was quietly throwing away.
@Suite("Image scaling keeps every channel")
struct RGBAImageScalingTests {

    /// A 2x2 image whose top-left pixel is fully transparent.
    private func cornerCutout() -> RGBAImage {
        RGBAImage(
            width: 2, height: 2,
            pixels: [
                RGBA(r: 10, g: 20, b: 30, a: 0),
                RGBA(r: 10, g: 20, b: 30, a: 255),
                RGBA(r: 10, g: 20, b: 30, a: 255),
                RGBA(r: 10, g: 20, b: 30, a: 255),
            ])
    }

    /// The bilinear resampler interpolated red, green and blue and then built
    /// its pixel with `RGBA(r:g:b:)`, whose alpha defaults to opaque — so every
    /// transparent picture it touched came out solid.
    ///
    /// Nothing noticed while its only consumers read luminance or RGB to pick
    /// a glyph. A renderer that hands the pixels to the TERMINAL notices at
    /// once, because the terminal is what composites them over the page.
    @Test("Enlarging carries alpha")
    func enlargingKeepsAlpha() {
        let scaled = cornerCutout().resampled(to: 4, 4)
        #expect(scaled.pixel(at: 0, 0).a == 0, "the transparent corner is still transparent")
        #expect(scaled.pixel(at: 3, 3).a == 255, "and the opaque one is still opaque")
        #expect(
            scaled.pixels.contains { $0.a > 0 && $0.a < 255 },
            "and the edge between them is interpolated, not stepped")
    }

    /// Both resamplers guarded the TARGET size and never the source. A 0x0
    /// source (which a decode can return as a success, and which `scaled(to:
    /// 0, 0)` produces) then indexed an empty array in `scaled(to:)` and read
    /// `source[-1]` through an unsafe buffer in the bilinear one.
    @Test("An empty source scales to an empty image instead of trapping")
    func emptySourceScales() {
        let sources = [
            RGBAImage(width: 0, height: 0, pixels: []),
            RGBAImage(width: 3, height: 0, pixels: []),
            RGBAImage(width: 0, height: 2, pixels: []),
        ]
        for source in sources {
            #expect(source.scaled(to: 4, 4).pixels.isEmpty, "\(source.width)x\(source.height)")
            #expect(source.resampled(to: 4, 4).pixels.isEmpty, "\(source.width)x\(source.height)")
            #expect(source.reduced(by: 2).pixels.isEmpty, "\(source.width)x\(source.height)")
        }
    }

    /// Straight RGBA cannot be filtered channel-wise: the decoder writes a
    /// transparent pixel as BLACK, and it got full weight, so a soft edge
    /// pulled its opaque neighbour toward black — a dark fringe on every PNG
    /// with a transparent surround, on a terminal that composites pixels.
    @Test("A soft edge keeps its colour: the filter is premultiplied")
    func softEdgeKeepsItsColour() {
        let source = RGBAImage(
            width: 2, height: 1,
            pixels: [RGBA(r: 255, g: 0, b: 0, a: 255), RGBA(r: 0, g: 0, b: 0, a: 0)])
        let out = source.resampled(to: 4, 1)
        let edge = out.pixel(at: 1, 0)
        #expect(edge.r == 255 && edge.g == 0 && edge.b == 0, "\(edge)")
        #expect(edge.a == 128, "\(edge)")
        // A fully transparent sample has no colour to keep and does not trap.
        #expect(out.pixel(at: 3, 0).a == 0)
        // Opaque pictures are byte-identical to the plain filter.
        let opaque = RGBAImage(
            width: 2, height: 1, pixels: [RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 0, b: 255)])
        let mid = opaque.resampled(to: 4, 1).pixel(at: 1, 0)
        #expect(mid.r == 128 && mid.b == 128 && mid.a == 255, "\(mid)")
    }

    /// The nearest-neighbour scaler carries it too, and so does a shrink; the
    /// test is here so a future edit to either fails in the same place.
    @Test("The other scalings carry it too")
    func siblingsKeepAlpha() {
        #expect(cornerCutout().scaled(to: 4, 4).pixel(at: 0, 0).a == 0, "nearest neighbour")
        let reduced = RGBAImage(
            width: 2, height: 2,
            pixels: [RGBA](repeating: RGBA(r: 1, g: 2, b: 3, a: 0), count: 4)
        ).resampled(to: 1, 1)
        #expect(reduced.pixel(at: 0, 0).a == 0, "shrink")
    }

    /// **The box reduction averaged straight colour and alpha independently** (§41).
    ///
    /// The bilinear read premultiplied and said at its own loop exactly why: a
    /// transparent pixel's colour is meaningless, the decoder writes it BLACK, and
    /// giving it full weight pulls its opaque neighbours toward black. The box
    /// reduction had the same hole — benign only because `ASCIIConverter` flattened
    /// over black *before* calling it. Both are one area-average resampler now
    /// (O-36), premultiplied.
    ///
    /// Half a block of white at full coverage and half at none: the answer is WHITE at
    /// half coverage. Averaged independently it is GREY at half coverage, which is a
    /// dark halo around every soft edge.
    @Test("A shrink averages colour by coverage, not beside it")
    func shrinkIsAlphaWeighted() {
        let opaque = RGBA(r: 255, g: 255, b: 255, a: 255)
        let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
        let reduced = RGBAImage(
            width: 2, height: 2, pixels: [opaque, clear, opaque, clear]
        ).resampled(to: 1, 1)
        let pixel = reduced.pixel(at: 0, 0)
        // 127.5, rounded to nearest (the box reduction truncated to 127).
        #expect(pixel.a == 128, "half coverage: \(pixel)")
        #expect(
            (pixel.r, pixel.g, pixel.b) == (255, 255, 255),
            "the white survives its transparent neighbours: \(pixel)")
    }

    /// An opaque block halved each way is the plain average of its four pixels,
    /// rounded to nearest: the weights cancel when every coverage is equal.
    @Test("An opaque shrink by a whole factor is the plain block average")
    func opaqueShrinkIsThePlainAverage() {
        let values: [UInt8] = [10, 20, 33, 44, 200, 201, 202, 203, 7, 8, 9, 250, 1, 2, 3, 4]
        let source = RGBAImage(
            width: 4, height: 4, pixels: values.map { RGBA(r: $0, g: $0 / 2, b: $0 / 3) })
        let reduced = source.resampled(to: 2, 2)
        for y in 0..<2 {
            for x in 0..<2 {
                var sum = (r: 0, g: 0, b: 0)
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let p = source.pixel(at: x * 2 + dx, y * 2 + dy)
                        sum = (sum.r + Int(p.r), sum.g + Int(p.g), sum.b + Int(p.b))
                    }
                }
                // Within half a level of the exact quarter: where a sum lands on
                // a half, a Float's last bit may tip it either way.
                let got = reduced.pixel(at: x, y)
                #expect(abs(Double(got.r) - Double(sum.r) / 4) <= 0.5, "\(x),\(y) red: \(got)")
                #expect(abs(Double(got.g) - Double(sum.g) / 4) <= 0.5, "\(x),\(y) green: \(got)")
                #expect(abs(Double(got.b) - Double(sum.b) / 4) <= 0.5, "\(x),\(y) blue: \(got)")
                #expect(got.a == 255, "\(x),\(y) alpha: \(got)")
            }
        }
    }

    /// Colour is unchanged by the fix — the interpolation that was already
    /// there still is.
    @Test("Colour interpolation is unchanged")
    func colourStillInterpolates() {
        let ramp = RGBAImage(
            width: 2, height: 1,
            pixels: [RGBA(r: 0, g: 0, b: 0), RGBA(r: 255, g: 255, b: 255)])
        let scaled = ramp.resampled(to: 4, 1)
        #expect(scaled.pixel(at: 0, 0).r == 0)
        #expect(scaled.pixel(at: 3, 0).r > 0)
        #expect(scaled.pixels.allSatisfy { $0.a == 255 }, "an opaque image stays opaque")
    }
}

/// An enlargement against a transcription of the bilinear read it was.
///
/// Enlarging kept the bilinear read when shrinking became an area average
/// (O-36): the same mapping, `x × width / targetWidth`, the same clamps at the
/// last pixel, premultiplied. Separable now, horizontally then vertically in
/// Floats, where the read summed four products in Doubles, so a value that
/// lands on a half can round the other way: within one level, not bit-exact.
@Suite("Enlarging reads as the bilinear read did")
struct ResamplingEquivalenceTests {

    /// The bilinear read, transcribed: `pixel(at:)` reads, a helper per
    /// channel, premultiplied. Also what `AdaptivePaletteTests` samples the
    /// Example's demo picture with, to keep testing the picture it was written on.
    static func reference(_ image: RGBAImage, to targetWidth: Int, _ targetHeight: Int)
        -> [RGBA]
    {
        var result = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: targetWidth * targetHeight)
        let xRatio = Double(image.width) / Double(targetWidth)
        let yRatio = Double(image.height) / Double(targetHeight)
        for y in 0..<targetHeight {
            let srcY = Double(y) * yRatio
            let y0 = min(Int(srcY), image.height - 1)
            let y1 = min(y0 + 1, image.height - 1)
            let yFrac = srcY - Double(y0)
            for x in 0..<targetWidth {
                let srcX = Double(x) * xRatio
                let x0 = min(Int(srcX), image.width - 1)
                let x1 = min(x0 + 1, image.width - 1)
                let xFrac = srcX - Double(x0)
                let p00 = image.pixel(at: x0, y0)
                let p10 = image.pixel(at: x1, y0)
                let p01 = image.pixel(at: x0, y1)
                let p11 = image.pixel(at: x1, y1)
                // Premultiplied, in the SAME expression shape as the fast path
                // — this test is "the unsafe-buffer version equals the plain
                // one", and two associations of the same sum can differ in the
                // last bit, which a `.rounded()` on a half turns into a pixel.
                let w00 = (1 - xFrac) * (1 - yFrac)
                let w10 = xFrac * (1 - yFrac)
                let w01 = (1 - xFrac) * yFrac
                let w11 = xFrac * yFrac
                let k00 = w00 * Double(p00.a)
                let k10 = w10 * Double(p10.a)
                let k01 = w01 * Double(p01.a)
                let k11 = w11 * Double(p11.a)
                let alpha = k00 + k10 + k01 + k11
                func channel(_ c00: UInt8, _ c10: UInt8, _ c01: UInt8, _ c11: UInt8) -> Double {
                    alpha > 0
                        ? (Double(c00) * k00 + Double(c10) * k10 + Double(c01) * k01 + Double(c11) * k11) / alpha
                        : 0
                }
                let red = channel(p00.r, p10.r, p01.r, p11.r)
                let green = channel(p00.g, p10.g, p01.g, p11.g)
                let blue = channel(p00.b, p10.b, p01.b, p11.b)
                result[y * targetWidth + x] = RGBA(
                    r: UInt8(clamping: Int(red.rounded())),
                    g: UInt8(clamping: Int(green.rounded())),
                    b: UInt8(clamping: Int(blue.rounded())),
                    a: UInt8(clamping: Int(alpha.rounded())))
            }
        }
        return result
    }

    private func noise(_ width: Int, _ height: Int, seed: UInt64) -> RGBAImage {
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
                    a: UInt8(truncatingIfNeeded: state >> 40)))
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Upscales, non-integer ratios, the same size, and the degenerate shapes
    /// where the clamping at the edges is what decides the answer.
    @Test("Every pixel is within a level of the bilinear read")
    func matchesTheReference() {
        let shapes = [
            (7, 5, 13, 11), (16, 16, 16, 16), (1, 9, 5, 13), (9, 1, 13, 5), (2, 2, 31, 29),
            (1, 1, 4, 4), (23, 17, 23, 17), (5, 7, 6, 50),
        ]
        for (index, shape) in shapes.enumerated() {
            let source = noise(shape.0, shape.1, seed: UInt64(index) &* 7919 &+ 3)
            let fast = source.resampled(to: shape.2, shape.3)
            let slow = Self.reference(source, to: shape.2, shape.3)
            let apart = zip(fast.pixels, slow).map { got, wanted in
                [abs(Int(got.r) - Int(wanted.r)), abs(Int(got.g) - Int(wanted.g)),
                 abs(Int(got.b) - Int(wanted.b)), abs(Int(got.a) - Int(wanted.a))].max() ?? 0
            }
            #expect(apart.allSatisfy { $0 <= 1 }, "\(shape) diverged by up to \(apart.max() ?? 0)")
        }
    }
}
