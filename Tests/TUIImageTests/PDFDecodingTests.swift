//  🖥️ TUI — A Terminal UI framework for Swift
//  PDFDecodingTests.swift
//
//  A PDF decodes on Apple platforms: its first page, rasterised through Core
//  Graphics at one pixel a point (decisions B-D3M-4).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics) && canImport(ImageIO)
    import CoreGraphics
    import Foundation
    import Testing

    @testable import TUIImage

    @Suite("PDF decoding")
    struct PDFDecodingTests {

        /// A one-page PDF `width` × `height` points: its left half red, its
        /// right half clear.
        private static func pdf(width: Int, height: Int) throws -> Data {
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: width, height: height)
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.endPDFPage()
            context.closePDF()
            return data as Data
        }

        @Test("A PDF's first page decodes at its size in points, drawn as it is")
        func decodesTheFirstPage() throws {
            let image = try PlatformImageLoader().loadImage(from: Self.pdf(width: 40, height: 20))
            #expect(image.width == 40 && image.height == 20)
            let left = image.pixels[10 * 40 + 5]
            let right = image.pixels[10 * 40 + 35]
            #expect(left.r == 255 && left.g == 0 && left.b == 0 && left.a == 255, "\(left)")
            #expect(right.a == 0, "the page's clear half: \(right)")
        }

        @Test("A PDF over the pixel limit is refused, as any image is")
        func respectsTheLimit() throws {
            #expect(throws: ImageLoadError.self) {
                try PlatformImageLoader().loadImage(from: Self.pdf(width: 40, height: 20), maxPixelCount: 100)
            }
        }

        @Test("A PDF file is read from its path, and a file that only looks like one by name is not")
        func readsAFile() throws {
            let directory = FileManager.default.temporaryDirectory
            let path = directory.appendingPathComponent("tuikit-pdf-\(UUID().uuidString).pdf").path
            try Self.pdf(width: 8, height: 4).write(to: URL(fileURLWithPath: path))
            defer { try? FileManager.default.removeItem(atPath: path) }
            let image = try PlatformImageLoader().loadImage(from: path)
            #expect(image.width == 8 && image.height == 4)
            #expect(PlatformImageLoader.pdfDocument(data: Data("not a pdf".utf8)) == nil)
        }
    }
#endif
