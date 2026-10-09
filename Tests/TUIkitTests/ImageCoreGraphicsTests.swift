//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageCoreGraphicsTests.swift
//
//  `Image.Orientation`, and images made from a `CGImage` or an `NSImage`:
//  their pixels, their orientations, and a picture changed under one view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUIkitBitmaps
import TUIkitImage

#if canImport(AppKit)
    import AppKit
    import TUIkitAppKit
#endif

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Images made from pixels the app has")
struct ImageCoreGraphicsTests {

    /// A 2 × 3 image whose pixels are numbered 0…5, row-major, in their red.
    private func numbered() -> RGBAImage {
        RGBAImage(width: 2, height: 3, pixels: (0..<6).map { RGBA(r: UInt8($0), g: 0, b: 0) })
    }

    /// `image`'s pixel numbers, a row at a time.
    private func grid(_ image: RGBAImage) -> String {
        (0..<image.height).map { row in
            (0..<image.width).map { String(image.pixels[row * image.width + $0].r) }.joined()
        }.joined(separator: " ")
    }

    @Test("The orientations' raw values and order are SwiftUI's")
    func rawValues() {
        // Measured on macOS 15: `Image.Orientation.allCases.map(\.rawValue)`.
        #expect(Image.Orientation.allCases.map(\.rawValue) == [0, 2, 6, 4, 1, 3, 7, 5])
        #expect(Image.Orientation(rawValue: 7) == .right)
        #expect(Image.Orientation(rawValue: 8) == nil)
    }

    @Test(
        "Each orientation turns the pixels as SwiftUI draws them",
        arguments: [
            // Measured on macOS 15: a numbered 2 × 3 CGImage drawn by SwiftUI.
            (Image.Orientation.up, "01 23 45"),
            (.upMirrored, "10 32 54"),
            (.down, "54 32 10"),
            (.downMirrored, "45 23 01"),
            (.left, "135 024"),
            (.leftMirrored, "024 135"),
            (.right, "420 531"),
            (.rightMirrored, "531 420"),
        ])
    func orientations(orientation: Image.Orientation, expected: String) {
        #expect(grid(numbered().oriented(orientation)) == expected)
    }

    #if canImport(AppKit)
        /// A `width` × `height` CGImage of one opaque colour.
        private func solid(_ colour: RGBA, width: Int = 4, height: Int = 4) -> CGImage {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for index in 0..<(width * height) {
                bytes[index * 4] = colour.r
                bytes[index * 4 + 1] = colour.g
                bytes[index * 4 + 2] = colour.b
                bytes[index * 4 + 3] = 255
            }
            let context = CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }

        /// The numbered image as a CGImage, each number forty steps of red
        /// apart so colour matching cannot blur one into the next.
        private func numberedCGImage() -> CGImage {
            var bytes: [UInt8] = []
            for pixel in numbered().pixels { bytes += [pixel.r * 40, 0, 0, 255] }
            let context = CGContext(
                data: &bytes, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }

        /// A decoded numbered image's numbers, a row at a time.
        private func numbers(_ image: Image) -> String? {
            image.decoded.map { decoded in
                let pixels = decoded.pixels
                let renumbered = pixels.pixels.map {
                    RGBA(r: UInt8((Double($0.r) / 40).rounded()), g: 0, b: 0)
                }
                return grid(RGBAImage(width: pixels.width, height: pixels.height, pixels: renumbered))
            }
        }

        @Test("A CGImage's pixels are drawn out once, turned to its orientation")
        func cgImagePixels() {
            let image = Image(numberedCGImage(), scale: 1, orientation: .left, label: Text("numbers"))
            #expect(numbers(image) == "135 024")
            let decorative = Image(decorative: numberedCGImage(), scale: 2)
            #expect(numbers(decorative) == "01 23 45")
        }

        @Test("Images of one CGImage are equal; of two, turned differently, or at two scales, are not")
        func cgImageEquality() {
            let picture = solid(RGBA(r: 255, g: 0, b: 0))
            let first = Image(decorative: picture, scale: 2)
            let second = Image(decorative: picture, scale: 2)
            #expect(first == second)
            #expect(Image(decorative: picture, scale: 1) != Image(decorative: picture, scale: 2), "their sizes differ")
            #expect(Image(decorative: picture, scale: 1) != Image(decorative: picture, scale: 1, orientation: .down))
            #expect(Image(decorative: picture, scale: 1) != Image(decorative: solid(RGBA(r: 255, g: 0, b: 0)), scale: 1))
        }

        @Test("An NSImage draws its pixels")
        func nsImagePixels() {
            let nsImage = NSImage(cgImage: solid(RGBA(r: 0, g: 0, b: 255)), size: NSSize(width: 4, height: 4))
            let pixels = Image(nsImage: nsImage).decoded?.pixels
            #expect(pixels?.width == 4 && pixels?.pixels.first == RGBA(r: 0, g: 0, b: 255))
        }

        @Test("A new picture under the same view draws at once, as the first did")
        func pictureChangesInPlace() {
            let harness = InputChainHarness(width: 8, height: 4)
            func drawn(_ picture: CGImage) -> String {
                harness.frame(
                    Image(decorative: picture, scale: 1).imageColorMode(.trueColor).frame(width: 8, height: 4)
                ).lines.joined()
            }
            let red = drawn(solid(RGBA(r: 255, g: 0, b: 0)))
            #expect(red.contains("255;0;0"))
            let blue = drawn(solid(RGBA(r: 0, g: 0, b: 255)))
            #expect(blue.contains("0;0;255") && !blue.contains("255;0;0"), "\(blue.debugDescription)")
        }
    #endif
}
