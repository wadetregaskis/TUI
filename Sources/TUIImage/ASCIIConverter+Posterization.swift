//  🖥️ TUI — A Terminal UI framework for Swift
//  ASCIIConverter+Posterization.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Posterization

extension ASCIIConverter {

    /// `image` reduced to ``posterizationLevels`` per channel — through the
    /// Floyd–Steinberg dither when ``dithering`` asks for one, a plain map
    /// otherwise — or `image` itself when no posterization is set.
    ///
    /// The one check both renderers make before any per-pixel work: unset, this
    /// returns its argument and touches no pixel. Set, it is a stage of its own,
    /// the last change to the PICTURE before the colour mode reads it, so a
    /// colour mode that quantises again (a palette, the grey ramp, mono) draws
    /// the posterized picture in its own colours, and its own dither spreads its
    /// own error on top.
    func posterized(_ image: RGBAImage) -> RGBAImage {
        guard let posterizationLevels else { return image }
        let levels = ChannelLevels(count: posterizationLevels)
        var pixels = image.pixels
        if dithering == .floydSteinberg {
            levels.dither(&pixels, width: image.width, height: image.height)
        } else {
            levels.apply(to: &pixels)
        }
        return RGBAImage(width: image.width, height: image.height, pixels: pixels)
    }
}

// MARK: - N levels a channel

/// `count` evenly spaced values per channel, black to white — `0` and `255`
/// always among them — and the two loops that reduce a picture to them.
///
/// Evenly in sRGB BYTES, unlike ``ASCIIPalette/shades(_:)``'s perceptual
/// spacing: this is the posterize of every photo editor, and its look — the
/// bands, and the primaries a two-level dither draws in — is the point of
/// asking for it. A palette of `count`³ entries would say the same thing, and
/// cost a nearest-colour search a pixel over as many as 4096 entries where a
/// table load does.
///
/// The error is carried per channel in sRGB, as the terminal's own palettes
/// carry theirs: the levels span the whole gamut, so there is no direction a
/// neighbour cannot make up and nothing to box the carry into.
struct ChannelLevels {
    /// For every byte, the level it rounds to.
    let table: [UInt8]

    /// `count` levels, clamped to `2...256`.
    init(count: Int) {
        let steps = min(255, max(1, count - 1))
        // A loop with its types stated: as a `map` closure the type-check guard
        // timed out on it (Linux and Windows lanes run the same limit).
        var table = [UInt8](repeating: 0, count: 256)
        for value in 0...255 {
            let level: Int = (value * steps + 127) / 255
            table[value] = UInt8((level * 255 + steps / 2) / steps)
        }
        self.table = table
    }

    /// `pixel` at its nearest level on each channel, its alpha untouched.
    func quantise(_ pixel: RGBA) -> RGBA {
        RGBA(
            r: table[Int(pixel.r)], g: table[Int(pixel.g)], b: table[Int(pixel.b)], a: pixel.a)
    }

    /// Every pixel at its nearest levels, in place.
    func apply(to pixels: inout [RGBA]) {
        table.withUnsafeBufferPointer { table in
            pixels.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices {
                    let pixel = buffer[index]
                    buffer[index] = RGBA(
                        r: table[Int(pixel.r)], g: table[Int(pixel.g)], b: table[Int(pixel.b)],
                        a: pixel.a)
                }
            }
        }
    }

    /// Floyd–Steinberg to the levels, in place, over a `width` × `height`
    /// buffer — the weights and the coverage weighting of
    /// ``PixelQuantiser/dither(_:width:height:)``, which says why a
    /// transparent pixel carries no error and why a neighbour keeps its alpha.
    func dither(_ pixels: inout [RGBA], width: Int, height: Int) {
        guard width > 0, height > 0, pixels.count >= width * height else { return }
        table.withUnsafeBufferPointer { table in
            pixels.withUnsafeMutableBufferPointer { buffer in
                @inline(__always)
                func spread(_ index: Int, _ r: Int16, _ g: Int16, _ b: Int16) {
                    let pixel = buffer[index]
                    buffer[index] = RGBA(
                        r: UInt8(clamping: Int16(pixel.r) + r),
                        g: UInt8(clamping: Int16(pixel.g) + g),
                        b: UInt8(clamping: Int16(pixel.b) + b),
                        a: pixel.a)
                }
                for y in 0..<height {
                    let row = y * width
                    for x in 0..<width {
                        let index = row + x
                        let old = buffer[index]
                        let new = RGBA(
                            r: table[Int(old.r)], g: table[Int(old.g)], b: table[Int(old.b)],
                            a: old.a)
                        buffer[index] = new
                        let (rErr, gErr, bErr) = PixelQuantiser.weighted(
                            (Int16(old.r) - Int16(new.r), Int16(old.g) - Int16(new.g),
                             Int16(old.b) - Int16(new.b)),
                            byCoverage: old.a)
                        if x + 1 < width {
                            spread(index + 1, rErr * 7 / 16, gErr * 7 / 16, bErr * 7 / 16)
                        }
                        if y + 1 < height {
                            let below = index + width
                            if x > 0 { spread(below - 1, rErr * 3 / 16, gErr * 3 / 16, bErr * 3 / 16) }
                            spread(below, rErr * 5 / 16, gErr * 5 / 16, bErr * 5 / 16)
                            if x + 1 < width { spread(below + 1, rErr / 16, gErr / 16, bErr / 16) }
                        }
                    }
                }
            }
        }
    }
}
