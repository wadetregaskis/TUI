//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageLoader+WIC.swift
//
//  Decoding on Windows with the Windows Imaging Component, the system's own
//  codecs: TIFF, WebP, HEIF and AVIF, JPEG XL and XR, icons, DDS and camera
//  raw files beside the formats stb_image reads, each picture turned by its
//  EXIF orientation.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

#if os(Windows)
import WinSDK
#endif

// MARK: - Orientation (platform-independent)

extension PlatformImageLoader {
    /// The rotation (clockwise, in quarter turns) and the horizontal flip that
    /// show a picture stored with EXIF `orientation` upright, as WIC's flip
    /// rotator takes them: it flips before it turns, so the two orientations
    /// that mirror across a diagonal take the turn each other would without a
    /// flip (measured 2026-11-20 on JPEGs of all eight).
    static func wicTransform(forOrientation orientation: Int) -> (quarterTurns: Int, flipsHorizontally: Bool) {
        switch orientation {
        case 2: (0, true)
        case 3: (2, false)
        case 4: (2, true)  // A vertical flip: a horizontal one, turned a half.
        case 5: (3, true)
        case 6: (1, false)
        case 7: (1, true)
        case 8: (3, false)
        default: (0, false)
        }
    }

    /// The index of the image to decode of those whose sizes are `sizes`: the
    /// one with the most pixels that `limit` allows, the first on a tie,
    /// else the largest, for the caller to refuse; `nil` for none. As
    /// ImageIO's path chooses (``largestImage(in:fitting:)`` on Apple
    /// platforms), so an icon draws its largest size that fits.
    static func largestIndex(of sizes: [(width: Int, height: Int)], fitting limit: Int?) -> Int? {
        guard !sizes.isEmpty else { return nil }
        func area(_ size: (width: Int, height: Int)) -> Int {
            let (area, overflowed) = size.width.multipliedReportingOverflow(by: size.height)
            return overflowed ? Int.max : area
        }
        func fits(_ area: Int) -> Bool { limit.map { area <= $0 } ?? true }
        var best = 0
        var bestArea = area(sizes[0])
        for index in sizes.indices.dropFirst() {
            let candidate = area(sizes[index])
            if fits(candidate) == fits(bestArea) ? candidate > bestArea : fits(candidate) {
                best = index
                bestArea = candidate
            }
        }
        return best
    }
}

#if os(Windows)

// MARK: - WIC Backend (Windows)

extension PlatformImageLoader {
    /// Decodes the file at `path` with WIC into straight-alpha, row-major RGBA,
    /// at `reduction` of its size each way, and the picture's size whole, as
    /// shown: the largest of a file's images that `maxPixelCount` allows,
    /// turned by its EXIF orientation.
    ///
    /// - Throws: ``ImageLoadError/unsupportedFormat(_:)`` where Windows has no
    ///   decoder for it, so the caller can try stb_image;
    ///   ``ImageLoadError/imageTooLarge(pixelCount:limit:)`` for a picture
    ///   declared past the limit, refused before it is decoded; otherwise
    ///   ``ImageLoadError/decodingFailed(_:)``.
    func decodeWithWIC(
        path: String, maxPixelCount: Int?, reducedBy reduction: Int = 1
    ) throws -> (image: RGBAImage, width: Int, height: Int) {
        try unsafe WICSession.run { session in
            let decoder = try unsafe session.decoder(path: path)
            return try unsafe session.decode(decoder, maxPixelCount: maxPixelCount, reducedBy: reduction)
        }
    }

    /// ``decodeWithWIC(path:maxPixelCount:reducedBy:)`` of a file's bytes.
    func decodeWithWIC(
        data: Data, maxPixelCount: Int?, reducedBy reduction: Int = 1
    ) throws -> (image: RGBAImage, width: Int, height: Int) {
        try unsafe WICSession.run { session in
            let decoder = try unsafe session.decoder(data: data)
            return try unsafe session.decode(decoder, maxPixelCount: maxPixelCount, reducedBy: reduction)
        }
    }

    /// The size, as shown, of the picture ``decodeWithWIC(path:maxPixelCount:reducedBy:)``
    /// decodes from the file at `path`, read from its header with nothing
    /// decoded.
    func pictureSizeWithWIC(path: String, maxPixelCount: Int?) throws -> (width: Int, height: Int) {
        try unsafe WICSession.run { session in
            let decoder = try unsafe session.decoder(path: path)
            let (frame, width, height, orientation) = try unsafe session.chosenFrame(of: decoder, maxPixelCount: maxPixelCount)
            unsafe session.release(frame)
            return Self.wicTransform(forOrientation: orientation).quarterTurns % 2 == 1 ? (height, width) : (width, height)
        }
    }

    /// The decode ``loadImage(from:maxPixelCount:)`` makes on Windows: WIC's,
    /// and stb_image's where WIC has no decoder for the picture or cannot
    /// decode it (stb_image reads TGA, HDR, PSD and PNM, which WIC does not).
    /// A picture too large is refused, not handed on.
    func decodeOnWindows(
        path: String, maxPixelCount: Int?, reducedBy reduction: Int = 1
    ) throws -> (image: RGBAImage, width: Int, height: Int) {
        do {
            return try decodeWithWIC(path: path, maxPixelCount: maxPixelCount, reducedBy: reduction)
        } catch let error as ImageLoadError {
            if case .imageTooLarge = error { throw error }
            return try decodeWithSTB(
                data: Self.fileBytes(atPath: path), maxPixelCount: maxPixelCount, reducedBy: reduction)
        }
    }

    /// ``decodeOnWindows(path:maxPixelCount:reducedBy:)`` of a file's bytes.
    func decodeOnWindows(data: Data, maxPixelCount: Int?) throws -> RGBAImage {
        do {
            return try decodeWithWIC(data: data, maxPixelCount: maxPixelCount).image
        } catch let error as ImageLoadError {
            if case .imageTooLarge = error { throw error }
            return try decodeWithSTB(data: data, maxPixelCount: maxPixelCount).image
        }
    }
}

// MARK: - A decode's COM objects

/// One decode's WIC factory, on a thread with COM initialised
/// (`WindowsCOM`), and the COM objects it makes, each released before it
/// ends.
///
/// Every COM call goes through its interface's table of functions
/// (`lpVtbl`); an object made is released (`Release`) once used, as nothing
/// here keeps one past the decode.
@unsafe struct WICSession {
    let factory: UnsafeMutablePointer<IWICImagingFactory>

    /// Runs `body` with COM initialised and a factory made, both undone after.
    static func run<T>(_ body: (Self) throws -> T) throws -> T {
        try WindowsCOM.withApartment { try unsafe withFactory(body) }
    }

    /// ``run(_:)``'s body, on a thread with COM initialised.
    private static func withFactory<T>(_ body: (Self) throws -> T) throws -> T {
        var clsid = CLSID_WICImagingFactory
        var iid = IID_IWICImagingFactory
        var made: UnsafeMutableRawPointer?
        let result = unsafe CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &made)
        guard result == S_OK, let made = unsafe made else {
            throw ImageLoadError.decodingFailed("WIC: no imaging factory (\(WICResult.describe(result)))")
        }
        let session = unsafe Self(factory: made.assumingMemoryBound(to: IWICImagingFactory.self))
        defer { _ = unsafe session.factory.pointee.lpVtbl.pointee.Release(session.factory) }
        return try unsafe body(session)
    }

    /// A decoder for the file at `path`, opened by its wide path.
    func decoder(path: String) throws -> UnsafeMutablePointer<IWICBitmapDecoder> {
        let wide = Array(path.utf16) + [0]
        var decoder: UnsafeMutablePointer<IWICBitmapDecoder>?
        let result = unsafe factory.pointee.lpVtbl.pointee.CreateDecoderFromFilename(
            factory, wide, nil, DWORD(0x8000_0000), WICDecodeMetadataCacheOnDemand, &decoder)  // GENERIC_READ
        return try unsafe Self.made(decoder, result, "the image at \(path)")
    }

    /// A decoder for `data`, read from a stream that holds a copy of it
    /// (`SHCreateMemStream`), which the decoder keeps for as long as it reads.
    func decoder(data: Data) throws -> UnsafeMutablePointer<IWICBitmapDecoder> {
        guard let length = UINT(exactly: data.count) else {
            throw ImageLoadError.decodingFailed("WIC: \(data.count) bytes are too many to read")
        }
        guard let stream = unsafe SHCreateMemStream(Array(data), length) else {
            throw ImageLoadError.decodingFailed("WIC: no stream over the image data")
        }
        defer { _ = unsafe stream.pointee.lpVtbl.pointee.Release(stream) }
        var decoder: UnsafeMutablePointer<IWICBitmapDecoder>?
        let result = unsafe factory.pointee.lpVtbl.pointee.CreateDecoderFromStream(
            factory, stream, nil, WICDecodeMetadataCacheOnDemand, &decoder)
        return try unsafe Self.made(decoder, result, "image data")
    }

    /// The frame to decode of `decoder`'s (``PlatformImageLoader/largestIndex(of:fitting:)``),
    /// its size as stored and its EXIF orientation; refused past
    /// `maxPixelCount` before anything is decoded. `decoder` is released.
    func chosenFrame(
        of decoder: UnsafeMutablePointer<IWICBitmapDecoder>, maxPixelCount: Int?
    ) throws -> (frame: UnsafeMutablePointer<IWICBitmapFrameDecode>, width: Int, height: Int, orientation: Int) {
        defer { _ = unsafe decoder.pointee.lpVtbl.pointee.Release(decoder) }
        var count: UINT = 0
        _ = unsafe decoder.pointee.lpVtbl.pointee.GetFrameCount(decoder, &count)
        var sizes: [(width: Int, height: Int)] = []
        for index in 0..<count {
            let frame = try unsafe self.frame(index, of: decoder)
            sizes.append(unsafe Self.size(of: frame))
            unsafe release(frame)
        }
        guard let index = PlatformImageLoader.largestIndex(of: sizes, fitting: maxPixelCount) else {
            throw ImageLoadError.decodingFailed("WIC: the picture holds no image")
        }
        let (width, height) = sizes[index]
        let (pixels, overflowed) = width.multipliedReportingOverflow(by: height)
        if let limit = maxPixelCount, overflowed || pixels > limit {
            throw ImageLoadError.imageTooLarge(pixelCount: overflowed ? Int.max : pixels, limit: limit)
        }
        let frame = try unsafe self.frame(UINT(index), of: decoder)
        return unsafe (frame, width, height, Self.orientation(of: frame))
    }

    /// `decoder`'s chosen frame, turned upright, as straight-alpha RGBA at
    /// `reduction` of its size, and its size whole as shown. `decoder` is
    /// released.
    func decode(
        _ decoder: UnsafeMutablePointer<IWICBitmapDecoder>, maxPixelCount: Int?, reducedBy reduction: Int
    ) throws -> (image: RGBAImage, width: Int, height: Int) {
        let (frame, _, _, orientation) = try unsafe chosenFrame(of: decoder, maxPixelCount: maxPixelCount)
        defer { unsafe release(frame) }
        let (quarterTurns, flips) = PlatformImageLoader.wicTransform(forOrientation: orientation)
        var options = [
            WICBitmapTransformRotate0, WICBitmapTransformRotate90, WICBitmapTransformRotate180,
            WICBitmapTransformRotate270,
        ][quarterTurns].rawValue
        if flips { options |= WICBitmapTransformFlipHorizontal.rawValue }
        var rotator: UnsafeMutablePointer<IWICBitmapFlipRotator>?
        let made = unsafe factory.pointee.lpVtbl.pointee.CreateBitmapFlipRotator(factory, &rotator)
        guard made == S_OK, let rotator = unsafe rotator else {
            throw ImageLoadError.decodingFailed("WIC: no flip rotator (\(WICResult.describe(made)))")
        }
        defer { _ = unsafe rotator.pointee.lpVtbl.pointee.Release(rotator) }
        let initialised = unsafe frame.withMemoryRebound(to: IWICBitmapSource.self, capacity: 1) {
            unsafe rotator.pointee.lpVtbl.pointee.Initialize(rotator, $0, WICBitmapTransformOptions(rawValue: options))
        }
        guard initialised == S_OK else {
            throw ImageLoadError.decodingFailed("WIC: could not turn the picture (\(WICResult.describe(initialised)))")
        }
        let image = try unsafe rotator.withMemoryRebound(to: IWICBitmapSource.self, capacity: 1) {
            try unsafe Self.straightRGBA(of: $0)
        }
        return (image.reduced(by: reduction), image.width, image.height)
    }

    /// `source`'s pixels converted to straight-alpha 32-bit RGBA, row 0 the top.
    static func straightRGBA(of source: UnsafeMutablePointer<IWICBitmapSource>) throws -> RGBAImage {
        var format = GUID_WICPixelFormat32bppRGBA
        var converted: UnsafeMutablePointer<IWICBitmapSource>?
        let result = unsafe WICConvertBitmapSource(&format, source, &converted)
        guard result == S_OK, let converted = unsafe converted else {
            throw ImageLoadError.decodingFailed("WIC: could not convert the pixels (\(WICResult.describe(result)))")
        }
        defer { _ = unsafe converted.pointee.lpVtbl.pointee.Release(converted) }
        var width: UINT = 0
        var height: UINT = 0
        _ = unsafe converted.pointee.lpVtbl.pointee.GetSize(converted, &width, &height)
        let (stride, strideOverflowed) = Int(width).multipliedReportingOverflow(by: 4)
        let (count, countOverflowed) = stride.multipliedReportingOverflow(by: Int(height))
        guard !strideOverflowed, !countOverflowed, let bufferSize = UINT(exactly: count) else {
            throw ImageLoadError.decodingFailed("WIC: a picture of \(width) × \(height) is too large to hold")
        }
        guard width > 0, height > 0 else { return RGBAImage(width: Int(width), height: Int(height), pixels: []) }
        var bytes = [UInt8](repeating: 0, count: count)
        let copied = unsafe converted.pointee.lpVtbl.pointee.CopyPixels(converted, nil, UINT(stride), bufferSize, &bytes)
        guard copied == S_OK else {
            throw ImageLoadError.decodingFailed("WIC: could not read the pixels (\(WICResult.describe(copied)))")
        }
        // 32bppRGBA is straight alpha, in the loader's own order.
        let pixels = (0..<(count / 4)).map { index in
            let at = index * 4
            return RGBA(r: bytes[at], g: bytes[at + 1], b: bytes[at + 2], a: bytes[at + 3])
        }
        return RGBAImage(width: Int(width), height: Int(height), pixels: pixels)
    }

    /// Frame `index` of `decoder`.
    func frame(
        _ index: UINT, of decoder: UnsafeMutablePointer<IWICBitmapDecoder>
    ) throws -> UnsafeMutablePointer<IWICBitmapFrameDecode> {
        var frame: UnsafeMutablePointer<IWICBitmapFrameDecode>?
        let result = unsafe decoder.pointee.lpVtbl.pointee.GetFrame(decoder, index, &frame)
        guard result == S_OK, let frame = unsafe frame else {
            throw ImageLoadError.decodingFailed("WIC: no frame \(index) (\(WICResult.describe(result)))")
        }
        return unsafe frame
    }

    /// Releases `frame`.
    func release(_ frame: UnsafeMutablePointer<IWICBitmapFrameDecode>) {
        _ = unsafe frame.pointee.lpVtbl.pointee.Release(frame)
    }

    /// `frame`'s size as stored.
    static func size(of frame: UnsafeMutablePointer<IWICBitmapFrameDecode>) -> (width: Int, height: Int) {
        var width: UINT = 0
        var height: UINT = 0
        _ = unsafe frame.pointee.lpVtbl.pointee.GetSize(frame, &width, &height)
        return (Int(width), Int(height))
    }

    /// `frame`'s EXIF orientation (`System.Photo.Orientation`), 1 where it
    /// states none or has no metadata to read.
    private static func orientation(of frame: UnsafeMutablePointer<IWICBitmapFrameDecode>) -> Int {
        var reader: UnsafeMutablePointer<IWICMetadataQueryReader>?
        guard unsafe frame.pointee.lpVtbl.pointee.GetMetadataQueryReader(frame, &reader) == S_OK,
            let reader = unsafe reader
        else { return 1 }
        defer { _ = unsafe reader.pointee.lpVtbl.pointee.Release(reader) }
        return unsafe unsignedMetadata("System.Photo.Orientation", in: reader) ?? 1
    }

    /// The whole number `reader` holds under the metadata query `name`, or
    /// `nil` where it holds none, or something else there.
    static func unsignedMetadata(_ name: String, in reader: UnsafeMutablePointer<IWICMetadataQueryReader>) -> Int? {
        var value = unsafe PROPVARIANT()
        defer { _ = unsafe PropVariantClear(&value) }
        let wide = Array(name.utf16) + [0]
        guard unsafe reader.pointee.lpVtbl.pointee.GetMetadataByName(reader, wide, &value) == S_OK else { return nil }
        switch Int32(unsafe value.vt) {
        case Int32(VT_UI1.rawValue): return Int(unsafe value.bVal)
        case Int32(VT_UI2.rawValue): return Int(unsafe value.uiVal)
        case Int32(VT_UI4.rawValue): return Int(unsafe value.ulVal)
        default: return nil
        }
    }

    /// The decoder `made` names, or the error `result` says: unsupported where
    /// WIC has no decoder for the picture, so the caller can try another.
    private static func made(
        _ decoder: UnsafeMutablePointer<IWICBitmapDecoder>?, _ result: HRESULT, _ what: String
    ) throws -> UnsafeMutablePointer<IWICBitmapDecoder> {
        if result == S_OK, let decoder = unsafe decoder { return unsafe decoder }
        if WICResult.noDecoder.contains(UInt32(bitPattern: result)) {
            throw ImageLoadError.unsupportedFormat("WIC has no decoder for \(what)")
        }
        throw ImageLoadError.decodingFailed("WIC could not open \(what) (\(WICResult.describe(result)))")
    }
}

/// What a WIC call answered.
private enum WICResult {
    /// The `HRESULT`s WIC answers when it has no decoder for a picture:
    /// `WINCODEC_ERR_COMPONENTNOTFOUND` and `WINCODEC_ERR_UNKNOWNIMAGEFORMAT`.
    static let noDecoder: Set<UInt32> = [0x8898_2F50, 0x8898_2F80]

    /// An `HRESULT` as Windows writes one.
    static func describe(_ result: HRESULT) -> String {
        "0x" + String(UInt32(bitPattern: result), radix: 16, uppercase: true)
    }
}

#endif
