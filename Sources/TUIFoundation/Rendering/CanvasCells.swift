//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasCells.swift
//
//  A canvas's pixels as cells, at the grain the terminal's glyphs reach: for
//  each cell the two colours that best split its pixels, and the glyph drawing
//  that split.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling

extension CanvasGrain {
    /// A cell's pixels, across and down, where this grain draws in glyphs.
    var cellPixels: (across: Int, down: Int) {
        switch resolvedKind {
        case .cells: (1, 1)
        case .halfBlocks: (1, 2)
        case .quadrants: (2, 2)
        case .sextants: (2, 3)
        case .octants, .braille: (2, 4)
        }
    }

    /// The glyph inking the pixels of `mask`, bit 0 the top-left and on across
    /// then down, in this grain's vocabulary.
    func glyph(mask: Int) -> Character {
        switch resolvedKind {
        case .cells: mask == 0 ? " " : "█"
        case .halfBlocks: Self.halfBlockGlyphs[mask]
        case .quadrants: Self.quadrantGlyphs[mask]
        case .sextants: Self.sextant(mask)
        case .octants: Self.octant(mask)
        case .braille: Self.braille(mask)
        }
    }

    private static let halfBlockGlyphs: [Character] = [" ", "▀", "▄", "█"]

    private static let quadrantGlyphs: [Character] = [
        " ", "▘", "▝", "▀", "▖", "▌", "▞", "▛", "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█",
    ]

    /// Symbols for Legacy Computing lists the sextants in mask order from
    /// U+1FB00, leaving out those Block Elements already has: none, the left
    /// and right halves, and all.
    private static func sextant(_ mask: Int) -> Character {
        switch mask {
        case 0: return " "
        case 21: return "▌"
        case 42: return "▐"
        case 63: return "█"
        default:
            let skipped = (mask > 21 ? 1 : 0) + (mask > 42 ? 1 : 0)
            return scalar(0x1FB00 + UInt32(mask - 1 - skipped))
        }
    }

    /// The twenty-six masks some earlier block already draws, each with the
    /// scalar that draws it, in mask order. Read off the Unicode 16 names,
    /// which ``CanvasGrainTests`` compares where the standard library has them.
    private static let octantsElsewhere: [(mask: Int, scalar: UInt32)] = [
        (0x00, 0x20), (0x01, 0x1CEA8), (0x02, 0x1CEAB), (0x03, 0x1FB82), (0x05, 0x2598), (0x0A, 0x259D),
        (0x0F, 0x2580), (0x14, 0x1FBE6), (0x28, 0x1FBE7), (0x3F, 0x1FB85), (0x40, 0x1CEA3), (0x50, 0x2596),
        (0x55, 0x258C), (0x5A, 0x259E), (0x5F, 0x259B), (0x80, 0x1CEA0), (0xA0, 0x2597), (0xA5, 0x259A),
        (0xAA, 0x2590), (0xAF, 0x259C), (0xC0, 0x2582), (0xF0, 0x2584), (0xF5, 0x2599), (0xFA, 0x259F),
        (0xFC, 0x2586), (0xFF, 0x2588),
    ]

    /// Symbols for Legacy Computing Supplement lists the octants in mask order
    /// from U+1CD00, leaving out ``octantsElsewhere``.
    private static func octant(_ mask: Int) -> Character {
        var skipped = 0
        for known in octantsElsewhere {
            if known.mask == mask { return scalar(known.scalar) }
            if known.mask < mask { skipped += 1 }
        }
        return scalar(0x1CD00 + UInt32(mask - skipped))
    }

    /// A braille cell's dots are numbered down the left and then the right,
    /// with the bottom row added last.
    private static func braille(_ mask: Int) -> Character {
        let dots: [UInt32] = [0x01, 0x08, 0x02, 0x10, 0x04, 0x20, 0x40, 0x80]
        var pattern: UInt32 = 0
        for bit in 0..<8 where mask & (1 << bit) != 0 { pattern |= dots[bit] }
        return scalar(0x2800 + pattern)
    }

    private static func scalar(_ value: UInt32) -> Character {
        Unicode.Scalar(value).map(Character.init) ?? " "
    }
}

/// A canvas's pixels as cells.
///
/// A cell draws one glyph with two colours, however many pixels it stands for,
/// so each cell's pixels are split into the two groups nearest their own
/// colours, and the glyph is the one whose ink falls on the second group. Where
/// a shape's edge passes through the cell the second group is what the terminal
/// shows through: no field at all, so whatever is behind the canvas shows there
/// and the edge is exact to the pixel. Each colour keeps its alpha, which
/// ``ShapeCells`` claims for the compositor, as a shape's antialiased edge is.
///
/// At half blocks this is the table ``ShapeHalfBlocks`` draws by, cell for cell.
enum CanvasCells {
    /// The cells of `raster`, whose cells are `grain`'s pixels each.
    ///
    /// - Parameters:
    ///   - raster: The pixels.
    ///   - grain: The grain they were drawn at.
    ///   - columns: The frame's width, in cells.
    ///   - rows: The frame's height, in rows.
    ///   - monochrome: Whether the terminal shows no colour, so a pixel is
    ///     there or it is not.
    ///   - backdrop: What an opaque canvas's pixels start as, which on a
    ///     terminal with no colour is not there.
    ///   - spelling: The colour a pixel's channels stand for, where it is one
    ///     the terminal decides, and has no channels of its own.
    static func cells(
        of raster: CanvasRaster, grain: CanvasGrain, columns: Int, rows: Int, monochrome: Bool,
        backdrop: CanvasRGBA? = nil, spelling: [UInt32: Color]
    ) -> ShapeCells {
        var cells = ShapeCells(width: columns, height: rows)
        let (across, down) = grain.cellPixels
        var samples = [CanvasRGBA](repeating: .clear, count: across * down)
        for row in 0..<rows {
            for column in 0..<columns {
                for y in 0..<down {
                    for x in 0..<across { samples[y * across + x] = raster[column * across + x, row * down + y] }
                }
                cells[column, row] =
                    monochrome
                    ? silhouette(samples, grain: grain, backdrop: backdrop)
                    : cell(samples, grain: grain, spelling: spelling)
            }
        }
        return cells
    }

    /// A cell for a terminal with no colour: a pixel is there at half strength.
    private static func silhouette(_ samples: [CanvasRGBA], grain: CanvasGrain, backdrop: CanvasRGBA?) -> ShapeCells.Cell {
        var mask = 0
        for (bit, sample) in samples.enumerated() where sample.alpha >= 128 && sample != backdrop { mask |= 1 << bit }
        return ShapeCells.Cell(ink: nil, field: nil, glyph: grain.glyph(mask: mask))
    }

    /// The glyph and two colours that best draw `samples`.
    static func cell(_ samples: [CanvasRGBA], grain: CanvasGrain, spelling: [UInt32: Color]) -> ShapeCells.Cell {
        let everything = (1 << samples.count) - 1
        var present = 0
        for (bit, sample) in samples.enumerated() where sample.alpha > 0 { present |= 1 << bit }
        guard present != 0 else { return .empty }
        func colour(of mask: Int) -> Color { mean(samples, mask: mask, spelling: spelling) }
        // A hole shows what is behind: the pixels there are the ink, and there
        // is no field.
        if present != everything {
            return ShapeCells.Cell(ink: colour(of: present), field: nil, glyph: grain.glyph(mask: present))
        }
        var ink = split(samples)
        guard ink != 0 else {
            let whole = colour(of: everything)
            // A braille cell is its dots however full, which is its look.
            if grain.resolvedKind == .braille {
                return ShapeCells.Cell(ink: whole, field: nil, glyph: grain.glyph(mask: everything))
            }
            return ShapeCells.Cell(ink: nil, field: whole, glyph: " ")
        }
        // The last pixel is always the ink, which spells a cell of two rows
        // `▄` over the top's colour, as `ShapeHalfBlocks` does.
        if ink & (1 << (samples.count - 1)) == 0 { ink = everything ^ ink }
        return ShapeCells.Cell(ink: colour(of: ink), field: colour(of: everything ^ ink), glyph: grain.glyph(mask: ink))
    }

    /// The pixels of the second of the two groups `samples` falls into, or 0
    /// where they are all one colour: seeded at the farthest pair, and each
    /// pixel given to the nearer seed.
    private static func split(_ samples: [CanvasRGBA]) -> Int {
        var farthest = (first: 0, second: 0, distance: 0)
        for first in samples.indices {
            for second in samples.indices where second > first {
                let apart = distance(samples[first], samples[second])
                if apart > farthest.distance { farthest = (first, second, apart) }
            }
        }
        guard farthest.distance > 0 else { return 0 }
        var mask = 0
        for (bit, sample) in samples.enumerated()
        where distance(sample, samples[farthest.second]) < distance(sample, samples[farthest.first]) {
            mask |= 1 << bit
        }
        return mask
    }

    private static func distance(_ a: CanvasRGBA, _ b: CanvasRGBA) -> Int {
        func squared(_ x: UInt8, _ y: UInt8) -> Int { (Int(x) - Int(y)) * (Int(x) - Int(y)) }
        return squared(a.red, b.red) + squared(a.green, b.green) + squared(a.blue, b.blue) + squared(a.alpha, b.alpha)
    }

    /// The mean of the pixels of `mask`, weighted by their alpha, at their mean
    /// alpha — and spelled as the colour it stands for, where it is one.
    private static func mean(_ samples: [CanvasRGBA], mask: Int, spelling: [UInt32: Color]) -> Color {
        var sums = (red: 0, green: 0, blue: 0, alpha: 0, count: 0)
        for (bit, sample) in samples.enumerated() where mask & (1 << bit) != 0 {
            let alpha = Int(sample.alpha)
            sums.red += Int(sample.red) * alpha
            sums.green += Int(sample.green) * alpha
            sums.blue += Int(sample.blue) * alpha
            sums.alpha += alpha
            sums.count += 1
        }
        guard sums.alpha > 0 else { return .clear }
        func channel(_ sum: Int) -> UInt8 { UInt8((sum + sums.alpha / 2) / sums.alpha) }
        let (red, green, blue) = (channel(sums.red), channel(sums.green), channel(sums.blue))
        let meanAlpha = Double(sums.alpha) / Double(sums.count) / 255
        if let spelled = spelling[UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)] {
            return meanAlpha >= 1 ? spelled : spelled.opacity(meanAlpha)
        }
        // A canvas's own pixels: content, not ink a palette role could name.
        let colour = Color.rgb(red, green, blue)  // swiftlint:disable:this framework_colour_literal
        return meanAlpha >= 1 ? colour : colour.opacity(meanAlpha)
    }
}
