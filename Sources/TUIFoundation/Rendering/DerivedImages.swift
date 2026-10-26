//  🖥️ TUI — A Terminal UI framework for Swift
//  DerivedImages.swift
//
//  Copies of the pictures TUI has put in the terminal, changed for what lies
//  over them — frosted under glass, faded, veiled — transmitted once each, so
//  the cells under a translucent layer can draw a picture the layer has
//  already been applied to (`Terminal graphics protocols.md` §14).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// How a derived copy differs from its picture: blurred or not, then mixed
/// toward a colour by an amount.
///
/// The amount is in 64ths, so a layer whose alpha moves — a fade, a breath —
/// asks for at most 65 copies rather than one a frame (and the store keeps
/// only a few of those, ``DerivedImages/limit``).
package struct ImageTransform: Hashable, Sendable {
    /// Whether the copy is blurred over about a cell, as a material frosts.
    package var blurs: Bool
    /// The colour mixed in, as 0xRRGGBB.
    package var toward: UInt32
    /// How much of `toward` is mixed in, in 64ths.
    package var amount: UInt8

    /// A transform mixing `colour` in by `fraction`, quantised to 64ths;
    /// blurred where `blurs`.
    package init(blurs: Bool, toward colour: (red: UInt8, green: UInt8, blue: UInt8), fraction: Double) {
        self.blurs = blurs
        toward = UInt32(colour.red) << 16 | UInt32(colour.green) << 8 | UInt32(colour.blue)
        amount = UInt8((min(1, max(0, fraction)) * 64).rounded())
    }
}

/// The derived copies of the store's pictures, and the small copy of each
/// picture they are made from.
///
/// **Small, on purpose.** A copy that is blurred or tinted has nothing a
/// terminal's own scaling loses, and both Ghostty and iTerm2 scale a copy at
/// one pixel a cell as smoothly as one at full resolution (measured 2026-10-26,
/// `frost_over_image_card.py --derived-pixels 1`). So each picture keeps
/// ``pixelsAcross`` × ``pixelsDown`` pixels a cell — a few kilobytes — and a
/// derived copy costs as much to transmit.
struct DerivedImages {
    /// Pixels kept across one cell of a picture.
    static let pixelsAcross = 2
    /// Pixels kept down one cell: a cell is about twice as tall as wide, so
    /// these are square.
    static let pixelsDown = 4
    /// The derived copies kept of one picture. Past it, the oldest goes.
    static let limit = 8

    /// The most bytes of a picture's own pixels kept to make its unblurred
    /// copies from (a fade, a veil), whose detail a small copy loses: a
    /// photograph a screen wide. A larger picture's copies are made from its
    /// small copy, soft rather than unbounded.
    static let fullPixelLimit = 4 << 20

    /// A picture's small copy, as RGBA bytes, and its derived copies.
    private struct Source {
        let columns: Int
        let rows: Int
        let pixels: [UInt8]
        /// The picture's own pixels, as RGBA, where they fit ``DerivedImages/fullPixelLimit``.
        var full: (bytes: [UInt8], width: Int, height: Int)?
        var copies: [ImageTransform: Copy] = [:]
        /// The transforms in the order they were made, oldest first.
        var order: [ImageTransform] = []

        var width: Int { columns * DerivedImages.pixelsAcross }
        var height: Int { rows * DerivedImages.pixelsDown }
    }

    /// One derived copy in the terminal.
    private struct Copy {
        let id: KittyGraphics.ImageID
        let pixels: [UInt8]
    }

    private var sources: [KittyGraphics.ImageID: Source] = [:]
    /// Every derived copy's id, for the store's id search to skip.
    private(set) var ids: Set<KittyGraphics.ImageID> = []

    // MARK: - Pictures

    /// Keeps a small copy of picture `id`, from the pixels it was transmitted
    /// with, to derive copies of it from.
    mutating func remember(
        _ id: KittyGraphics.ImageID, columns: Int, rows: Int,
        pixels: (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int)
    ) {
        var source = Source(
            columns: columns, rows: rows,
            pixels: Self.downsampled(
                pixels, to: (columns * Self.pixelsAcross, rows * Self.pixelsDown)))
        if pixels.width * pixels.height * 4 <= Self.fullPixelLimit {
            source.full = (Self.rgba(pixels), pixels.width, pixels.height)
        }
        sources[id] = source
    }

    /// `pixels` as RGBA: as they are, or opaque where they had no alpha.
    static func rgba(_ pixels: (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int)) -> [UInt8] {
        guard pixels.format.stride == 3 else { return pixels.bytes }
        var out = [UInt8]()
        out.reserveCapacity(pixels.width * pixels.height * 4)
        for at in stride(from: 0, to: min(pixels.bytes.count, pixels.width * pixels.height * 3), by: 3) {
            out += [pixels.bytes[at], pixels.bytes[at + 1], pixels.bytes[at + 2], 255]
        }
        return out
    }

    /// Forgets picture `id` and every copy derived from it, returning the
    /// copies' ids for the store to delete from the terminal.
    @discardableResult
    mutating func forget(_ id: KittyGraphics.ImageID) -> [KittyGraphics.ImageID] {
        guard let source = sources.removeValue(forKey: id) else { return [] }
        let gone = source.copies.values.map(\.id)
        ids.subtract(gone)
        return gone
    }

    /// Fits picture `id`'s small copy to a new box, `columns` × `rows`, and
    /// drops its copies, which were placed in the old one.
    mutating func resize(_ id: KittyGraphics.ImageID, columns: Int, rows: Int) {
        guard let source = sources[id] else { return }
        ids.subtract(source.copies.values.map(\.id))
        var resized = Source(
            columns: columns, rows: rows,
            pixels: Self.downsampled(
                (source.pixels, .rgba, source.width, source.height),
                to: (columns * Self.pixelsAcross, rows * Self.pixelsDown)))
        // The same picture in a new box: its own pixels still are its pixels.
        resized.full = source.full
        sources[id] = resized
    }

    /// The ids of picture `id`'s copies.
    func copyIDs(of id: KittyGraphics.ImageID) -> [KittyGraphics.ImageID] {
        sources[id]?.copies.values.map(\.id).sorted() ?? []
    }

    // MARK: - Copies

    /// The id of the copy of picture `id` changed by `transform`, if the
    /// terminal has it.
    func existingCopy(of id: KittyGraphics.ImageID, by transform: ImageTransform) -> KittyGraphics.ImageID? {
        sources[id]?.copies[transform]?.id
    }

    /// Makes the copy of picture `id` changed by `transform`, under `copyID`,
    /// and returns the escapes that put it in the terminal — a delete first,
    /// when making it pushes the oldest copy out. `nil` where the picture is
    /// unknown.
    ///
    /// The id is the caller's, claimed before this is called: the store's
    /// search for a free id reads ``ids``, and reading them from inside a
    /// mutation of this value is an overlapping access.
    mutating func make(
        of id: KittyGraphics.ImageID, by transform: ImageTransform, as copyID: KittyGraphics.ImageID
    ) -> String? {
        guard var source = sources[id] else { return nil }
        var escapes = ""
        if source.order.count >= Self.limit, let oldest = source.order.first {
            source.order.removeFirst()
            if let gone = source.copies.removeValue(forKey: oldest) {
                ids.remove(gone.id)
                escapes += KittyGraphics.delete(id: gone.id)
            }
        }
        let pixels = Self.applying(transform, to: source.pixels, width: source.width, height: source.height)
        // An unblurred copy keeps the picture's detail, from its own pixels where
        // they were kept; a blurred one has none to keep, and the small copy is it.
        if !transform.blurs, let full = source.full {
            escapes += KittyGraphics.transmit(
                pixels: Self.applying(transform, to: full.bytes, width: full.width, height: full.height), format: .rgba,
                width: full.width, height: full.height, id: copyID, compressed: KittyGraphics.isCompressionSupported)
        } else {
            escapes += KittyGraphics.transmit(
                pixels: pixels, format: .rgba, width: source.width, height: source.height, id: copyID,
                compressed: KittyGraphics.isCompressionSupported)
        }
        escapes += KittyGraphics.placement(id: copyID, columns: source.columns, rows: source.rows)
        source.copies[transform] = Copy(id: copyID, pixels: pixels)
        source.order.append(transform)
        ids.insert(copyID)
        sources[id] = source
        return escapes
    }

    /// The average colour of cell (`column`, `row`) of picture `id` changed by
    /// `transform`: what a glyph over that cell is drawn on. `nil` where the
    /// picture or its copy is unknown — make it first (``make(of:by:as:)``).
    func average(
        of id: KittyGraphics.ImageID, by transform: ImageTransform, column: Int, row: Int
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard let source = sources[id], let copy = source.copies[transform],
            (0..<source.columns).contains(column), (0..<source.rows).contains(row)
        else { return nil }
        var sums = (0, 0, 0)
        for y in (row * Self.pixelsDown)..<((row + 1) * Self.pixelsDown) {
            for x in (column * Self.pixelsAcross)..<((column + 1) * Self.pixelsAcross) {
                let at = (y * source.width + x) * 4
                sums.0 += Int(copy.pixels[at])
                sums.1 += Int(copy.pixels[at + 1])
                sums.2 += Int(copy.pixels[at + 2])
            }
        }
        let count = Self.pixelsAcross * Self.pixelsDown
        return (UInt8(sums.0 / count), UInt8(sums.1 / count), UInt8(sums.2 / count))
    }

    // MARK: - Pixels

    /// `pixels` box-filtered to `size`, as RGBA.
    static func downsampled(
        _ pixels: (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int),
        to size: (width: Int, height: Int)
    ) -> [UInt8] {
        let stride = pixels.format.stride
        var out = [UInt8](repeating: 0, count: size.width * size.height * 4)
        guard pixels.width > 0, pixels.height > 0, size.width > 0, size.height > 0,
            pixels.bytes.count >= pixels.width * pixels.height * stride
        else { return out }
        for y in 0..<size.height {
            let top = y * pixels.height / size.height
            let bottom = max(top + 1, (y + 1) * pixels.height / size.height)
            for x in 0..<size.width {
                let left = x * pixels.width / size.width
                let right = max(left + 1, (x + 1) * pixels.width / size.width)
                var sums = (0, 0, 0, 0)
                for sy in top..<bottom {
                    for sx in left..<right {
                        let at = (sy * pixels.width + sx) * stride
                        sums.0 += Int(pixels.bytes[at])
                        sums.1 += Int(pixels.bytes[at + 1])
                        sums.2 += Int(pixels.bytes[at + 2])
                        sums.3 += stride == 4 ? Int(pixels.bytes[at + 3]) : 255
                    }
                }
                let count = (bottom - top) * (right - left)
                let at = (y * size.width + x) * 4
                out[at] = UInt8(sums.0 / count)
                out[at + 1] = UInt8(sums.1 / count)
                out[at + 2] = UInt8(sums.2 / count)
                out[at + 3] = UInt8(sums.3 / count)
            }
        }
        return out
    }

    /// `pixels` (RGBA, `width` × `height`) changed by `transform`: blurred over
    /// about a cell — a box blur run twice each way, which is close to a
    /// Gaussian — then mixed toward its colour in encoded sRGB, as TUI mixes.
    /// Alpha is left alone, so a transparent picture stays transparent.
    static func applying(_ transform: ImageTransform, to pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = pixels
        if transform.blurs {
            for _ in 0..<2 {
                out = boxBlurred(out, width: width, height: height, radius: (pixelsAcross, 0))
                out = boxBlurred(out, width: width, height: height, radius: (0, pixelsDown))
            }
        }
        guard transform.amount > 0 else { return out }
        let fraction = Double(transform.amount) / 64
        // One channel of the colour, by its shift: a function rather than three
        // shifts in one array literal, which the type-check guard times out on.
        func channel(_ shift: UInt32) -> Double { Double((transform.toward >> shift) & 0xFF) }
        let toward: [Double] = [channel(16), channel(8), channel(0)]
        for at in stride(from: 0, to: out.count, by: 4) {
            for channel in 0..<3 {
                let mixed = Double(out[at + channel]) * (1 - fraction) + toward[channel] * fraction
                out[at + channel] = UInt8(min(255, max(0, mixed.rounded())))
            }
        }
        return out
    }

    /// One pass of a box blur `radius` pixels across or down, the edges held.
    private static func boxBlurred(
        _ pixels: [UInt8], width: Int, height: Int, radius: (across: Int, down: Int)
    ) -> [UInt8] {
        var out = pixels
        for y in 0..<height {
            for x in 0..<width {
                var sums = (0, 0, 0, 0)
                var count = 0
                for dy in -radius.down...radius.down {
                    for dx in -radius.across...radius.across {
                        let sx = min(width - 1, max(0, x + dx))
                        let sy = min(height - 1, max(0, y + dy))
                        let at = (sy * width + sx) * 4
                        sums.0 += Int(pixels[at])
                        sums.1 += Int(pixels[at + 1])
                        sums.2 += Int(pixels[at + 2])
                        sums.3 += Int(pixels[at + 3])
                        count += 1
                    }
                }
                let at = (y * width + x) * 4
                out[at] = UInt8(sums.0 / count)
                out[at + 1] = UInt8(sums.1 / count)
                out[at + 2] = UInt8(sums.2 / count)
                out[at + 3] = UInt8(sums.3 / count)
            }
        }
        return out
    }
}
