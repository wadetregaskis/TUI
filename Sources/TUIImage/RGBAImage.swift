//  🖥️ TUI — A Terminal UI framework for Swift
//  RGBAImage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore

// MARK: - RGBA Pixel

/// A single pixel with red, green, blue, and alpha channels.
///
/// Used as the intermediate representation for image data before
/// ASCII art conversion. Each channel is stored as a `UInt8` (0-255).
public struct RGBA: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    /// Creates an opaque pixel with the given RGB values.
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = .max) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

// MARK: - Luminance

extension RGBA {

    /// The perceived luminance using ITU-R BT.601 coefficients.
    ///
    /// Returns a value in the range 0.0 (black) to 255.0 (white).
    public var luminance: Double {
        // `Double(Int(r))`, not `Double(r)`, and not a typo: Swift has no
        // `Double.init(UInt8)`, so the short spelling binds the generic
        // `init<T: BinaryInteger>` and — unspecialised, in a debug build —
        // calls it through a protocol witness. Three of those, on a property
        // that runs per PIXEL on the graphics path. Going via `Int` picks a
        // concrete initializer; the value is identical, since every byte is
        // exactly representable as an Int and as a Double.
        Double(Int(r)) * 0.299 + Double(Int(g)) * 0.587 + Double(Int(b)) * 0.114
    }
}

// MARK: - RGBAImage

/// A raw image stored as a flat array of RGBA pixels in row-major order.
///
/// This is the platform-independent representation produced by
/// `ImageLoader` implementations and consumed by `ASCIIConverter`.
public struct RGBAImage: Sendable {
    /// Image width in pixels.
    public let width: Int

    /// Image height in pixels.
    public let height: Int

    /// Row-major pixel data (`width * height` elements).
    public private(set) var pixels: [RGBA]

    /// Creates an image from dimensions and pixel data.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - pixels: Pixel data in row-major order. Must contain `width * height` elements.
    public init(width: Int, height: Int, pixels: [RGBA]) {
        precondition(pixels.count == width * height, "Pixel count must match width * height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

// MARK: - Pixel Access

extension RGBAImage {

    /// Returns the pixel at the given coordinates.
    ///
    /// - Parameters:
    ///   - x: Column (0-based, left to right).
    ///   - y: Row (0-based, top to bottom).
    /// - Returns: The RGBA pixel value.
    public func pixel(at x: Int, _ y: Int) -> RGBA {
        pixels[y * width + x]
    }

    /// Sets the pixel at the given coordinates.
    ///
    /// - Parameters:
    ///   - x: Column (0-based).
    ///   - y: Row (0-based).
    ///   - value: The new pixel value.
    public mutating func setPixel(at x: Int, _ y: Int, value: RGBA) {
        pixels[y * width + x] = value
    }

    /// Replaces every pixel with `transform(pixel)`, in place.
    ///
    /// One pass over the buffer rather than a `map` into a second one: this
    /// runs on the scaled image at conversion time, and an extra allocation the
    /// size of the render grid is the kind of thing that shows up in a profile
    /// of an image redrawn on every spinner tick.
    /// Through an unsafe buffer rather than an index loop: this runs once per
    /// non-true-colour conversion and again per mono recolouring, over a
    /// megapixel, and a debug build charges a bounds check and an exclusivity
    /// check for every subscript at both ends.
    public mutating func mapPixels(_ transform: (RGBA) -> RGBA) {
        pixels.withUnsafeMutableBufferPointer { buffer in
            for index in 0..<buffer.count { unsafe buffer[index] = unsafe transform(buffer[index]) }
        }
    }

    /// Quantises every pixel in place through `quantiser`'s loop — see
    /// `PixelQuantiser.apply(to:)` for why the loop lives there.
    mutating func quantise(with quantiser: PixelQuantiser) {
        quantiser.apply(to: &pixels)
    }

    /// Adds an error value to the pixel at the given coordinates (for dithering).
    ///
    /// Clamps each channel to the valid 0-255 range.
    ///
    /// - Parameters:
    ///   - x: Column.
    ///   - y: Row.
    ///   - rError: Red channel error.
    ///   - gError: Green channel error.
    ///   - bError: Blue channel error.
    public mutating func addError(at x: Int, _ y: Int, rError: Int16, gError: Int16, bError: Int16) {
        let index = y * width + x
        let pixel = pixels[index]
        // The alpha is kept: this rebuilds the pixel, and `RGBA(r:g:b:)`
        // would default it to opaque — the defect that made every dithered
        // picture with transparency come out solid.
        pixels[index] = RGBA(
            r: UInt8(clamping: Int16(pixel.r) + rError),
            g: UInt8(clamping: Int16(pixel.g) + gError),
            b: UInt8(clamping: Int16(pixel.b) + bError),
            a: pixel.a
        )
    }
}

// MARK: - Image Scaling

extension RGBAImage {
    /// An image of `width` × `height` pixels from the straight-alpha RGBA bytes
    /// at `bytes`, row by row: what stb_image hands back.
    init(rgbaBytes bytes: UnsafePointer<UInt8>, width: Int, height: Int) {
        let count = width * height
        var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: count)
        for index in 0..<count {
            let offset = index * 4
            pixels[index] = unsafe RGBA(r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}

extension RGBAImage {

    /// Returns a scaled copy using nearest-neighbor interpolation.
    ///
    /// - Parameters:
    ///   - targetWidth: The desired width.
    ///   - targetHeight: The desired height.
    /// - Returns: A new image with the specified dimensions — or an empty
    ///   image when the target is empty, or when this image is: there is no
    ///   pixel to sample. (An empty image is an ordinary value here; a decode
    ///   can succeed with one.)
    public func scaled(to targetWidth: Int, _ targetHeight: Int) -> RGBAImage {
        guard targetWidth > 0, targetHeight > 0, width > 0, height > 0 else {
            return RGBAImage(width: 0, height: 0, pixels: [])
        }

        var result = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: targetWidth * targetHeight)

        for y in 0..<targetHeight {
            let srcY = y * height / targetHeight
            for x in 0..<targetWidth {
                let srcX = x * width / targetWidth
                result[y * targetWidth + x] = pixel(at: srcX, srcY)
            }
        }

        return RGBAImage(width: targetWidth, height: targetHeight, pixels: result)
    }

    /// Returns a copy resampled to `targetWidth` × `targetHeight` pixels: the
    /// one resampler every picture is resized by (`PixelResampler`).
    ///
    /// Along an axis that shrinks, each pixel is the average of every source
    /// pixel it covers, each weighted by how much of it is covered, so nothing
    /// is skipped however large the source: a one-pixel line still counts, and
    /// the picture's total is kept. Along an axis that grows (or keeps its
    /// length), each pixel is read bilinearly from the two source pixels
    /// nearest `x × width / targetWidth`. Each axis on its own: a picture
    /// squeezed across and stretched down averages across and interpolates
    /// down.
    ///
    /// The average is weighted by coverage (premultiplied), in the encoded
    /// sRGB values the pixels hold: a transparent pixel's colour, which means
    /// nothing, lends none to its neighbours, and a pixel with no coverage at
    /// all comes out `(0, 0, 0, 0)`.
    ///
    /// It replaced a bilinear read that took 2 × 2 source pixels per target
    /// pixel however far it shrank (and so aliased fine detail) and a box
    /// reduction by whole factors that files were given ahead of it: one step
    /// for every picture, the owner ruled on 2026-11-22 (O-36 (a)).
    ///
    /// - Parameters:
    ///   - targetWidth: The desired width.
    ///   - targetHeight: The desired height.
    /// - Returns: The resampled image — or an empty image when the target is
    ///   empty, or when this image is: there is nothing to read.
    public func resampled(to targetWidth: Int, _ targetHeight: Int) -> RGBAImage {
        guard targetWidth > 0, targetHeight > 0, width > 0, height > 0 else {
            return RGBAImage(width: 0, height: 0, pixels: [])
        }
        // The resampler reads and writes RGBA as bytes, four to a pixel in the order
        // `r, g, b, a`: what `RGBA`'s four stored `UInt8`s are laid out as.
        assert(MemoryLayout<RGBA>.stride == 4 && MemoryLayout<RGBA>.offset(of: \.a) == 3, "RGBA is not four bytes")
        let count = targetWidth * targetHeight
        let resampled = unsafe [RGBA](unsafeUninitializedCapacity: count) { destination, initialized in
            pixels.withUnsafeBytes { source in
                unsafe PixelResampler.resample(
                    source, bytesPerPixel: 4, size: (width, height), to: (targetWidth, targetHeight),
                    window: (0..<targetWidth, 0..<targetHeight), enlargement: .bilinear,
                    into: UnsafeMutableRawBufferPointer(destination))
            }
            initialized = count
        }
        return RGBAImage(width: targetWidth, height: targetHeight, pixels: resampled)
    }

    /// This image at `1 / factor` of its size each way, rounded down — what a
    /// picture decoded whole is kept at when it is drawn smaller
    /// (`PlatformImageLoader.reduction(of:covering:)`) — resampled by
    /// ``resampled(to:_:)``. A `factor` of 1 or less, or an image smaller than
    /// `factor` on either axis, returns `self`.
    package func reduced(by factor: Int) -> RGBAImage {
        guard factor > 1, width >= factor, height >= factor else { return self }
        return resampled(to: width / factor, height / factor)
    }

    /// This image with its LOCAL contrast raised — an unsharp mask.
    ///
    /// Every pixel is pushed away from the average of the area around it by
    /// `amount` times the difference: `p + amount × (p − blur(p))`. A flat
    /// region IS its own average and does not move; a pixel on one side of a
    /// boundary moves further from the pixels on the other side. So it sharpens
    /// boundaries and leaves smooth expanses alone, which is the opposite of
    /// what a global contrast curve does — that one moves every pixel of a
    /// given tone, wherever it sits.
    ///
    /// The radii are the caller's because the scale is the point. A picture
    /// scaled to a render's pixel grid is about to be reduced again to one
    /// glyph per CELL, so a lift measured in single pixels of a 5×10 sub-cell
    /// grid averages back out before any character is chosen. Passing the
    /// sub-cell grid makes the neighbourhood about a cell across whatever the
    /// renderer's grid is, so the same `amount` means the same thing for a
    /// luminance ramp, half-blocks, braille and a shape match alike.
    ///
    /// Each channel is sharpened on its own, so a boundary between two
    /// equally-bright colours sharpens too; alpha is left alone, its edges
    /// being the picture's outline rather than anything inside it.
    ///
    /// - Parameters:
    ///   - amount: How far to push. `0` (or less) returns `self`, as does an
    ///     amount that is not a finite number; around `0.6` is a visible lift
    ///     and `2` is heavy-handed.
    ///   - radiusX: Half the neighbourhood's width, in pixels. Clamped to ≥ 1.
    ///   - radiusY: Half its height. Clamped to ≥ 1.
    public func sharpened(amount: Double, radiusX: Int = 1, radiusY: Int = 1) -> RGBAImage {
        guard amount > 0, amount.isFinite, width > 0, height > 0 else { return self }
        let spanX = max(1, radiusX)
        let spanY = max(1, radiusY)
        let rowBlur = horizontallyAveraged(span: spanX)
        var result = pixels
        // Three scalars, not a three-element array. The arithmetic below is
        // unchanged and the output is byte-identical; what is gone is two heap
        // allocations PER PIXEL — `[here.r, here.g, here.b]` and its copy —
        // which on a megapixel image is two million of them, and which a debug
        // build does not optimise away. This is the difference between an
        // unsharp mask being a knob and being a pause.
        //
        // ROW-major, and not because rows read better: the running sum is a
        // COLUMN's, so the obvious nest walks one column at a time, and every
        // step of it jumps `width` pixels through three arrays that together
        // are 26 MB for the graphics path's grid — a cache line fetched for one
        // triple of the two-and-two-thirds it carries, and evicted long before
        // the next column asks for the rest. Keeping one running-sum triple per
        // COLUMN, in a scratch as wide as the image (23 KB at 960 pixels, which
        // stays resident), lets the walk go along the rows instead, so
        // `rowBlur`, `pixels` and `result` are all read and written in address
        // order.
        //
        // Still bit-exact, and that is why it is written this way rather than
        // as a prefix-sum difference: each column is primed over rows
        // `0...min(height - 1, spanY)` and then slid down one row at a time, in
        // that order, so every column accumulates exactly the additions and
        // subtractions it did before, in exactly the same sequence.
        // Interleaving independent columns changes no column's arithmetic — a
        // reassociated sum would, and `.rounded()` turns a last-bit difference
        // into a different pixel. `SharpeningEquivalenceTests` checks it.
        var running = [Double](repeating: 0, count: width * 3)
        pixels.withUnsafeBufferPointer { source in
            rowBlur.withUnsafeBufferPointer { blur in
                running.withUnsafeMutableBufferPointer { sums in
                    result.withUnsafeMutableBufferPointer { out in
                        for y in 0...min(height - 1, spanY) {
                            let row = y * width
                            for x in 0..<width {
                                let slot = (row + x) * 3
                                let into = x * 3
                                unsafe sums[into] += blur[slot]
                                unsafe sums[into + 1] += blur[slot + 1]
                                unsafe sums[into + 2] += blur[slot + 2]
                            }
                        }
                        for y in 0..<height {
                            let low = max(0, y - spanY)
                            let high = min(height - 1, y + spanY)
                            let count = Double(high - low + 1)
                            let row = y * width
                            // −1 for "no row to drop" / "no row to add": the
                            // condition is the same for every pixel of the row,
                            // so it is asked once per row rather than per pixel.
                            let dropped = y - spanY >= 0 ? (y - spanY) * width : -1
                            let added = y + spanY + 1 < height ? (y + spanY + 1) * width : -1
                            for x in 0..<width {
                                let into = x * 3
                                let index = row + x
                                let here = unsafe source[index]
                                unsafe out[index] = unsafe RGBA(
                                    r: Self.lifted(here.r, blurred: sums[into] / count, amount: amount),
                                    g: Self.lifted(here.g, blurred: sums[into + 1] / count, amount: amount),
                                    b: Self.lifted(here.b, blurred: sums[into + 2] / count, amount: amount),
                                    a: here.a)
                                if dropped >= 0 {
                                    let gone = (dropped + x) * 3
                                    unsafe sums[into] -= blur[gone]
                                    unsafe sums[into + 1] -= blur[gone + 1]
                                    unsafe sums[into + 2] -= blur[gone + 2]
                                }
                                if added >= 0 {
                                    let fresh = (added + x) * 3
                                    unsafe sums[into] += blur[fresh]
                                    unsafe sums[into + 1] += blur[fresh + 1]
                                    unsafe sums[into + 2] += blur[fresh + 2]
                                }
                            }
                        }
                    }
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: result)
    }

    /// One channel pushed away from its neighbourhood's average by `amount`
    /// times the difference — the unsharp mask, per channel.
    private static func lifted(_ value: UInt8, blurred: Double, amount: Double) -> UInt8 {
        // `Double(Int(value))`, not `Double(value)`, and not a typo: Swift has
        // no `Double.init(UInt8)`, so the short spelling binds the generic
        // `init<T: BinaryInteger>` and — unspecialised, in a debug build —
        // calls it through a protocol witness. Going via `Int` picks a concrete
        // initializer; the value is identical, every byte being exactly
        // representable as an Int and as a Double. Three of these run per PIXEL
        // of the sharpened picture.
        let original = Double(Int(value))
        // Held to a byte while still a `Double`: a finite amount of 1e18 lifts
        // a channel past what `Int(_:)` takes without trapping.
        return UInt8(min(255, max(0, (original + amount * (original - blurred)).rounded())))
    }

    /// Each pixel's three colour channels averaged across `2 × span + 1`
    /// columns, as `[r, g, b]` triples in row-major order — the first half of
    /// ``sharpened(amount:radiusX:radiusY:)``'s separable box blur.
    ///
    /// By a running sum, so the cost is O(pixels) rather than O(pixels × span):
    /// the shape grid's neighbourhood is 11 × 21 taps, which is not something to
    /// walk per pixel per channel. The window SHRINKS at the edges rather than
    /// repeating the border — either is defensible, and averaging only over
    /// pixels that exist keeps the outermost column from being pulled toward a
    /// value counted twice.
    private func horizontallyAveraged(span: Int) -> [Double] {
        var blurred = [Double](repeating: 0, count: pixels.count * 3)
        for y in 0..<height {
            let row = y * width
            var running = (r: 0.0, g: 0.0, b: 0.0)
            func take(_ index: Int, _ sign: Double) {
                let p = pixels[index]
                // `Double(Int(byte))`, not `Double(byte)`, and not a typo — the
                // reason is at `lifted(_:blurred:amount:)`. Three per pixel
                // here too, and the window calls it twice over: once for the
                // column it takes in, once for the one it lets go.
                running.r += sign * Double(Int(p.r))
                running.g += sign * Double(Int(p.g))
                running.b += sign * Double(Int(p.b))
            }
            // Prime the window on the first column, then slide it across.
            for x in 0...min(width - 1, span) { take(row + x, 1) }
            for x in 0..<width {
                let count = Double(min(width - 1, x + span) - max(0, x - span) + 1)
                let slot = (row + x) * 3
                blurred[slot] = running.r / count
                blurred[slot + 1] = running.g / count
                blurred[slot + 2] = running.b / count
                if x - span >= 0 { take(row + x - span, -1) }
                if x + span + 1 < width { take(row + x + span + 1, 1) }
            }
        }
        return blurred
    }
}
