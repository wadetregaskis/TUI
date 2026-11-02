//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatedImageDecoder+GIF.swift
//
//  A GIF's structure, read without decoding it, and its frames by stb_image's
//  decoder. What every platform without ImageIO plays; compiled on all of them,
//  as a helper compiled only there could only be tested there.
//
//  Created by Wade Tregaskis
//  License: MIT

import CSTBImage
import Foundation

/// What a GIF's blocks say, read by walking them, with no pixels decoded: what
/// stb_image does not report, and what has to be known ahead of the frames to
/// plan how much of them to keep.
struct GIFStructure: Equatable {
    let width: Int
    let height: Int
    /// How many images it holds.
    let frameCount: Int
    /// How many times it plays, or `nil` for forever.
    ///
    /// A GIF with no looping extension plays once. One with it states how many
    /// times it REPEATS, so one more than that, and 0 is forever: what browsers
    /// do, and what ffmpeg and ImageMagick write for it.
    let plays: Int?

    /// The structure of the GIF `data` holds, up to where it is cut off if it
    /// is, or `nil` if it is not one.
    init?(_ data: Data) {
        let parsed = data.withUnsafeBytes { Self.walk($0) }
        guard let parsed else { return nil }
        width = parsed.width
        height = parsed.height
        frameCount = parsed.frames
        plays = parsed.repeats.map { $0 == 0 ? nil : $0 + 1 } ?? 1
    }

    private static func walk(_ bytes: UnsafeRawBufferPointer) -> (width: Int, height: Int, frames: Int, repeats: Int?)? {
        guard bytes.count >= 13, bytes.starts(with: "GIF8".utf8) else { return nil }
        func colourTableLength(flags: UInt8) -> Int { flags & 0x80 == 0 ? 0 : 3 << (Int(flags & 0x07) + 1) }
        func littleEndian(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        /// The index past the sub-blocks starting at `start`.
        func pastSubBlocks(_ start: Int) -> Int {
            var at = start
            while at < bytes.count, bytes[at] != 0 { at += Int(bytes[at]) + 1 }
            return at + 1
        }
        var at = 13 + colourTableLength(flags: bytes[10])
        var frames = 0
        var repeats: Int?
        walking: while at < bytes.count {
            switch bytes[at] {
            case 0x2C:  // An image: a descriptor, a colour table, its code size, its data.
                guard at + 10 < bytes.count else { break walking }
                frames += 1
                at = pastSubBlocks(at + 10 + colourTableLength(flags: bytes[at + 9]) + 1)
            case 0x21:  // An extension: its label, then sub-blocks.
                guard at + 2 < bytes.count else { break walking }
                if bytes[at + 1] == 0xFF, at + 18 < bytes.count, bytes[at + 2] == 11,
                    isLoopingApplication(bytes[(at + 3)..<(at + 14)]), bytes[at + 14] == 3, bytes[at + 15] == 1
                {
                    repeats = littleEndian(at + 16)
                }
                at = pastSubBlocks(at + 2)
            default:  // The trailer, or something else that ends what can be read.
                break walking
            }
        }
        return (littleEndian(6), littleEndian(8), frames, repeats)
    }

    private static func isLoopingApplication(_ name: Slice<UnsafeRawBufferPointer>) -> Bool {
        name.elementsEqual("NETSCAPE2.0".utf8) || name.elementsEqual("ANIMEXTS1.0".utf8)
    }
}

extension AnimatedImageDecoder {
    /// The frames of the GIF `data` holds, composited by stb_image, one held at
    /// a time past what is kept (`stb_gif_reader.h`), or `nil` if it holds fewer
    /// than two, or the calling task was cancelled.
    static func decodeGIF(
        _ data: Data, maxPixelCount: Int?, byteBudget: Int, frameLimit: Int
    ) -> AnimatedImage? {
        guard let structure = GIFStructure(data), structure.frameCount > 1,
            fits(width: structure.width, height: structure.height, maxPixelCount: maxPixelCount),
            let length = try? PlatformImageLoader.stbLength(forByteCount: data.count)
        else { return nil }
        let plan = FramePlan(
            canvasWidth: structure.width, canvasHeight: structure.height, frameCount: structure.frameCount,
            byteBudget: byteBudget, frameLimit: frameLimit)
        let frames: [AnimatedImage.Frame]? = data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress,
                let reader = stb_gif_reader_open(base, length)
            else { return nil }
            defer { stb_gif_reader_close(reader) }
            var builder = AnimatedImageBuilder(plan: plan)
            var delay: Int32 = 0
            var width: Int32 = 0
            var height: Int32 = 0
            while let pixels = stb_gif_reader_next(reader, &delay, &width, &height) {
                guard !Task.isCancelled else { return nil }
                builder.add(delayNanos: AnimatedImage.delayNanos(milliseconds: Int(delay))) {
                    RGBAImage(rgbaBytes: pixels, width: Int(width), height: Int(height))
                }
            }
            return builder.frames
        }
        guard let frames, frames.count > 1 else { return nil }
        return AnimatedImage(width: structure.width, height: structure.height, frames: frames, plays: structure.plays)
    }
}
