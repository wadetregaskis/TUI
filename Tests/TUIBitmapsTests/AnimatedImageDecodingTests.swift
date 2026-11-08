//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatedImageDecodingTests.swift
//
//  An animated file's frames, its timing, and what it is allowed to hold.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage

#if canImport(ImageIO)
    import ImageIO
    import UniformTypeIdentifiers
#endif

@Suite("An animated file's frames")
struct AnimatedImageDecodingTests {
    private static let budget = AnimatedImageDecoder.byteBudget
    private static let limit = AnimatedImageDecoder.frameLimit

    private func grey(_ image: RGBAImage, _ x: Int, _ y: Int) -> UInt8 { image.pixel(at: x, y).r }

    // MARK: - What a GIF states

    @Test("A GIF plays once with no looping extension, and its repeats and one more with one, 0 being forever")
    func plays() throws {
        let frames = [GIFFixture.Frame(grey: 0), GIFFixture.Frame(grey: 100)]
        #expect(GIFStructure(GIFFixture(frames: frames).data)?.plays == 1)
        #expect(GIFStructure(GIFFixture(frames: frames, repeats: 0).data)?.plays == nil)
        #expect(GIFStructure(GIFFixture(frames: frames, repeats: 2).data)?.plays == 3)
        #expect(GIFStructure(GIFFixture(frames: frames).data)?.frameCount == 2)
    }

    @Test("A file cut short is read as far as it goes, and what is not a GIF is not one")
    func truncated() throws {
        let whole = GIFFixture(frames: [.init(grey: 0), .init(grey: 100)]).data
        for cut in stride(from: 0, to: whole.count, by: 7) {
            _ = GIFStructure(whole.prefix(cut))
        }
        #expect(GIFStructure(whole.prefix(whole.count - 2))?.frameCount == 2)
        #expect(GIFStructure(Data("not a picture at all".utf8)) == nil)
        #expect(AnimatedImageDecoder.decodeGIF(
            whole.prefix(40), maxPixelCount: nil, byteBudget: Self.budget, frameLimit: Self.limit) == nil)
    }

    // MARK: - Both decoders

    /// The frames of a file that composites: a rectangle left, one taken back,
    /// and one painted after it.
    private var compositing: GIFFixture {
        GIFFixture(
            frames: [
                .init(grey: 100, delay: 5),
                .init(grey: 20, rect: (0, 0, 4, 4), delay: 20, disposal: 3),
                .init(grey: 60, rect: (4, 4, 4, 4), delay: 30, disposal: 1),
                .init(grey: 40, rect: (0, 4, 2, 2), delay: 40, disposal: 2),
                .init(grey: 80, rect: (6, 0, 2, 2), delay: 1),
            ], repeats: 1)
    }

    private func checkCompositing(_ animation: AnimatedImage?) throws {
        let animation = try #require(animation)
        #expect(animation.frames.count == 5)
        #expect((animation.width, animation.height) == (8, 8))
        #expect(animation.plays == 2)
        // In hundredths of a second as stated, and a delay of 10 ms is 100 ms.
        #expect(animation.frames.map { $0.delayNanos / 1_000_000 } == [50, 200, 300, 400, 100])
        let images = animation.frames.map(\.image)
        let (back, first) = (GIFFixture.level(100), GIFFixture.level(20))
        #expect(grey(images[0], 0, 0) == back)
        #expect(grey(images[1], 0, 0) == first && grey(images[1], 7, 7) == back)
        // "Restore to previous" took the first rectangle back.
        #expect(grey(images[2], 0, 0) == back && grey(images[2], 7, 7) == GIFFixture.level(60))
        #expect(grey(images[3], 0, 4) == GIFFixture.level(40) && grey(images[3], 7, 7) == GIFFixture.level(60))
        // "Clear" took that one away, to the file's background colour.
        #expect(grey(images[4], 0, 4) == GIFFixture.level(0))
        #expect(grey(images[4], 6, 0) == GIFFixture.level(80) && grey(images[4], 7, 7) == GIFFixture.level(60))
    }

    @Test("stb_image's decoder composites a GIF's frames, one at a time")
    func stbCompositing() throws {
        try checkCompositing(
            AnimatedImageDecoder.decodeGIF(
                compositing.data, maxPixelCount: nil, byteBudget: Self.budget, frameLimit: Self.limit))
    }

    #if canImport(ImageIO)
        @Test("ImageIO's frames of a GIF are the same ones")
        func imageIOCompositing() throws {
            try checkCompositing(AnimatedImageDecoder.decode(compositing.data, maxPixelCount: nil))
        }

        /// An APNG, by the only writer of one to hand.
        private func writeAPNG(frames: [UInt8], delay: Double, plays: Int) throws -> Data {
            let out = NSMutableData()
            let destination = try #require(
                CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, frames.count, nil))
            CGImageDestinationSetProperties(
                destination,
                [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: plays]] as CFDictionary)
            for level in frames {
                let pixels = [UInt8](repeating: level, count: 4 * 4)
                let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
                let image = try unsafe #require(
                    CGImage(
                        width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                CGImageDestinationAddImage(
                    destination, image,
                    [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]] as CFDictionary)
            }
            #expect(CGImageDestinationFinalize(destination))
            return out as Data
        }

        @Test("ImageIO plays an APNG, its loop count counting plays")
        func apng() throws {
            let data = try writeAPNG(frames: [10, 200, 90], delay: 0.2, plays: 3)
            #expect(AnimatedImageDecoder.mayAnimate(head: [UInt8](data.prefix(4_096))))
            let animation = try #require(AnimatedImageDecoder.decode(data, maxPixelCount: nil))
            #expect(animation.frames.count == 3)
            #expect(animation.plays == 3)
            #expect(animation.frames.map { $0.delayNanos / 1_000_000 } == [200, 200, 200])
            #expect(grey(animation.frames[1].image, 0, 0) > grey(animation.frames[0].image, 0, 0))
        }

        @Test("A PNG of one picture is not one")
        func stillPNG() throws {
            let data = try writeAPNG(frames: [10], delay: 0, plays: 0)
            #expect(AnimatedImageDecoder.decode(data, maxPixelCount: nil) == nil)
        }
    #endif

    @Test("A GIF of one picture is not one, and neither is one over the pixel limit")
    func notAnimated() throws {
        let single = GIFFixture(frames: [.init(grey: 0)]).data
        #expect(AnimatedImageDecoder.decode(single, maxPixelCount: nil) == nil)
        let two = GIFFixture(frames: [.init(grey: 0), .init(grey: 100)]).data
        #expect(AnimatedImageDecoder.decode(two, maxPixelCount: 63) == nil)
        #expect(AnimatedImageDecoder.decode(two, maxPixelCount: 64) != nil)
    }

    // MARK: - Telling from a file's first bytes

    @Test("A file's first bytes say whether it is worth reading for frames")
    func head() {
        #expect(AnimatedImageDecoder.mayAnimate(head: Array("GIF89a".utf8)))
        #expect(!AnimatedImageDecoder.mayAnimate(head: [0xFF, 0xD8, 0xFF, 0xE0]))
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ name: String, length: UInt8 = 0) -> [UInt8] {
            [0, 0, 0, length] + Array(name.utf8) + [UInt8](repeating: 0, count: Int(length) + 4)
        }
        func webP(flags: UInt8) -> [UInt8] {
            Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBPVP8X".utf8) + [10, 0, 0, 0, flags, 0, 0, 0]
        }
        // By ImageIO's being here, the only decoder of either.
        #if canImport(ImageIO)
            let hasAPNGAndWebP = true
        #else
            let hasAPNGAndWebP = false
        #endif
        let apng = signature + chunk("IHDR", length: 13) + chunk("acTL", length: 8) + chunk("IDAT", length: 2)
        #expect(AnimatedImageDecoder.mayAnimate(head: apng) == hasAPNGAndWebP)
        #expect(!AnimatedImageDecoder.mayAnimate(head: signature + chunk("IHDR", length: 13) + chunk("IDAT", length: 2)))
        #expect(AnimatedImageDecoder.mayAnimate(head: webP(flags: 0x02)) == hasAPNGAndWebP)
        #expect(!AnimatedImageDecoder.mayAnimate(head: webP(flags: 0x10)))
    }

    // MARK: - The bound

    @Test("A file within the budget is kept whole")
    func plannedWhole() {
        let plan = FramePlan(canvasWidth: 480, canvasHeight: 270, frameCount: 100, byteBudget: Self.budget, frameLimit: Self.limit)
        #expect(plan == FramePlan(canvasWidth: 480, canvasHeight: 270, frameCount: 1, byteBudget: Self.budget, frameLimit: Self.limit))
        #expect(plan.stride == 1 && plan.frameWidth == 480 && plan.frameHeight == 270)
    }

    @Test(
        "However large or long the file, what is kept is within the budget",
        arguments: [
            (1_000, 1_000, 100), (65_535, 65_535, 1_000), (65_535, 1, 2), (1, 65_535, 2), (4_096, 2_160, 100_000),
            (320, 240, 5_000),
        ])
    func plannedWithin(width: Int, height: Int, frames: Int) {
        let plan = FramePlan(canvasWidth: width, canvasHeight: height, frameCount: frames, byteBudget: Self.budget, frameLimit: Self.limit)
        let kept = (frames + plan.stride - 1) / plan.stride
        #expect(kept <= Self.limit)
        #expect(plan.frameWidth * plan.frameHeight * 4 * kept <= Self.budget)
        #expect(plan.frameWidth >= 1 && plan.frameHeight >= 1)
        #expect(plan.frameWidth <= width && plan.frameHeight <= height)
    }

    @Test("A file past the budget keeps every frame, scaled down, its size still the file's")
    func scaledDown() throws {
        let fixture = GIFFixture(width: 64, height: 32, frames: (0..<4).map { .init(grey: UInt8($0 * 20)) })
        let budget = 4 * 16 * 8 * 4
        for animation in [
            AnimatedImageDecoder.decodeGIF(fixture.data, maxPixelCount: nil, byteBudget: budget, frameLimit: Self.limit),
            AnimatedImageDecoder.decode(fixture.data, maxPixelCount: nil, byteBudget: budget),
        ] {
            let animation = try #require(animation)
            #expect(animation.frames.count == 4)
            #expect((animation.width, animation.height) == (64, 32))
            let held = animation.frames.reduce(0) { $0 + $1.image.pixels.count * 4 }
            #expect(held <= budget)
            #expect(animation.frames[0].image.width == 16)
        }
    }

    @Test("Past the frame limit every nth frame stands for the ones it skips, for as long")
    func strided() throws {
        let fixture = GIFFixture(frames: (0..<10).map { .init(grey: UInt8($0 * 10), delay: 2 + $0) }, repeats: 0)
        for animation in [
            AnimatedImageDecoder.decodeGIF(fixture.data, maxPixelCount: nil, byteBudget: Self.budget, frameLimit: 4),
            AnimatedImageDecoder.decode(fixture.data, maxPixelCount: nil, frameLimit: 4),
        ] {
            let animation = try #require(animation)
            #expect(animation.frames.count == 4)
            #expect(animation.frames.map { grey($0.image, 0, 0) } == [0, 3, 6, 9].map { GIFFixture.level(UInt8($0 * 10)) })
            #expect(animation.frames.map { $0.delayNanos / 1_000_000 } == [90, 180, 270, 110])
        }
    }

    // MARK: - Timing

    private func timed(_ milliseconds: [Int], plays: Int?) -> AnimatedImage {
        AnimatedImage(
            width: 1, height: 1,
            frames: milliseconds.map {
                AnimatedImage.Frame(image: RGBAImage(width: 0, height: 0, pixels: []), delayNanos: Int64($0) * 1_000_000)
            }, plays: plays)
    }

    private func milli(_ value: Int64) -> Int64 { value * 1_000_000 }

    /// Whether `animation` shows frame `index` at `milliseconds`, with the next
    /// due at `next` milliseconds.
    private func shows(_ animation: AnimatedImage, _ index: Int, at milliseconds: Int64, next: Int64) -> Bool {
        let position = animation.position(atElapsed: milli(milliseconds))
        return position.index == index && position.nextChange == milli(next)
    }

    @Test("The frame showing follows the time, and says when the next is due")
    func position() {
        let animation = timed([100, 200, 100], plays: nil)
        #expect(shows(animation, 0, at: 0, next: 100))
        #expect(animation.position(atElapsed: milli(100) - 1).index == 0)
        #expect(shows(animation, 1, at: 100, next: 300))
        #expect(shows(animation, 2, at: 399, next: 400))
        #expect(shows(animation, 0, at: 400, next: 500))
        // Forever is forever, and a late frame skips what it missed.
        #expect(shows(animation, 1, at: 4_000_150, next: 4_000_300))
    }

    @Test("A count of plays ends on the last frame, with nothing more due")
    func ends() {
        let animation = timed([100, 100], plays: 2)
        #expect(shows(animation, 0, at: 250, next: 300))
        #expect(shows(animation, 1, at: 399, next: 400))
        #expect(animation.position(atElapsed: milli(400)).index == 1)
        #expect(animation.position(atElapsed: milli(400)).nextChange == nil)
        #expect(animation.position(atElapsed: milli(90_000)).nextChange == nil)
    }

    @Test("A delay of 10 ms or less shows for 100 ms, as in a browser")
    func delays() {
        #expect(AnimatedImage.delayNanos(milliseconds: 0) == milli(100))
        #expect(AnimatedImage.delayNanos(milliseconds: 10) == milli(100))
        #expect(AnimatedImage.delayNanos(milliseconds: 20) == milli(20))
        #expect(AnimatedImage.delayNanos(milliseconds: 655_350) == milli(655_350))
    }
}
