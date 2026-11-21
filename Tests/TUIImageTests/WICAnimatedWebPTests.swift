//  🖥️ TUI — A Terminal UI framework for Swift
//  WICAnimatedWebPTests.swift
//
//  Animated WebP on Windows, composited by WIC's WebP codec. The files are
//  written here byte by byte: each frame a solid colour in lossless VP8L
//  whose prefix codes have one symbol each, so a frame needs no pixel bits
//  and no encoder.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage

@Suite("Animated WebP, by WIC")
struct WICAnimatedWebPTests {
    /// The test file's four frames on an 8 × 4 canvas: red over all of it,
    /// then green at half its alpha blended over the middle, then blue
    /// replacing a corner of that and disposed after, then yellow blended at
    /// the left.
    private static let frames: [WebPFixture.Frame] = [
        .init(x: 0, y: 0, width: 8, height: 4, milliseconds: 100, argb: (255, 255, 0, 0)),
        .init(x: 2, y: 0, width: 4, height: 4, milliseconds: 200, argb: (128, 0, 255, 0)),
        .init(x: 4, y: 2, width: 2, height: 2, milliseconds: 300, argb: (255, 0, 0, 255), blends: false, disposes: true),
        .init(x: 0, y: 2, width: 2, height: 2, milliseconds: 400, argb: (255, 255, 255, 0)),
    ]

    @Test("The fixture is an animated WebP by its first bytes")
    func fixtureHead() {
        let data = WebPFixture.animated(width: 8, height: 4, frames: Self.frames, loops: 3)
        #expect(AnimatedImageDecoder.isAnimatedWebP(head: [UInt8](data.prefix(21))))
        #expect(!AnimatedImageDecoder.isAnimatedWebP(head: [UInt8](Data("GIF89a".utf8))))
    }

    #if os(Windows)
        @Test("Each frame is the whole canvas, blended, replaced and disposed as the file says, at its duration")
        func composited() throws {
            let data = WebPFixture.animated(width: 8, height: 4, frames: Self.frames, loops: 3)
            let animation = try #require(AnimatedImageDecoder.decode(data, maxPixelCount: nil))
            #expect(animation.width == 8 && animation.height == 4)
            #expect(animation.frames.map(\.delayNanos) == [100, 200, 300, 400].map { Int64($0) * 1_000_000 })
            #expect(animation.plays == 3)
            func colour(_ frame: Int, _ x: Int, _ y: Int) -> [UInt8] {
                let pixel = animation.frames[frame].image.pixel(at: x, y)
                return [pixel.r, pixel.g, pixel.b, pixel.a]
            }
            let red: [UInt8] = [255, 0, 0, 255]
            #expect(colour(0, 3, 1) == red)
            // Green at half its alpha over red.
            let blended = colour(1, 3, 1)
            #expect(blended[3] == 255 && (120...135).contains(blended[0]) && (120...135).contains(blended[1]))
            #expect(colour(1, 0, 0) == red && colour(1, 7, 3) == red)
            #expect(colour(2, 4, 2) == [0, 0, 255, 255], "blue replaces what is under it")
            // Disposed: the blue's rectangle is the background, transparent.
            #expect(colour(3, 4, 2)[3] == 0)
            #expect(colour(3, 0, 3) == [255, 255, 0, 255])
            #expect(colour(3, 3, 1) == blended, "what was drawn before stays")
        }

        @Test("A file that loops for ever plays for ever, and one past the pixel limit is refused")
        func foreverAndLimit() throws {
            let data = WebPFixture.animated(width: 8, height: 4, frames: Self.frames, loops: 0)
            #expect(try #require(AnimatedImageDecoder.decode(data, maxPixelCount: nil)).plays == nil)
            #expect(AnimatedImageDecoder.decode(data, maxPixelCount: 31) == nil)
            #expect(AnimatedImageDecoder.decode(data, maxPixelCount: 32) != nil)
        }

        @Test("One frame is no animation, and the file still draws as a picture")
        func single() throws {
            let data = WebPFixture.animated(width: 8, height: 4, frames: Array(Self.frames.prefix(1)), loops: 0)
            #expect(AnimatedImageDecoder.decode(data, maxPixelCount: nil) == nil)
            let picture = try PlatformImageLoader().loadImage(from: data, maxPixelCount: nil)
            #expect(picture.width == 8 && picture.height == 4)
            #expect(picture.pixel(at: 1, 1).r == 255)
        }
    #endif
}

/// Writes WebP files of solid-colour frames.
enum WebPFixture {
    struct Frame {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var milliseconds: Int
        var argb: (UInt8, UInt8, UInt8, UInt8)
        var blends = true
        var disposes = false
    }

    /// An animated WebP of `frames` on a canvas of `width` × `height`,
    /// playing `loops` times (0 for ever) on a transparent background.
    static func animated(width: Int, height: Int, frames: [Frame], loops: Int) -> Data {
        let flags: [UInt8] = [0x02 | 0x10, 0, 0, 0]  // animation, alpha
        let header = flags + uint24(width - 1) + uint24(height - 1)
        var body = chunk("VP8X", header) + chunk("ANIM", [0, 0, 0, 0, UInt8(loops & 0xFF), UInt8(loops >> 8)])
        for frame in frames {
            let flags: UInt8 = (frame.blends ? 0 : 0x02) | (frame.disposes ? 0x01 : 0)
            let placement = uint24(frame.x / 2) + uint24(frame.y / 2) + uint24(frame.width - 1)
                + uint24(frame.height - 1) + uint24(frame.milliseconds) + [flags]
            body += chunk("ANMF", placement + chunk("VP8L", losslessSolid(frame.width, frame.height, frame.argb)))
        }
        return Data(Array("RIFF".utf8) + uint32(4 + body.count) + Array("WEBP".utf8) + body)
    }

    /// A VP8L bitstream of one colour: no transform, no colour cache, and a
    /// prefix code of one symbol for each of green, red, blue, alpha and
    /// distance, which takes no bits a pixel.
    private static func losslessSolid(_ width: Int, _ height: Int, _ argb: (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var bits = BitWriter()
        bits.write(0x2F, 8)
        bits.write(width - 1, 14)
        bits.write(height - 1, 14)
        bits.write(argb.0 == 255 ? 0 : 1, 1)
        bits.write(0, 3)  // version
        bits.write(0, 1)  // no transform
        bits.write(0, 1)  // no colour cache
        bits.write(0, 1)  // no meta prefix codes
        for symbol in [Int(argb.2), Int(argb.1), Int(argb.3), Int(argb.0), 0] {
            bits.write(1, 1)  // a simple code
            bits.write(0, 1)  // of one symbol
            if symbol < 2 {
                bits.write(0, 1)
                bits.write(symbol, 1)
            } else {
                bits.write(1, 1)
                bits.write(symbol, 8)
            }
        }
        return bits.bytes()
    }

    /// Bits written least significant first, as VP8L reads them.
    private struct BitWriter {
        private var output: [UInt8] = []
        private var pending = 0
        private var count = 0

        mutating func write(_ value: Int, _ width: Int) {
            for bit in 0..<width {
                pending |= ((value >> bit) & 1) << count
                count += 1
                if count == 8 {
                    output.append(UInt8(pending))
                    (pending, count) = (0, 0)
                }
            }
        }

        func bytes() -> [UInt8] { count > 0 ? output + [UInt8(pending)] : output }
    }

    private static func chunk(_ tag: String, _ data: [UInt8]) -> [UInt8] {
        Array(tag.utf8) + uint32(data.count) + data + (data.count.isMultiple(of: 2) ? [] : [0])
    }

    private static func uint24(_ value: Int) -> [UInt8] { (0..<3).map { UInt8((value >> (8 * $0)) & 0xFF) } }

    private static func uint32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
}
