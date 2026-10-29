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
import TUIStyling

/// How a derived copy differs from its picture: blurred or not, then mixed
/// toward one colour after another, or recoloured as a colour effect
/// recolours cells.
///
/// Each mix's amount is in 64ths, so a layer whose alpha moves — a fade, a
/// breath — asks for at most 65 copies rather than one a frame (and the store
/// keeps only a few of those, ``DerivedImages/limit``). Mixes chain because
/// layers stack: a faded picture behind a sheet is a fade and then a veil, a
/// copy of a copy, made from the picture itself.
package struct ImageTransform: Hashable, Sendable {
    /// One step of the change to each pixel's colour: a mix toward a colour,
    /// toward the pixel's own grey (``greys``), or a colour effect's
    /// recolouring (``recolour``).
    package struct Mix: Hashable, Sendable {
        /// The colour mixed in, as 0xRRGGBB.
        package var toward: UInt32
        /// How much of it is mixed in, in 64ths.
        package var amount: UInt8
        /// Whether the mix is in linear light, as `Color.compositing(_:over:)`
        /// mixes — the modal veil's — rather than in encoded sRGB, as
        /// `Color.opacity(_:over:)` and every fade do.
        package var linearLight: Bool
        /// Whether each pixel is mixed toward its own grey
        /// (`Color.saturated(red:green:blue:keeping:)`) instead of toward
        /// `toward`, which is then unused: the colour the modal veil takes out.
        package var greys = false
        /// The colour effect each pixel is recoloured by instead of mixed,
        /// where there is one: `toward`, `amount` and `greys` are then unused.
        package var recolour: Recolour?
    }

    /// Whether the copy is blurred over about a cell, as a material frosts.
    package var blurs: Bool
    /// The mixes, in order, after the blur.
    package var mixes: [Mix]

    /// A transform mixing `colour` in by `fraction`, quantised to 64ths;
    /// blurred where `blurs`, and mixed in linear light where `linearLight`.
    package init(
        blurs: Bool, toward colour: (red: UInt8, green: UInt8, blue: UInt8), fraction: Double, linearLight: Bool = false
    ) {
        self.blurs = blurs
        let amount = UInt8((min(1, max(0, fraction)) * 64).rounded())
        let toward = UInt32(colour.red) << 16 | UInt32(colour.green) << 8 | UInt32(colour.blue)
        mixes = amount > 0 ? [Mix(toward: toward, amount: amount, linearLight: linearLight)] : []
    }

    /// A transform taking `fraction` of each pixel's colour out, toward the
    /// grey it reads as, quantised to 64ths.
    package init(greying fraction: Double) {
        blurs = false
        let amount = UInt8((min(1, max(0, fraction)) * 64).rounded())
        mixes = amount > 0 ? [Mix(toward: 0, amount: amount, linearLight: false, greys: true)] : []
    }

    /// A transform recolouring each pixel by `recolour`.
    package init(recolouring recolour: Recolour) {
        blurs = false
        mixes = [Mix(toward: 0, amount: 64, linearLight: false, recolour: recolour)]
    }

    /// Whether the copy would be the picture itself.
    package var isIdentity: Bool { !blurs && mixes.isEmpty }

    /// This transform, then `next`: blurred if either blurs, and mixed by this
    /// one's mixes and then by `next`'s.
    package func followed(by next: Self) -> Self {
        var both = self
        both.blurs = blurs || next.blurs
        both.mixes += next.mixes
        return both
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
        /// Its small copy's pixels a cell: ``DerivedImages/pixelsAcross`` ×
        /// ``DerivedImages/pixelsDown``, or a frost backdrop's own
        /// (`MaterialFrostResolution`).
        var across = DerivedImages.pixelsAcross
        var down = DerivedImages.pixelsDown
        let pixels: [UInt8]
        /// The picture's own pixels, as RGBA, where they fit ``DerivedImages/fullPixelLimit``.
        var full: (bytes: [UInt8], width: Int, height: Int)?
        var copies: [ImageTransform: Copy] = [:]
        /// The transforms in the order they were made, oldest first.
        var order: [ImageTransform] = []

        var width: Int { columns * across }
        var height: Int { rows * down }
    }

    /// One derived copy in the terminal.
    private struct Copy {
        let id: KittyGraphics.ImageID
        let pixels: [UInt8]
        /// The size it was sent at: the small copy's, or the picture's own
        /// where an unblurred copy was made from its kept pixels.
        let sentWidth: Int
        let sentHeight: Int
    }

    private var sources: [KittyGraphics.ImageID: Source] = [:]
    /// Each derived copy's picture and transform, by the copy's id: so a copy
    /// can be copied again — a fade under a veil — from the picture itself.
    private var origins: [KittyGraphics.ImageID: (source: KittyGraphics.ImageID, transform: ImageTransform)] = [:]

    /// Whether `id` is a derived copy's, for the store's id search to skip.
    func isCopy(_ id: KittyGraphics.ImageID) -> Bool { origins[id] != nil }

    /// The picture copy `id` was made from, and how.
    func origin(of id: KittyGraphics.ImageID) -> (source: KittyGraphics.ImageID, transform: ImageTransform)? {
        origins[id]
    }

    // MARK: - Pictures

    /// Keeps a small copy of picture `id`, from the pixels it was transmitted
    /// with, to derive copies of it from: `pixelsPerCell` a cell, by default
    /// ``pixelsAcross`` × ``pixelsDown``.
    mutating func remember(
        _ id: KittyGraphics.ImageID, columns: Int, rows: Int,
        pixels: (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int),
        pixelsPerCell: (across: Int, down: Int) = (Self.pixelsAcross, Self.pixelsDown)
    ) {
        var source = Source(
            columns: columns, rows: rows, across: pixelsPerCell.across, down: pixelsPerCell.down,
            pixels: Self.downsampled(
                pixels, to: (columns * pixelsPerCell.across, rows * pixelsPerCell.down)))
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
        for copy in gone { origins.removeValue(forKey: copy) }
        return gone
    }

    /// Fits picture `id`'s small copy to a new box, `columns` × `rows`, and
    /// drops its copies, which were placed in the old one.
    mutating func resize(_ id: KittyGraphics.ImageID, columns: Int, rows: Int) {
        guard let source = sources[id] else { return }
        for copy in source.copies.values { origins.removeValue(forKey: copy.id) }
        var resized = Source(
            columns: columns, rows: rows, across: source.across, down: source.down,
            pixels: Self.downsampled(
                (source.pixels, .rgba, source.width, source.height),
                to: (columns * source.across, rows * source.down)))
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
    /// terminal has it — moved to the back of the line ``make(of:by:as:)``
    /// pushes the oldest out of, so a copy in use every frame is not the one
    /// another's making deletes.
    mutating func existingCopy(of id: KittyGraphics.ImageID, by transform: ImageTransform) -> KittyGraphics.ImageID? {
        guard let copy = sources[id]?.copies[transform] else { return nil }
        if sources[id]?.order.last != transform {
            sources[id]?.order.removeAll { $0 == transform }
            sources[id]?.order.append(transform)
        }
        return copy.id
    }

    /// Makes the copy of picture `id` changed by `transform`, under `copyID`,
    /// and returns the escapes that put it in the terminal, and the id of the
    /// copy making it pushed out, if it did. `nil` where the picture is
    /// unknown.
    ///
    /// The pushed-out copy is the caller's to delete, after the frame's cells
    /// (`TerminalImageStore.takeDeletes()`): a cell may still name it until
    /// they are written.
    ///
    /// The id is the caller's, claimed before this is called: the store's
    /// search for a free id reads ``ids``, and reading them from inside a
    /// mutation of this value is an overlapping access.
    mutating func make(
        of id: KittyGraphics.ImageID, by transform: ImageTransform, as copyID: KittyGraphics.ImageID
    ) -> (escapes: String, evicted: KittyGraphics.ImageID?)? {
        guard var source = sources[id] else { return nil }
        var escapes = ""
        var evicted: KittyGraphics.ImageID?
        if source.order.count >= Self.limit, let oldest = source.order.first {
            source.order.removeFirst()
            if let gone = source.copies.removeValue(forKey: oldest) {
                origins.removeValue(forKey: gone.id)
                evicted = gone.id
            }
        }
        let pixels = Self.applying(
            transform, to: source.pixels, width: source.width, height: source.height,
            pixelsPerCell: (source.across, source.down))
        // An unblurred copy keeps the picture's detail, from its own pixels where
        // they were kept; a blurred one has none to keep, and the small copy is it.
        let sent: (width: Int, height: Int)
        if !transform.blurs, let full = source.full {
            escapes += KittyGraphics.transmit(
                pixels: Self.applying(transform, to: full.bytes, width: full.width, height: full.height), format: .rgba,
                width: full.width, height: full.height, id: copyID, compressed: KittyGraphics.isCompressionSupported)
            sent = (full.width, full.height)
        } else {
            escapes += KittyGraphics.transmit(
                pixels: pixels, format: .rgba, width: source.width, height: source.height, id: copyID,
                compressed: KittyGraphics.isCompressionSupported)
            sent = (source.width, source.height)
        }
        escapes += KittyGraphics.placement(id: copyID, columns: source.columns, rows: source.rows)
        source.copies[transform] = Copy(id: copyID, pixels: pixels, sentWidth: sent.width, sentHeight: sent.height)
        source.order.append(transform)
        origins[copyID] = (id, transform)
        sources[id] = source
        return (escapes, evicted)
    }

    /// The box copy `copyID` is placed in, in cells: its picture's.
    func box(ofCopy copyID: KittyGraphics.ImageID) -> (columns: Int, rows: Int)? {
        guard let origin = origins[copyID], let source = sources[origin.source] else { return nil }
        return (source.columns, source.rows)
    }

    /// The rectangle of copy `copyID`'s pixels, as it was sent, that its cell
    /// (`column`, `row`) draws: what a classic placement crops it to, to lay
    /// that cell of it under a glyph (`PictureUnderTextMarker`). Edges at
    /// `column × width / columns`, rounded down, so a cell's right edge is the
    /// next one's left and a run's rectangles tile. `nil` for an unknown copy
    /// or a cell outside it.
    func pixelRect(
        ofCopy copyID: KittyGraphics.ImageID, column: Int, row: Int
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let origin = origins[copyID], let source = sources[origin.source],
            let copy = source.copies[origin.transform],
            (0..<source.columns).contains(column), (0..<source.rows).contains(row)
        else { return nil }
        let left = column * copy.sentWidth / source.columns
        let right = (column + 1) * copy.sentWidth / source.columns
        let top = row * copy.sentHeight / source.rows
        let bottom = (row + 1) * copy.sentHeight / source.rows
        guard right > left, bottom > top else { return nil }
        return (left, top, right - left, bottom - top)
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
        for y in (row * source.down)..<((row + 1) * source.down) {
            for x in (column * source.across)..<((column + 1) * source.across) {
                let at = (y * source.width + x) * 4
                sums.0 += Int(copy.pixels[at])
                sums.1 += Int(copy.pixels[at + 1])
                sums.2 += Int(copy.pixels[at + 2])
            }
        }
        let count = source.across * source.down
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

    /// `pixels` (RGBA, `width` × `height`, `pixelsPerCell` a cell) changed by
    /// `transform`: blurred over about a cell — a box blur run twice each way,
    /// which is close to a Gaussian — then mixed toward each of its colours in
    /// turn. Alpha is left alone, so a transparent picture stays transparent.
    static func applying(
        _ transform: ImageTransform, to pixels: [UInt8], width: Int, height: Int,
        pixelsPerCell: (across: Int, down: Int) = (pixelsAcross, pixelsDown)
    ) -> [UInt8] {
        var out = pixels
        if transform.blurs {
            for _ in 0..<2 {
                out = boxBlurred(out, width: width, height: height, radius: (max(1, pixelsPerCell.across), 0))
                out = boxBlurred(out, width: width, height: height, radius: (0, max(1, pixelsPerCell.down)))
            }
        }
        for mix in transform.mixes { apply(mix, to: &out) }
        return out
    }

    /// `pixels` (RGBA) mixed toward `mix`'s colour, or each pixel's own grey,
    /// by its amount.
    private static func apply(_ mix: ImageTransform.Mix, to out: inout [UInt8]) {
        if let recolour = mix.recolour {
            for at in stride(from: 0, to: out.count, by: 4) {
                // A pixel's colour, as the effect's arithmetic takes it: not ink.
                // swiftlint:disable:next framework_colour_literal
                let moved = recolour.applied(to: .rgb(out[at], out[at + 1], out[at + 2]))
                guard let rgb = moved.rgbComponents else { continue }
                (out[at], out[at + 1], out[at + 2]) = (rgb.red, rgb.green, rgb.blue)
            }
            return
        }
        let fraction = Double(mix.amount) / 64
        if mix.greys {
            for at in stride(from: 0, to: out.count, by: 4) {
                let moved = Color.saturated(
                    red: out[at], green: out[at + 1], blue: out[at + 2], keeping: 1 - fraction)
                (out[at], out[at + 1], out[at + 2]) = moved
            }
            return
        }
        // One channel of the colour, by its shift: a function rather than three
        // shifts in one array literal, which the type-check guard times out on.
        func channel(_ shift: UInt32) -> UInt8 { UInt8((mix.toward >> shift) & 0xFF) }
        let toward: [UInt8] = [channel(16), channel(8), channel(0)]
        if mix.linearLight {
            let towardLinear = toward.map(Color.linearChannel)
            for at in stride(from: 0, to: out.count, by: 4) {
                for channel in 0..<3 {
                    let mixed = Color.linearChannel(out[at + channel]) * (1 - fraction) + towardLinear[channel] * fraction
                    out[at + channel] = Color.encodedChannel(mixed)
                }
            }
            return
        }
        for at in stride(from: 0, to: out.count, by: 4) {
            for channel in 0..<3 {
                let mixed = Double(out[at + channel]) * (1 - fraction) + Double(toward[channel]) * fraction
                out[at + channel] = UInt8(min(255, max(0, mixed.rounded())))
            }
        }
    }

    /// `pixels` (RGBA, `width` × `height`, `pixelsPerCell` a cell) blurred as a
    /// material frosts a box `reach` cells either way: a box blur run twice
    /// each way, each half the reach, which is close to a Gaussian as wide as
    /// the box (`FrameBuffer.frostBackdrop`).
    static func frosted(
        _ pixels: [UInt8], width: Int, height: Int, reach: (columns: Int, rows: Int),
        pixelsPerCell: (across: Int, down: Int) = (pixelsAcross, pixelsDown)
    ) -> [UInt8] {
        let across = max(1, (reach.columns * pixelsPerCell.across + 1) / 2)
        let down = max(1, (reach.rows * pixelsPerCell.down + 1) / 2)
        var out = pixels
        for _ in 0..<2 {
            out = boxBlurred(out, width: width, height: height, radius: (across, 0))
            out = boxBlurred(out, width: width, height: height, radius: (0, down))
        }
        return out
    }

    /// Cell (`column`, `row`) of picture `id`, or of the copy `id` names, as
    /// `across` × `down` RGBA pixels, row by row — what a frost's backdrop takes
    /// for that cell — or `nil` for an unknown image or a cell outside it.
    ///
    /// Sampled from the finest pixels kept: a picture's own where they were
    /// kept, a copy's as it was made, else the small copy; each output pixel
    /// the mean of the pixels under it, as ``downsampled(_:to:)`` takes them,
    /// or the one it falls in where there are fewer pixels than asked for.
    func cellPixels(
        of id: KittyGraphics.ImageID, column: Int, row: Int, across: Int = pixelsAcross, down: Int = pixelsDown
    ) -> [UInt8]? {
        let source: Source
        let image: (bytes: [UInt8], width: Int, height: Int)
        if let known = sources[id] {
            source = known
            image = known.full ?? (known.pixels, known.width, known.height)
        } else if let origin = origins[id], let known = sources[origin.source],
            let copy = known.copies[origin.transform]
        {
            source = known
            image = (copy.pixels, known.width, known.height)
        } else {
            return nil
        }
        guard (0..<source.columns).contains(column), (0..<source.rows).contains(row), across > 0, down > 0,
            image.width > 0, image.height > 0
        else { return nil }
        // The whole image's pixel grid at `across` × `down` a cell; this cell's
        // part of it.
        let gridWidth = source.columns * across
        let gridHeight = source.rows * down
        var out: [UInt8] = []
        out.reserveCapacity(across * down * 4)
        for y in (row * down)..<((row + 1) * down) {
            let top = y * image.height / gridHeight
            let bottom = max(top + 1, (y + 1) * image.height / gridHeight)
            for x in (column * across)..<((column + 1) * across) {
                let left = x * image.width / gridWidth
                let right = max(left + 1, (x + 1) * image.width / gridWidth)
                var sums = (0, 0, 0, 0)
                for sy in top..<bottom {
                    for sx in left..<right {
                        let at = (sy * image.width + sx) * 4
                        sums.0 += Int(image.bytes[at])
                        sums.1 += Int(image.bytes[at + 1])
                        sums.2 += Int(image.bytes[at + 2])
                        sums.3 += Int(image.bytes[at + 3])
                    }
                }
                let count = (bottom - top) * (right - left)
                out += [UInt8(sums.0 / count), UInt8(sums.1 / count), UInt8(sums.2 / count), UInt8(sums.3 / count)]
            }
        }
        return out
    }

    /// One pass of a box blur `radius` pixels across or down, the edges held:
    /// each pixel the mean of the `2 × radius + 1` pixels around it, a pixel
    /// past an edge counting as the edge's.
    ///
    /// A running sum along each line — the window slid a pixel at a time, the
    /// pixel leaving it taken off and the one entering added — so a pixel
    /// costs the same whatever the radius, where summing each window afresh
    /// cost the radius again for every pixel. One of `radius`'s two is 0: the
    /// pass runs along the other.
    static func boxBlurred(
        _ pixels: [UInt8], width: Int, height: Int, radius: (across: Int, down: Int)
    ) -> [UInt8] {
        guard width > 0, height > 0 else { return pixels }
        var out = pixels
        let alongRows = radius.down == 0
        let reach = alongRows ? radius.across : radius.down
        guard reach > 0 else { return pixels }
        let count = 2 * reach + 1
        // A line's length, how many lines, and the strides between pixels on one
        // and between the starts of two, in bytes.
        let (length, lines) = alongRows ? (width, height) : (height, width)
        let (step, lineStep) = alongRows ? (4, width * 4) : (width * 4, 4)
        pixels.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { target in
                for line in 0..<lines {
                    let base = line * lineStep
                    func at(_ index: Int) -> Int { base + min(length - 1, max(0, index)) * step }
                    var sums = (0, 0, 0, 0)
                    for index in -reach...reach {
                        let pixel = at(index)
                        sums.0 += Int(source[pixel])
                        sums.1 += Int(source[pixel + 1])
                        sums.2 += Int(source[pixel + 2])
                        sums.3 += Int(source[pixel + 3])
                    }
                    for index in 0..<length {
                        let pixel = base + index * step
                        target[pixel] = UInt8(sums.0 / count)
                        target[pixel + 1] = UInt8(sums.1 / count)
                        target[pixel + 2] = UInt8(sums.2 / count)
                        target[pixel + 3] = UInt8(sums.3 / count)
                        let leaving = at(index - reach)
                        let entering = at(index + reach + 1)
                        sums.0 += Int(source[entering]) - Int(source[leaving])
                        sums.1 += Int(source[entering + 1]) - Int(source[leaving + 1])
                        sums.2 += Int(source[entering + 2]) - Int(source[leaving + 2])
                        sums.3 += Int(source[entering + 3]) - Int(source[leaving + 3])
                    }
                }
            }
        }
        return out
    }
}
