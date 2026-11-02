//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatedImageDecoder.swift
//
//  Which files animate, and their frames: GIF everywhere, by ImageIO or
//  stb_image's decoder; APNG and animated WebP where ImageIO reads them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#endif

/// Decodes an animated file into an ``AnimatedImage``.
///
/// A format no decoder here can play stays what it was: the still picture
/// ``PlatformImageLoader`` loads. Without ImageIO that is every format but GIF:
/// stb_image reads an APNG's default image and no WebP at all, and a decoder for
/// either would be a new dependency.
package enum AnimatedImageDecoder {
    /// The most bytes of pixels one animated picture keeps (``FramePlan``).
    package static let byteBudget = 64 << 20

    /// The most frames one animated picture keeps (``FramePlan``).
    package static let frameLimit = 1_024

    /// The largest file read to decode its frames: all of it is in memory while
    /// that runs. A larger one stays a still picture.
    package static let fileByteLimit = 256 << 20

    /// How far into a file ``mayAnimate(atPath:)`` looks.
    private static let headLength = 4_096

    /// Whether the file at `path` might hold frames a decoder here can play,
    /// from one short read. For a file already loaded as a picture, so a
    /// regular file: reading a pipe would wait for a writer.
    package static func mayAnimate(atPath path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headLength) else { return false }
        return mayAnimate(head: [UInt8](head))
    }

    /// ``mayAnimate(atPath:)`` of a file beginning `head`.
    ///
    /// An APNG says so in a chunk ahead of its image data, and an animated WebP
    /// in its first header's flags; a GIF has to be read to find out, as many
    /// are single pictures.
    static func mayAnimate(head: [UInt8]) -> Bool {
        if head.starts(with: Array("GIF8".utf8)) { return true }
        #if canImport(ImageIO)
            if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return pngMayAnimate(head) }
            if head.starts(with: Array("RIFF".utf8)), head.count > 20, Array(head[8..<16]) == Array("WEBPVP8X".utf8) {
                return head[20] & 0x02 != 0
            }
        #endif
        return false
    }

    /// Whether a PNG beginning `head` has an `acTL` chunk, which an APNG states
    /// before its first `IDAT`, or might have one past where `head` ends.
    private static func pngMayAnimate(_ head: [UInt8]) -> Bool {
        var at = 8
        while at + 8 <= head.count {
            let type = head[(at + 4)..<(at + 8)]
            if type.elementsEqual("acTL".utf8) { return true }
            if type.elementsEqual("IDAT".utf8) { return false }
            let length = head[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) }
            at += 12 + length
        }
        return true
    }

    /// The frames of the file at `path`, or `nil` if it holds fewer than two, no
    /// decoder here reads it, it is larger than ``fileByteLimit``, or the
    /// calling task was cancelled.
    package static func decode(atPath path: String, maxPixelCount: Int?) -> AnimatedImage? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
            size <= fileByteLimit, let data = try? PlatformImageLoader.fileBytes(atPath: path)
        else { return nil }
        return decode(data, maxPixelCount: maxPixelCount)
    }

    /// The frames of the file `data` holds: ``decode(atPath:maxPixelCount:)``,
    /// keeping at most `byteBudget` of pixels.
    package static func decode(
        _ data: Data, maxPixelCount: Int?, byteBudget: Int = byteBudget, frameLimit: Int = frameLimit
    ) -> AnimatedImage? {
        #if canImport(ImageIO)
            decodeWithImageIO(data, maxPixelCount: maxPixelCount, byteBudget: byteBudget, frameLimit: frameLimit)
        #else
            decodeGIF(data, maxPixelCount: maxPixelCount, byteBudget: byteBudget, frameLimit: frameLimit)
        #endif
    }

    /// Whether a picture of `width` × `height` is one to decode at all.
    static func fits(width: Int, height: Int, maxPixelCount: Int?) -> Bool {
        guard width > 0, height > 0 else { return false }
        let (pixels, overflowed) = width.multipliedReportingOverflow(by: height)
        return !overflowed && (maxPixelCount.map { pixels <= $0 } ?? true)
    }
}

// MARK: - ImageIO

#if canImport(ImageIO)
    extension AnimatedImageDecoder {
        /// Where ImageIO says an animated format's timing, for the formats that
        /// have some. By this and not by the image count alone: a file of several
        /// images need not be an animation (an icon's sizes, a HEIF's burst).
        private struct Format {
            let dictionary: CFString
            let unclampedDelay: CFString
            let delay: CFString
            /// The key of its loop count, which counts plays, 0 for forever. `nil`
            /// for GIF, whose count ``GIFStructure`` reads, the same on every
            /// platform.
            let loopCount: CFString?

            init?(typeIdentifier: String) {
                switch typeIdentifier {
                case "com.compuserve.gif":
                    self.init(
                        kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime,
                        kCGImagePropertyGIFDelayTime, nil)
                case "public.png":
                    self.init(
                        kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime,
                        kCGImagePropertyAPNGDelayTime, kCGImagePropertyAPNGLoopCount)
                case "org.webmproject.webp":
                    self.init(
                        kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime,
                        kCGImagePropertyWebPDelayTime, kCGImagePropertyWebPLoopCount)
                default:
                    return nil
                }
            }

            private init(_ dictionary: CFString, _ unclampedDelay: CFString, _ delay: CFString, _ loopCount: CFString?) {
                self.dictionary = dictionary
                self.unclampedDelay = unclampedDelay
                self.delay = delay
                self.loopCount = loopCount
            }

            /// How long a frame with `properties` shows, in milliseconds.
            func milliseconds(in properties: [CFString: Any]?) -> Int {
                let timing = properties?[dictionary] as? [CFString: Any]
                let seconds = (timing?[unclampedDelay] ?? timing?[delay]) as? Double ?? 0
                return Int((seconds * 1_000).rounded())
            }

            /// How many times a file with `properties` plays, or `nil` for forever.
            func plays(in properties: [CFString: Any]?, of data: Data) -> Int? {
                guard let loopCount else { return GIFStructure(data)?.plays }
                let stated = (properties?[dictionary] as? [CFString: Any])?[loopCount] as? Int ?? 0
                return stated > 0 ? stated : nil
            }
        }

        private static func decodeWithImageIO(
            _ data: Data, maxPixelCount: Int?, byteBudget: Int, frameLimit: Int
        ) -> AnimatedImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                let type = CGImageSourceGetType(source), let format = Format(typeIdentifier: type as String)
            else { return nil }
            let count = CGImageSourceGetCount(source)
            func properties(_ index: Int) -> [CFString: Any]? {
                CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            }
            guard count > 1, let first = properties(0),
                let width = first[kCGImagePropertyPixelWidth] as? Int,
                let height = first[kCGImagePropertyPixelHeight] as? Int,
                fits(width: width, height: height, maxPixelCount: maxPixelCount)
            else { return nil }
            var builder = AnimatedImageBuilder(
                plan: FramePlan(
                    canvasWidth: width, canvasHeight: height, frameCount: count, byteBudget: byteBudget,
                    frameLimit: frameLimit))
            let loader = PlatformImageLoader()
            for index in 0..<count {
                guard !Task.isCancelled else { return nil }
                let milliseconds = format.milliseconds(in: properties(index))
                builder.add(delayNanos: AnimatedImage.delayNanos(milliseconds: milliseconds)) {
                    CGImageSourceCreateImageAtIndex(source, index, nil).flatMap { try? loader.decode($0, maxPixelCount: nil) }
                }
            }
            guard builder.frames.count > 1 else { return nil }
            let plays = format.plays(in: CGImageSourceCopyProperties(source, nil) as? [CFString: Any], of: data)
            return AnimatedImage(width: width, height: height, frames: builder.frames, plays: plays)
        }
    }
#endif
