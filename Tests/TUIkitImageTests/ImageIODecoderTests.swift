//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageIODecoderTests.swift
//
//  The Apple decoder is ImageIO, not NSImage, so that TUIkitImage need not
//  import AppKit — and it turns a picture by its EXIF orientation, as NSImage
//  did, and refuses one declared too large before drawing it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitImage

#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    import CoreGraphics
    import ImageIO
    import UniformTypeIdentifiers

    @Suite("The ImageIO decoder")
    struct ImageIODecoderTests {
        /// A 4 × 2 PNG, red on its left half and blue on its right, stored
        /// with EXIF `orientation`.
        private func picture(orientation: Int) throws -> Data {
            let width = 4
            let height = 2
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for index in 0..<(width * height) {
                let red = index % width < 2
                bytes[index * 4] = red ? 255 : 0
                bytes[index * 4 + 2] = red ? 0 : 255
                bytes[index * 4 + 3] = 255
            }
            let context = try #require(
                CGContext(
                    data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let image = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(
                CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            return data as Data
        }

        @Test("A picture stored upright is decoded as stored")
        func upright() throws {
            let decoded = try PlatformImageLoader().loadImage(from: picture(orientation: 1))
            #expect(decoded.width == 4 && decoded.height == 2)
            #expect(decoded.pixels[0].r == 255 && decoded.pixels[3].b == 255)
        }

        @Test("A picture stored on its side is turned by its EXIF orientation, as NSImage turned it")
        func turned() throws {
            // Orientation 6: the stored pixels are turned 90° clockwise to show.
            let decoded = try PlatformImageLoader().loadImage(from: picture(orientation: 6))
            #expect(decoded.width == 2 && decoded.height == 4, "\(decoded.width) × \(decoded.height)")
            // Turned clockwise, the red left half is the top.
            #expect(decoded.pixels[0].r == 255 && decoded.pixels[decoded.pixels.count - 1].b == 255)
        }

        @Test("A picture declared larger than the limit is refused")
        func tooLarge() throws {
            #expect(throws: ImageLoadError.self) {
                try PlatformImageLoader().loadImage(from: picture(orientation: 1), maxPixelCount: 4)
            }
        }

        // MARK: - Files of several images

        /// A `width` × `height` image of one opaque colour.
        private func solid(width: Int, height: Int, red: UInt8, blue: UInt8) throws -> CGImage {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for index in 0..<(width * height) {
                bytes[index * 4] = red
                bytes[index * 4 + 1] = 0
                bytes[index * 4 + 2] = blue
            }
            let context = try #require(
                CGContext(
                    data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try #require(context.makeImage())
        }

        /// A file of `type` holding `images` in order, each with its EXIF
        /// orientation.
        private func file(_ type: UTType, _ images: [(CGImage, orientation: Int)]) throws -> Data {
            let data = NSMutableData()
            let destination = try #require(
                CGImageDestinationCreateWithData(
                    data as CFMutableData, type.identifier as CFString, images.count, nil))
            for (image, orientation) in images {
                CGImageDestinationAddImage(
                    destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            }
            #expect(CGImageDestinationFinalize(destination))
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            try #require(CGImageSourceGetCount(source) == images.count, "the file holds every image")
            return data as Data
        }

        /// NSImage drew the 64 × 32 image of this file, measured on a Mac whose
        /// display is at 2×; ImageIO's first image is the 16 × 16 one.
        @Test("Of several images, the largest is decoded, wherever it is in the file")
        func largestOfSeveral() throws {
            let small = try solid(width: 16, height: 16, red: 255, blue: 0)
            let large = try solid(width: 64, height: 32, red: 0, blue: 255)
            for order in [[small, large], [large, small]] {
                let data = try file(.tiff, order.map { ($0, orientation: 1) })
                let decoded = try PlatformImageLoader().loadImage(from: data)
                #expect(decoded.width == 64 && decoded.height == 32, "\(decoded.width) × \(decoded.height)")
                #expect(decoded.pixels[0].b == 255 && decoded.pixels[0].r == 0, "the blue, large image")
            }
        }

        @Test("The largest of several images is turned by its own EXIF orientation")
        func largestOfSeveralIsTurned() throws {
            let small = try solid(width: 16, height: 16, red: 255, blue: 0)
            let large = try solid(width: 64, height: 32, red: 0, blue: 255)
            let data = try file(.tiff, [(small, orientation: 1), (large, orientation: 6)])
            let decoded = try PlatformImageLoader().loadImage(from: data)
            #expect(decoded.width == 32 && decoded.height == 64, "\(decoded.width) × \(decoded.height)")
        }

        /// The limit bounds memory; a file whose largest image is over it but
        /// holds a smaller one within it still draws, as decoding the first
        /// image did before the largest was chosen.
        @Test("Under a pixel limit, the largest image within it is decoded, and a file with none within it is refused")
        func largestWithinTheLimit() throws {
            let small = try solid(width: 16, height: 16, red: 255, blue: 0)
            let middle = try solid(width: 32, height: 16, red: 0, blue: 255)
            let large = try solid(width: 64, height: 32, red: 0, blue: 255)
            for order in [[large, small, middle], [small, middle, large]] {
                let data = try file(.tiff, order.map { ($0, orientation: 1) })
                let decoded = try PlatformImageLoader().loadImage(from: data, maxPixelCount: 32 * 16)
                #expect(decoded.width == 32 && decoded.height == 16, "\(decoded.width) × \(decoded.height)")
                let smallest = try PlatformImageLoader().loadImage(from: data, maxPixelCount: 16 * 16)
                #expect(smallest.width == 16 && smallest.height == 16, "exactly at the limit")
                #expect(throws: ImageLoadError.self) {
                    try PlatformImageLoader().loadImage(from: data, maxPixelCount: 16 * 16 - 1)
                }
            }
        }

        @Test("Of several images the same size, the first is decoded, as an animation's first frame")
        func firstOfEqualImages() throws {
            let red = try solid(width: 8, height: 8, red: 255, blue: 0)
            let blue = try solid(width: 8, height: 8, red: 0, blue: 255)
            let decoded = try PlatformImageLoader().loadImage(
                from: file(.gif, [(red, orientation: 1), (blue, orientation: 1)]))
            #expect(decoded.pixels[0].r == 255 && decoded.pixels[0].b == 0, "the first frame, red")
        }
    }
#endif
