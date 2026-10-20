//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageLoader.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// ImageIO, not AppKit, on Apple platforms — and the difference is load-bearing.
// From the macOS 15 SDK AppKit imports SwiftUICore, and a module that imports
// AppKit at all — `internal import` included, in a package built without
// library evolution, which a SwiftPM package is — makes every app that imports
// it load SwiftUICore, whose extension members (`FormatStyle.offset(to:)` and
// the rest) then sit beside TUIkit's. ImageIO decodes every raster format
// `NSImage` did for this loader without that. See `SystemFormatStyle+DiscreteStatics.swift`
// and the `TUIkitAppKit` target, which is where AppKit lives now.
#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#else
    import CSTBImage
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - ImageLoader Protocol

/// Loads images from file paths or raw data and converts them to `RGBAImage`.
///
/// See `PlatformImageLoader` for the built-in implementation and the formats
/// it supports.
public protocol ImageLoader: Sendable {
    /// Loads an image from a file path.
    ///
    /// - Parameter path: The absolute file path to the image.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the file cannot be read or decoded.
    func loadImage(from path: String) throws -> RGBAImage

    /// Loads an image from raw data.
    ///
    /// - Parameter data: The image file data.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the data cannot be decoded.
    func loadImage(from data: Data) throws -> RGBAImage
}

// MARK: - ImageLoadError

/// Errors that can occur during image loading.
public enum ImageLoadError: Error, LocalizedError, CustomStringConvertible {
    /// The file was not found at the given path.
    case fileNotFound(String)

    /// The image format is not supported.
    case unsupportedFormat(String)

    /// The image data could not be decoded.
    case decodingFailed(String)

    /// A URL download failed.
    case downloadFailed(String)

    /// The image exceeds the maximum allowed pixel count.
    case imageTooLarge(pixelCount: Int, limit: Int)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        case .decodingFailed(let reason):
            return "Image decoding failed: \(reason)"
        case .downloadFailed(let reason):
            return "Image download failed: \(reason)"
        case .imageTooLarge(let pixelCount, let limit):
            return "Image too large: \(pixelCount) pixels (limit: \(limit))"
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Platform Image Loader

/// The built-in image loader, decoding with the best facility available for
/// the current build.
///
/// Selection is by capability rather than a hard-coded platform list: when
/// `canImport(ImageIO)` holds (Apple platforms) it decodes via ImageIO,
/// gaining the system image codecs and colour management with no third-party
/// code, and turning a picture by its EXIF orientation as `NSImage` does;
/// otherwise it falls back to the bundled stb_image C library (`CSTBImage`).
/// Both paths produce straight-alpha, row-major RGBA, so the backends are
/// interchangeable.
///
/// Formats via the stb_image fallback: PNG, JPEG, GIF, BMP, TGA, HDR, PSD, PNM.
/// The ImageIO path additionally decodes every raster format the host OS
/// reads (HEIC, TIFF, WebP, …), and of a file holding several images (an
/// icon's sizes, a multi-resolution TIFF) the largest. On Apple platforms a
/// PDF is rasterised too, its first page at one pixel a point
/// (``decodePDF(_:maxPixelCount:)``); EPS is not read.
public struct PlatformImageLoader: ImageLoader {

    public init() {}

    public func loadImage(from path: String) throws -> RGBAImage {
        try loadImage(from: path, maxPixelCount: nil)
    }

    public func loadImage(from data: Data) throws -> RGBAImage {
        try loadImage(from: data, maxPixelCount: nil)
    }

    /// Loads an image from a file path with an optional pixel count limit.
    ///
    /// - Parameters:
    ///   - path: The absolute file path to the image.
    ///   - maxPixelCount: The maximum allowed total pixel count, or `nil` for no limit.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the file cannot be read, decoded, or exceeds the limit.
    public func loadImage(from path: String, maxPixelCount: Int?) throws -> RGBAImage {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ImageLoadError.fileNotFound(path)
        }
        #if canImport(ImageIO)
            if let pdf = Self.pdfDocument(atPath: path) { return try decodePDF(pdf, maxPixelCount: maxPixelCount) }
            return try decodeWithImageIO(
                CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                describing: "image at \(path)", maxPixelCount: maxPixelCount)
        #else
            return try decodeWithSTB(data: Self.fileBytes(atPath: path), maxPixelCount: maxPixelCount)
        #endif
    }

    /// Loads an image from raw data with an optional pixel count limit.
    ///
    /// - Parameters:
    ///   - data: The image file data.
    ///   - maxPixelCount: The maximum allowed total pixel count, or `nil` for no limit.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the data cannot be decoded or exceeds the limit.
    public func loadImage(from data: Data, maxPixelCount: Int?) throws -> RGBAImage {
        #if canImport(ImageIO)
            if let pdf = Self.pdfDocument(data: data) { return try decodePDF(pdf, maxPixelCount: maxPixelCount) }
            return try decodeWithImageIO(
                CGImageSourceCreateWithData(data as CFData, nil), describing: "image data",
                maxPixelCount: maxPixelCount)
        #else
            return try decodeWithSTB(data: data, maxPixelCount: maxPixelCount)
        #endif
    }
}

// MARK: - stb_image Inputs (platform-independent)

extension PlatformImageLoader {
    /// `byteCount` as the C `int` length `stbi_load_from_memory` takes,
    /// rejecting anything that does not fit.
    ///
    /// Deliberately NOT inside the `#if !canImport(ImageIO)` arm below, even
    /// though only that arm calls it: the ceiling comes from stb_image's own
    /// signature, not from the host, and a helper compiled only on non-Apple
    /// platforms could only be tested there. The conversion used to be
    /// `Int32(data.count)` — the trapping initialiser — so a payload over
    /// 2 GiB aborted the process, wrecking a terminal left in raw mode, where
    /// the ImageIO arm throws for the same input.
    static func stbLength(forByteCount byteCount: Int) throws -> Int32 {
        guard let length = Int32(exactly: byteCount) else {
            throw ImageLoadError.decodingFailed(
                "stb_image: \(byteCount) bytes exceeds the \(Int32.max) byte maximum")
        }
        return length
    }

    /// The bytes of the file at `path`, as an `ImageLoadError` rather than a
    /// Foundation error.
    ///
    /// Outside the `#if !canImport(ImageIO)` arm below for the same reason as
    /// ``stbLength(forByteCount:)``: a helper compiled only on non-Apple
    /// platforms could only be tested there.
    ///
    /// This is NOT about avoiding C, or about streaming: it is so that
    /// stb_image never opens a file itself. `stbi_load(path:)` opens it with
    /// the NARROW `fopen`, which on Windows decodes the bytes Swift hands it
    /// under the process ANSI codepage instead of UTF-8 — CP1252 by default,
    /// where the two UTF-8 bytes of `é` spell `Ã©`, so `café.png` is looked up
    /// as `cafÃ©.png` and a path `FileManager.fileExists(atPath:)` confirmed
    /// two statements earlier cannot be opened (`stbi_failure_reason()` says
    /// "can't fopen"). Codepage coverage is irrelevant; the encoding mismatch
    /// alone is enough. Reading the bytes here leaves Foundation, which goes
    /// through the wide Win32 API, as the single path resolver on every host.
    static func fileBytes(atPath path: String) throws -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ImageLoadError.decodingFailed("Could not read \(path): \(error)")
        }
    }
}

// MARK: - stb_image Backend (non-Apple platforms)

#if !canImport(ImageIO)
    extension PlatformImageLoader {

        /// Decodes in-memory data with stb_image into straight-alpha, row-major RGBA.
        private func decodeWithSTB(data: Data, maxPixelCount: Int?) throws -> RGBAImage {
            var width: Int32 = 0
            var height: Int32 = 0
            var channels: Int32 = 0

            // Before the buffer is touched, because the conversion can fail and
            // the closure below cannot throw. See ``stbLength(forByteCount:)``.
            let length = try Self.stbLength(forByteCount: data.count)

            let rawPixels: UnsafeMutablePointer<UInt8>? = data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return nil }
                return stbi_load_from_memory(
                    baseAddress.assumingMemoryBound(to: UInt8.self),
                    length,
                    &width,
                    &height,
                    &channels,
                    4
                )
            }

            guard let pixels = rawPixels else {
                let reason = String(cString: stbi_failure_reason())
                throw ImageLoadError.decodingFailed("stb_image: \(reason)")
            }
            defer { stbi_image_free(pixels) }

            let pixelCount = Int(width) * Int(height)
            if let limit = maxPixelCount, pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: limit)
            }

            return pixelsFromRaw(pixels, width: Int(width), height: Int(height))
        }

        /// Converts raw stb_image RGBA output to an `RGBAImage`.
        private func pixelsFromRaw(
            _ rawPixels: UnsafeMutablePointer<UInt8>,
            width: Int,
            height: Int
        ) -> RGBAImage {
            let count = width * height
            var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: count)

            for pixelIndex in 0..<count {
                let offset = pixelIndex * 4
                pixels[pixelIndex] = RGBA(
                    r: rawPixels[offset],
                    g: rawPixels[offset + 1],
                    b: rawPixels[offset + 2],
                    a: rawPixels[offset + 3]
                )
            }

            return RGBAImage(width: width, height: height, pixels: pixels)
        }
    }
#endif

// MARK: - ImageIO Backend (Apple platforms)

#if canImport(ImageIO)
    extension PlatformImageLoader {

        /// A PDF's header, which a file of one begins with.
        private static let pdfHeader = Array("%PDF-".utf8)

        /// The PDF at `path`, or `nil` where the file is not one: its first bytes
        /// read, so another image's file costs one short read.
        static func pdfDocument(atPath path: String) -> CGPDFDocument? {
            guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: pdfHeader.count), Array(head) == pdfHeader else {
                return nil
            }
            return CGPDFDocument(URL(fileURLWithPath: path) as CFURL)
        }

        /// The PDF `data` holds, or `nil` where it is not one.
        static func pdfDocument(data: Data) -> CGPDFDocument? {
            guard data.starts(with: pdfHeader), let provider = CGDataProvider(data: data as CFData) else {
                return nil
            }
            return CGPDFDocument(provider)
        }

        /// A PDF's first page, rasterised at one pixel a point, turned as the page
        /// says, on a clear ground: what `NSImage` drew of one before this loader
        /// stopped importing AppKit (decisions B50, B-D3M-4), now through Core
        /// Graphics alone. At a pixel a point the image's natural size is its
        /// page's, in points, as SwiftUI's is.
        func decodePDF(_ document: CGPDFDocument, maxPixelCount: Int?) throws -> RGBAImage {
            guard let page = document.page(at: 1) else {
                throw ImageLoadError.decodingFailed("PDF has no pages")
            }
            let box = page.getBoxRect(.cropBox)
            let quarterTurns = (page.rotationAngle / 90 % 4 + 4) % 4
            let turned = quarterTurns % 2 == 1
            let width = Int((turned ? box.height : box.width).rounded(.up))
            let height = Int((turned ? box.width : box.height).rounded(.up))
            guard width > 0, height > 0 else { throw ImageLoadError.decodingFailed("PDF page is empty") }
            if let limit = maxPixelCount, width * height > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: width * height, limit: limit)
            }
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw ImageLoadError.decodingFailed("PDF: no bitmap context") }
            let target = CGRect(x: 0, y: 0, width: width, height: height)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            guard let image = context.makeImage() else { throw ImageLoadError.decodingFailed("PDF: nothing drawn") }
            return try decode(image, maxPixelCount: maxPixelCount)
        }

        /// Decodes the largest image of an ImageIO source (see
        /// ``largestImage(in:)``) into straight-alpha, row-major RGBA (row 0 =
        /// top) via a CoreGraphics bitmap context, matching the stb_image
        /// fallback's pixel contract so the two backends are interchangeable.
        ///
        /// Turned by its EXIF orientation, as `NSImage` — this loader's backend
        /// until it had to stop importing AppKit — turns it: a plain
        /// `CGImageSourceCreateImageAtIndex` hands back the pixels as stored,
        /// so a portrait photograph from a phone came out on its side. Only an
        /// image that needs turning takes the thumbnail path, at its full size,
        /// which is the one ImageIO call that applies the transform.
        private func decodeWithImageIO(
            _ source: CGImageSource?, describing what: String, maxPixelCount: Int?
        ) throws -> RGBAImage {
            guard let source, let chosen = Self.largestImage(in: source, fitting: maxPixelCount) else {
                throw ImageLoadError.decodingFailed("ImageIO could not decode \(what)")
            }
            let (index, properties) = chosen
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            // Before anything is drawn: a size declared too large is refused
            // without decoding it.
            let (declared, overflowed) = width.multipliedReportingOverflow(by: height)
            if let limit = maxPixelCount, overflowed || declared > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: overflowed ? Int.max : declared, limit: limit)
            }
            let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
            let image: CGImage?
            if orientation != 1, max(width, height) > 0 {
                image = CGImageSourceCreateThumbnailAtIndex(
                    source, index,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    ] as CFDictionary)
            } else {
                image = CGImageSourceCreateImageAtIndex(source, index, nil)
            }
            guard let image else {
                throw ImageLoadError.decodingFailed("ImageIO could not decode \(what)")
            }
            return try decode(image, maxPixelCount: maxPixelCount)
        }

        /// The image of `source` with the most pixels, by its declared size,
        /// that `limit` allows, and its properties — `nil` if it holds none.
        ///
        /// A file can hold several images: an icon's sizes, a multi-resolution
        /// TIFF's, an animation's frames. ImageIO's first is whatever comes
        /// first in the file — often an icon's smallest — where `NSImage`, this
        /// loader's backend until it stopped importing AppKit, drew the
        /// representation that best matched the first's size at the display's
        /// scale: measured on a Mac whose display is at 2×, a TIFF of a
        /// 16 × 16 and a 64 × 32 image drew the 64 × 32 one. The largest is that choice made without
        /// a display to ask, and the most detail to scale down from. A tie
        /// keeps the primary image, else the earliest, so an animation shows
        /// its first frame and a HEIF its primary image.
        ///
        /// Under a pixel limit, an image within it beats any that is not, so an
        /// icon whose largest size is over the limit still draws its largest
        /// that fits, as decoding the first image did. Only when none fits is
        /// the largest chosen, for the caller to refuse.
        private static func largestImage(
            in source: CGImageSource, fitting limit: Int?
        ) -> (Int, [CFString: Any]?)? {
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { return nil }
            let primary = min(CGImageSourceGetPrimaryImageIndex(source), count - 1)
            func properties(_ index: Int) -> [CFString: Any]? {
                CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            }
            func area(_ properties: [CFString: Any]?) -> Int {
                let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
                let (area, overflowed) = width.multipliedReportingOverflow(by: height)
                return overflowed ? Int.max : area
            }
            var best = (primary, properties(primary))
            guard count > 1 else { return best }
            var bestArea = area(best.1)
            func fits(_ area: Int) -> Bool { limit.map { area <= $0 } ?? true }
            for index in 0..<count where index != primary {
                let candidate = properties(index)
                let candidateArea = area(candidate)
                let isBetter = fits(candidateArea) == fits(bestArea)
                    ? candidateArea > bestArea : fits(candidateArea)
                if isBetter {
                    best = (index, candidate)
                    bestArea = candidateArea
                }
            }
            return best
        }

        /// Decodes a `CGImage` into straight-alpha, row-major RGBA (row 0 =
        /// top), the pixel contract every backend meets.
        ///
        /// - Parameters:
        ///   - cgImage: The image to draw out.
        ///   - maxPixelCount: The most pixels to accept, or `nil` for any.
        /// - Returns: The image's pixels.
        package func decode(_ cgImage: CGImage, maxPixelCount: Int?) throws -> RGBAImage {
            let width = cgImage.width
            let height = cgImage.height
            let pixelCount = width * height
            if let limit = maxPixelCount, pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: limit)
            }
            guard width > 0, height > 0 else {
                return RGBAImage(width: width, height: height, pixels: [])
            }

            // Render into a known RGBA8, premultiplied-last, top-left-origin buffer.
            let bytesPerRow = width * 4
            var premultiplied = [UInt8](repeating: 0, count: height * bytesPerRow)
            let drew: Bool = premultiplied.withUnsafeMutableBytes { raw in
                guard let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                // CoreGraphics emits a benign one-time IOKit probe line to stderr
                // the first time it rasterizes an image in a VM (e.g.
                // "IOServiceMatching failed for: AppleM2ScalerParavirtDriver").
                // Harmless in a normal app, but a TUI owns the alternate screen,
                // so swallow stderr just around the draw — the only thing that
                // triggers it — and restore it immediately.
                Self.suppressingStandardError {
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
                return true
            }
            guard drew else {
                throw ImageLoadError.decodingFailed("Could not create RGBA bitmap context")
            }

            return RGBAImage(
                width: width,
                height: height,
                pixels: Self.straightAlphaPixels(from: premultiplied, count: pixelCount)
            )
        }

        /// Converts a premultiplied-last RGBA byte buffer to straight-alpha pixels.
        private static func straightAlphaPixels(from buffer: [UInt8], count: Int) -> [RGBA] {
            var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: count)
            for index in 0..<count {
                let offset = index * 4
                let alpha = buffer[offset + 3]
                switch alpha {
                case 0:
                    pixels[index] = RGBA(r: 0, g: 0, b: 0, a: 0)
                case 255:
                    pixels[index] = RGBA(
                        r: buffer[offset],
                        g: buffer[offset + 1],
                        b: buffer[offset + 2],
                        a: 255
                    )
                default:
                    let a = Int(alpha)
                    pixels[index] = RGBA(
                        r: UInt8(min(255, (Int(buffer[offset]) * 255 + a / 2) / a)),
                        g: UInt8(min(255, (Int(buffer[offset + 1]) * 255 + a / 2) / a)),
                        b: UInt8(min(255, (Int(buffer[offset + 2]) * 255 + a / 2) / a)),
                        a: alpha
                    )
                }
            }
            return pixels
        }

        /// Serializes ``suppressingStandardError(_:)``. The file-descriptor
        /// table is process-global, and image decodes run concurrently (each
        /// load is `@concurrent`): unserialized, a second load's `dup` could
        /// capture fd 2 while a first had it pointed at `/dev/null` — and its
        /// "restore" then pins stderr to the null device for the rest of the
        /// process.
        static let stderrRedirectLock = NSLock()

        /// Runs `body` with stderr (fd 2) temporarily redirected to `/dev/null`.
        ///
        /// Used to swallow the benign one-time IOKit probe line CoreGraphics
        /// writes to stderr during the first image rasterization in a VM, which
        /// would otherwise corrupt the alternate-screen TUI. The window is the
        /// single synchronous draw call; a concurrent stderr write (none is
        /// expected mid-render — the renderer writes stdout) would be lost.
        ///
        /// Internal (not private) as the test seam: the save/redirect/restore
        /// dance is what the race lives in, and the tests hammer it directly.
        static func suppressingStandardError(_ body: () -> Void) {
            stderrRedirectLock.lock()
            defer { stderrRedirectLock.unlock() }
            fflush(stderr)
            let saved = dup(STDERR_FILENO)
            let devNull = open("/dev/null", O_WRONLY)
            if devNull >= 0 {
                dup2(devNull, STDERR_FILENO)
                close(devNull)
            }
            defer {
                fflush(stderr)
                if saved >= 0 {
                    dup2(saved, STDERR_FILENO)
                    close(saved)
                }
            }
            body()
        }
    }
#endif

// MARK: - URL Image Cache

/// A session-scoped cache for images downloaded from URLs.
///
/// Cached entries persist for the lifetime of the application.
/// Thread-safe via an internal lock.
public final class URLImageCache: @unchecked Sendable {
    /// Shared session cache.
    public static let shared = URLImageCache()

    private var cache: [String: RGBAImage] = [:]
    private let lock = NSLock()

    /// Creates an empty cache.
    ///
    /// `loadImage(fromURL:cache:…)` takes the cache to use, which was always
    /// the point — an app that wants its own, or a test that wants one nobody
    /// else can see, should not be reaching into a process-wide singleton. The
    /// initializer being private made that parameter accept exactly one value,
    /// so the seam existed on paper only.
    public init() {}

    /// Returns a cached image for the given URL string, or nil.
    public func get(_ urlString: String) -> RGBAImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[urlString]
    }

    /// Stores an image in the cache for the given URL string.
    public func set(_ urlString: String, image: RGBAImage) {
        lock.lock()
        defer { lock.unlock() }
        cache[urlString] = image
    }
}

// MARK: - URL Image Loading

extension PlatformImageLoader {

    /// Loads an image from a URL, using the session cache.
    ///
    /// On first access the image is downloaded and cached; subsequent calls
    /// for the same URL return the cached copy.
    ///
    /// The download *suspends* — it never blocks the calling thread — and it
    /// honours cancellation: cancelling the enclosing task cancels the
    /// transfer and throws `CancellationError` promptly, rather than leaving
    /// the caller waiting out `timeout`.
    ///
    /// The label is `fromURL:` rather than `from:` because the two arguments
    /// this takes in practice — `(String, maxPixelCount:)` — are otherwise
    /// indistinguishable from the file-path overload's, `cache` and `timeout`
    /// both having defaults. Overload resolution silently preferred whichever
    /// was the better match in context, which for a *path* in an `async`
    /// function meant downloading it.
    ///
    /// - Parameters:
    ///   - urlString: The URL to download.
    ///   - cache: The image cache to use.
    ///   - timeout: The download timeout in seconds (default: 30).
    ///   - maxPixelCount: The maximum allowed total pixel count, or `nil` for no limit.
    /// - Returns: The decoded image.
    /// - Throws: `CancellationError` if the task was cancelled; `ImageLoadError`
    ///   on network or decoding failure, or if the image exceeds the size limit.
    public func loadImage(
        fromURL urlString: String,
        cache: URLImageCache = .shared,
        timeout: TimeInterval = 30,
        maxPixelCount: Int? = nil
    ) async throws -> RGBAImage {
        if let cached = cache.get(urlString) {
            // A cache hit still has to clear the caller's limit. The cache is
            // keyed by URL alone and shared across the process, but
            // `maxPixelCount` comes from the environment and so differs from
            // one view to the next — so without this, the FIRST load decides
            // for everyone. A view with no limit warms the cache; a later view
            // that asked for a strict one is handed the oversized image anyway,
            // its limit not applying precisely because something else got there
            // first. Whether an image is too big cannot depend on who arrived
            // before you.
            let pixelCount = cached.width * cached.height
            if let limit = maxPixelCount, pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: limit)
            }
            return cached
        }

        #if !canImport(FoundationNetworking) && !canImport(Darwin)
            // No URL loading on this platform, and this is where that has to be
            // said. `URLSession` is in Foundation on Apple platforms and in
            // FoundationNetworking everywhere else that has it; WebAssembly's
            // wasip1 has neither, and could not use one anyway — it has no
            // sockets. Everything else about images works there: a file loads,
            // an `RGBAImage` handed over directly renders, and the cache above
            // still answers. Only the fetch is missing, so only the fetch says
            // so, at the moment it is asked for rather than by being absent
            // from the API and taking every caller's source with it.
            throw ImageLoadError.downloadFailed(
                "This platform has no URL loading, so images cannot be fetched over the network: \(urlString)")
        #else
        guard let url = URL(string: urlString) else {
            throw ImageLoadError.downloadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let data: Data
        do {
            data = try await Self.download(request)
        } catch let error as ImageLoadError {
            throw error
        } catch {
            // A cancelled transfer surfaces as `URLError.cancelled`; report it
            // as what it is so callers can tell "gave up on purpose" from
            // "the network failed" and skip publishing a stale failure.
            if Task.isCancelled { throw CancellationError() }
            throw ImageLoadError.downloadFailed(error.localizedDescription)
        }

        let image = try loadImage(from: data, maxPixelCount: maxPixelCount)
        cache.set(urlString, image: image)
        return image
        #endif
    }

    #if canImport(FoundationNetworking) || canImport(Darwin)
    /// Runs one request to completion, bridging `URLSession`'s callback API to
    /// `async` — and structured cancellation to `URLSessionTask.cancel()`.
    ///
    /// The obvious spelling of this is a `DispatchSemaphore` around the
    /// callback, which is what this used to be. That parks a whole thread for
    /// the duration of the transfer, and the caller is on the cooperative
    /// pool, which has one thread per core: two slow images on a two-core
    /// machine and *nothing else* async makes progress until they finish or
    /// time out. Cancellation could not help, because a blocked thread cannot
    /// notice it.
    private static func download(_ request: URLRequest) async throws -> Data {
        let handle = URLTaskHandle()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: request) { data, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(
                            throwing: ImageLoadError.downloadFailed("No data received"))
                    }
                }
                handle.adopt(task)
            }
        } onCancel: {
            handle.cancel()
        }
    }
    #endif
}

// MARK: - Cancellation Bridge

#if canImport(FoundationNetworking) || canImport(Darwin)

/// Carries a `URLSessionDataTask` from the body of a
/// `withTaskCancellationHandler` to its cancellation handler.
///
/// The handler can run at any time, including *before* the body has created
/// the task (cancellation that lands in that window would otherwise be lost,
/// leaving the continuation to wait out the request's full timeout). Ordering
/// is therefore settled under the lock: whichever arrives second acts.
private final class URLTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    /// Takes ownership of the task and starts it.
    func adopt(_ task: URLSessionDataTask) {
        lock.lock()
        let cancelledFirst = isCancelled
        if !cancelledFirst { self.task = task }
        lock.unlock()

        // Resume unconditionally, even when already cancelled: only a task
        // that has been started is guaranteed to deliver its completion
        // handler, and that handler is what resumes the continuation.
        task.resume()
        if cancelledFirst { task.cancel() }
    }

    func cancel() {
        lock.lock()
        let started = task
        isCancelled = true
        task = nil
        lock.unlock()

        started?.cancel()
    }
}
#endif
