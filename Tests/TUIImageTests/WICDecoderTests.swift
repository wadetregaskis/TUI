//  🖥️ TUI — A Terminal UI framework for Swift
//  WICDecoderTests.swift
//
//  Decoding on Windows through the Windows Imaging Component: formats
//  stb_image does not read, EXIF orientation, the largest of several images,
//  and stb_image where WIC has no decoder. The pictures are TIFFs written here
//  byte by byte, which every platform's tests can make.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage

@Suite("WIC decoding")
struct WICDecoderTests {
    @Test("EXIF orientations map to WIC's turn and flip, flip first, as measured")
    func orientationTransforms() {
        let transform = PlatformImageLoader.wicTransform(forOrientation:)
        #expect(transform(1) == (0, false))
        #expect(transform(2) == (0, true))
        #expect(transform(3) == (2, false))
        #expect(transform(4) == (2, true))
        // The diagonal mirrors take each other's turn, as WIC flips first.
        #expect(transform(5) == (3, true))
        #expect(transform(6) == (1, false))
        #expect(transform(7) == (1, true))
        #expect(transform(8) == (3, false))
        #expect(transform(0) == (0, false))
        #expect(transform(9) == (0, false))
    }

    @Test("The largest image within the limit is chosen, the first on a tie")
    func largestIndex() {
        let choose = PlatformImageLoader.largestIndex(of:fitting:)
        #expect(choose([(1, 1), (3, 2), (2, 2)], nil) == 1)
        #expect(choose([(2, 2), (4, 1)], nil) == 0)
        #expect(choose([(1, 1), (3, 2)], 4) == 0)
        // None fits: the largest, for the caller to refuse.
        #expect(choose([(3, 3), (4, 4)], 2) == 1)
        #expect(choose([], nil) == nil)
    }

    /// A little-endian, uncompressed RGB TIFF of `pages`, each with its EXIF
    /// orientation.
    typealias Page = (width: Int, height: Int, pixels: [(UInt8, UInt8, UInt8)], orientation: Int)

    static func tiff(_ pages: [Page]) -> Data {
        var bytes: [UInt8] = Array("II".utf8) + [0x2A, 0x00, 0, 0, 0, 0]
        func put32(_ value: Int, at offset: Int) {
            for index in 0..<4 { bytes[offset + index] = UInt8((value >> (8 * index)) & 0xFF) }
        }
        var linkAt = 4
        for page in pages {
            let pixelsAt = bytes.count
            bytes += page.pixels.flatMap { [$0.0, $0.1, $0.2] }
            let bitsAt = bytes.count
            bytes += [8, 0, 8, 0, 8, 0]
            if bytes.count % 2 == 1 { bytes.append(0) }
            let ifdAt = bytes.count
            put32(ifdAt, at: linkAt)
            let entries: [(tag: Int, type: Int, count: Int, value: Int)] = [
                (256, 4, 1, page.width), (257, 4, 1, page.height), (258, 3, 3, bitsAt), (259, 3, 1, 1),
                (262, 3, 1, 2), (273, 4, 1, pixelsAt), (274, 3, 1, page.orientation), (277, 3, 1, 3),
                (278, 4, 1, page.height), (279, 4, 1, page.pixels.count * 3),
            ]
            bytes += [UInt8(entries.count), 0]
            for entry in entries {
                let at = bytes.count
                bytes += [UInt8](repeating: 0, count: 12)
                bytes[at] = UInt8(entry.tag & 0xFF)
                bytes[at + 1] = UInt8(entry.tag >> 8)
                bytes[at + 2] = UInt8(entry.type)
                put32(entry.count, at: at + 4)
                put32(entry.value, at: at + 8)
            }
            linkAt = bytes.count
            bytes += [0, 0, 0, 0]
        }
        return Data(bytes)
    }

    #if os(Windows)
        private static let red: (UInt8, UInt8, UInt8) = (255, 0, 0)
        private static let blue: (UInt8, UInt8, UInt8) = (0, 0, 255)

        private func file(_ data: Data, _ name: String) throws -> String {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tui-wic-\(UUID().uuidString)-\(name)")
            try data.write(to: url)
            return url.path
        }

        @Test("A TIFF, which stb_image does not read, decodes")
        func tiffDecodes() throws {
            let path = try file(Self.tiff([(2, 1, [Self.red, Self.blue], 1)]), "plain.tif")
            defer { try? FileManager.default.removeItem(atPath: path) }
            let image = try PlatformImageLoader().loadImage(from: path)
            #expect(image.width == 2 && image.height == 1)
            #expect(image.pixels == [RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 0, b: 255)])
        }

        @Test("A picture stored on its side is turned by its EXIF orientation, as ImageIO's are")
        func turned() throws {
            // Orientation 6: turned 90° clockwise to show, so the stored row
            // becomes the column, its left end at the top.
            let data = Self.tiff([(2, 1, [Self.red, Self.blue], 6)])
            let path = try file(data, "turned.tif")
            defer { try? FileManager.default.removeItem(atPath: path) }
            let loader = PlatformImageLoader()
            let image = try loader.loadImage(from: path)
            #expect(image.width == 1 && image.height == 2)
            #expect(image.pixels == [RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 0, b: 255)])
            let size = try loader.pictureSize(atPath: path, maxPixelCount: nil)
            #expect(size.width == 1 && size.height == 2)
            // From the bytes too.
            #expect(try loader.loadImage(from: data).height == 2)
        }

        @Test("Of several images, the largest that fits is decoded")
        func largestOfSeveral() throws {
            let small: Page = (1, 1, [Self.blue], 1)
            let large: Page = (3, 2, [(UInt8, UInt8, UInt8)](repeating: Self.red, count: 6), 1)
            let path = try file(Self.tiff([small, large]), "pages.tif")
            defer { try? FileManager.default.removeItem(atPath: path) }
            let loader = PlatformImageLoader()
            #expect(try loader.loadImage(from: path).width == 3)
            #expect(try loader.loadImage(from: path, maxPixelCount: 4).width == 1)
            #expect(throws: ImageLoadError.self) { try loader.loadImage(from: path, maxPixelCount: 0) }
        }

        @Test("Where WIC has no decoder, stb_image reads the picture")
        func stbWhereWICHasNone() throws {
            // A binary PNM, which stb_image reads and WIC does not.
            let data = Data(Array("P6\n2 1\n255\n".utf8) + [255, 0, 0, 0, 0, 255])
            let path = try file(data, "picture.ppm")
            defer { try? FileManager.default.removeItem(atPath: path) }
            let image = try PlatformImageLoader().loadImage(from: path)
            #expect(image.width == 2 && image.pixels.first == RGBA(r: 255, g: 0, b: 0))
            #expect(try PlatformImageLoader().loadImage(from: data).width == 2)
        }

        @Test("A picture reduced is decoded whole and averaged down, its size whole kept")
        func reduced() throws {
            let large: Page = (4, 2, [(UInt8, UInt8, UInt8)](repeating: Self.red, count: 8), 1)
            let path = try file(Self.tiff([large]), "reduced.tif")
            defer { try? FileManager.default.removeItem(atPath: path) }
            let loaded = try PlatformImageLoader().loadImage(from: path, maxPixelCount: nil, reducedBy: 2)
            #expect(loaded.width == 4 && loaded.height == 2)
            #expect(loaded.image.width == 2 && loaded.image.height == 1)
        }
    #endif
}
