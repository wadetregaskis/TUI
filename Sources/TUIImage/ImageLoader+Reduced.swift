//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageLoader+Reduced.swift
//
//  A file's picture at the size it is drawn rather than the size it is: its
//  size read from its header, and its pixels decoded at a power-of-two
//  fraction of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#else
    import CSTBImage
#endif

// MARK: - Reduced Decoding

extension PlatformImageLoader {
    /// The largest reduction ``reduction(of:covering:)`` answers: a picture
    /// 65,536 times its drawn size each way is not one anybody draws, and the
    /// bound keeps the doubling finite whatever size a header declares.
    static let maximumReduction = 1 << 16

    /// How far a picture of `size` pixels can be reduced and still have at
    /// least `needed` pixels on each axis: the largest power of two, 1 where
    /// it cannot be reduced at all.
    ///
    /// A power of two, not the exact ratio, for three reasons. JPEG decodes
    /// natively at a half, a quarter and an eighth of its size, from its own
    /// coefficients, so ImageIO's thumbnail is cheapest at those; stb_image's
    /// pictures are averaged down by whole blocks (``RGBAImage/boxReduced(by:)``);
    /// and a box that grows or shrinks a cell at a time — a window dragged, a
    /// zoom — decodes again only when it crosses a power of two, not on every
    /// frame. What is kept is at most twice the pixels needed on each axis.
    package static func reduction(
        of size: (width: Int, height: Int), covering needed: (width: Int, height: Int)
    ) -> Int {
        let neededWidth = max(1, needed.width)
        let neededHeight = max(1, needed.height)
        var reduction = 1
        while reduction < maximumReduction, size.width / (reduction * 2) >= neededWidth,
            size.height / (reduction * 2) >= neededHeight
        {
            reduction *= 2
        }
        return reduction
    }

    /// The key a file's picture decoded at `reduction` of its size is cached
    /// under: the file's own key (``cacheKey(forFile:)``) for the whole
    /// picture, and that key with the reduction after it for any other, so a
    /// picture drawn at two sizes is kept at both and neither is handed to the
    /// other. `nil` for a file whose attributes cannot be read.
    package static func cacheKey(forFile path: String, reducedBy reduction: Int) -> String? {
        guard let key = cacheKey(forFile: path) else { return nil }
        // `#1/4`: a quarter. No file key ends so — it ends in its modification
        // time — so no picture's key is another's reduced.
        return reduction > 1 ? "\(key)#1/\(reduction)" : key
    }

    /// The size, in pixels, of the picture ``loadImage(from:maxPixelCount:)``
    /// decodes from the file at `path`, read from its header with nothing
    /// decoded: the same image of a file holding several, turned by its
    /// orientation as the decode turns it.
    ///
    /// - Throws: `ImageLoadError` for a file that is missing, not a regular
    ///   file, unreadable, or of a picture past `maxPixelCount`.
    package func pictureSize(atPath path: String, maxPixelCount: Int?) throws -> (width: Int, height: Int) {
        try Self.requireRegularFile(atPath: path)
        #if canImport(ImageIO)
            if let pdf = Self.pdfDocument(atPath: path) {
                let page = try Self.firstPage(of: pdf, maxPixelCount: maxPixelCount)
                return (page.width, page.height)
            }
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                case let (_, properties)? = Self.largestImage(in: source, fitting: maxPixelCount)
            else {
                throw ImageLoadError.decodingFailed("ImageIO could not read the image at \(path)")
            }
            let (width, height, orientation) = try Self.declaredSize(properties, maxPixelCount: maxPixelCount)
            guard width > 0, height > 0 else {
                throw ImageLoadError.decodingFailed("ImageIO could not read the size of the image at \(path)")
            }
            return (5...8).contains(orientation) ? (height, width) : (width, height)
        #else
            let data = try Self.fileBytes(atPath: path)
            let length = try Self.stbLength(forByteCount: data.count)
            var width: Int32 = 0
            var height: Int32 = 0
            var channels: Int32 = 0
            let read: Int32 = unsafe data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return 0 }
                return unsafe stbi_info_from_memory(
                    base.assumingMemoryBound(to: UInt8.self), length, &width, &height, &channels)
            }
            guard read != 0, width > 0, height > 0 else {
                throw ImageLoadError.decodingFailed("stb_image: \(unsafe String(cString: stbi_failure_reason()))")
            }
            let (pixelCount, overflowed) = Int(width).multipliedReportingOverflow(by: Int(height))
            if let limit = maxPixelCount, overflowed || pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: overflowed ? Int.max : pixelCount, limit: limit)
            }
            return (Int(width), Int(height))
        #endif
    }

    /// Loads the picture in the file at `path` at `reduction` of its size each
    /// way — a power of two, ``reduction(of:covering:)``'s — and the size it
    /// has whole, which is what it is laid out as.
    ///
    /// Decoded straight to that size where the decoder can: ImageIO's
    /// thumbnail, on Apple platforms, which decodes a JPEG at an eighth of
    /// its size without ever holding it whole. stb_image cannot, so there the
    /// picture is decoded whole and averaged down (``RGBAImage/boxReduced(by:)``):
    /// only the copy kept is smaller. A PDF is rasterised at the size wanted.
    ///
    /// `maxPixelCount` limits the picture's own size, not the reduced one's:
    /// whether a picture is too large does not depend on how small it is drawn.
    ///
    /// - Throws: `ImageLoadError` if the file cannot be read, decoded, or
    ///   exceeds the limit.
    package func loadImage(
        from path: String, maxPixelCount: Int?, reducedBy reduction: Int
    ) throws -> (image: RGBAImage, width: Int, height: Int) {
        try Self.requireRegularFile(atPath: path)
        let reduction = min(max(1, reduction), Self.maximumReduction)
        #if canImport(ImageIO)
            if let pdf = Self.pdfDocument(atPath: path) {
                return try decodePDF(pdf, maxPixelCount: maxPixelCount, reducedBy: reduction)
            }
            return try decodeWithImageIO(
                CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                describing: "image at \(path)", maxPixelCount: maxPixelCount, reducedBy: reduction)
        #else
            return try decodeWithSTB(
                data: Self.fileBytes(atPath: path), maxPixelCount: maxPixelCount, reducedBy: reduction)
        #endif
    }
}
