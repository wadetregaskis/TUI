//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+Frost.swift
//
//  A material's frost (owner ruling O5-FROSTED (b), 2026-10-24): what is behind
//  a material loses its glyphs, and each cell there takes the average colour of
//  a box of cells around it, before the material's tint is laid over it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

// MARK: - Marking

extension FrameBuffer {
    /// This buffer with its translucent FIELD claims marked as frosting what is
    /// behind them as `frost` says (``OpacityRegion/frost``): the cells a
    /// material painted, which claim its surface's alpha. A claim at a field of
    /// 0 — a cell the drawing does not reach, handed back to what is behind —
    /// and an opaque one are left alone.
    func markingFrost(_ frost: OpacityRegion.Frost) -> FrameBuffer {
        var result = self
        result.opacityRegions = opacityRegions.map { claim in
            guard claim.fieldOpacity > 0, claim.fieldOpacity < 1 else { return claim }
            var frosted = claim
            frosted.frost = frost
            return frosted
        }
        return result
    }
}

// MARK: - The cell behind, frosted

extension FrameBuffer {
    /// `cell` — a cell behind a material's translucent field — as a frost that
    /// averages nothing leaves it (``OpacityRegion/Frost/droppingGlyphs``, or a
    /// box with no colour to average): its field alone, the glyph and whatever
    /// the glyph wore (its ink, an underline) dropped (`Opacity as
    /// composition.md` §111).
    ///
    /// The field is the one the cell shows, kept as it is spelled: a reversed
    /// cell's (`cells(in:)` has already put it in `background`, and
    /// `isReversed` stays for the spelling), the terminal's own where the cell
    /// states it, and none where it names none, which the blend reads as the
    /// surface. The material's tint is laid over it as over any field.
    static func frosted(_ cell: RowCell) -> RowCell {
        var blank = cell
        blank.character = " "
        blank.foreground = nil
        // The field's slot exactly as the cell spells it, and nothing else.
        blank.style = SGRState()
        blank.style.setBackground(cell.style.backgroundColour)
        return blank
    }

    /// A blank cell whose field is `field` — a cell behind a material's
    /// translucent field, frosted by a box's average (``FrostFields``) — in
    /// place of whatever was there, or of nothing: past the end of a shorter
    /// line, what shows is the page, and the box's average is the frost of it.
    static func frosted(field: Color) -> RowCell {
        RowCell(
            character: " ", style: SGRState().settingBackground(field), foreground: nil, background: field)
    }
}

// MARK: - The averages

/// What an averaging frost (``OpacityRegion/Frost/averaging(columns:rows:)``)
/// makes of the cells behind a layer: each covered cell's average colour, in
/// the DESTINATION's coordinates, for the blend to take as the field behind it
/// (``FrameBuffer/CellAlpha/frostField``).
///
/// Made once per resolution, before any row is blended, because a cell's box
/// reaches rows the row-at-a-time blend has not read yet.
struct FrostFields {
    /// The destination rows the averages cover.
    let rows: Range<Int>

    /// The destination columns the averages cover.
    let columns: Range<Int>

    /// The averages, row-major over ``rows`` × ``columns``: `nil` where no
    /// averaging claim covers the cell, or its box had no colour with an RGB.
    var fields: [Color?]

    /// The average at destination `(column, row)`, or `nil`.
    func field(column: Int, row: Int) -> Color? {
        guard rows.contains(row), columns.contains(column) else { return nil }
        return fields[(row - rows.lowerBound) * columns.count + column - columns.lowerBound]
    }

    /// `alphas` — one source row's, indexed from source column `start` — with
    /// each frosting cell's average filled in from destination row
    /// `destinationRow`, `shift` columns to the right.
    func fill(_ alphas: inout [FrameBuffer.CellAlpha?], from start: Int, destinationRow: Int, shift: Int) {
        guard rows.contains(destinationRow) else { return }
        for index in alphas.indices where alphas[index]?.frosts == true {
            alphas[index]?.frostField = field(column: start + index + shift, row: destinationRow)
        }
    }
}

extension FrameBuffer {
    /// The averages an averaging frost in `claims` makes of this buffer — what
    /// is behind a layer landing at `position` — or `nil` where no claim
    /// averages (a layer with no material, or one that drops glyphs only).
    ///
    /// A cell's EFFECTIVE colour is its field with its ink laid over it at the
    /// share of the cell its glyph inks (``frostCoverage(of:)``), blended in
    /// encoded sRGB as every fade is; past the end of a line it is the surface.
    /// A covered cell's average is the mean of the encoded bytes of the
    /// effective colours in its box, rounded — no clamp needed: a mean of bytes
    /// is a byte. A colour with no RGB (the terminal's own, unreported) cannot
    /// be averaged and is left out of the sum. Where two claims with different
    /// boxes cover one cell, the larger box frosts it.
    ///
    /// One parse of each row the boxes reach, and a summed-area table over them,
    /// so a cell's average costs the same four lookups a channel whatever its
    /// box's size.
    ///
    /// - Parameters:
    ///   - claims: The layer's claims; only those that average are read.
    ///   - position: Where the layer lands in this buffer.
    ///   - surface: What a cell stating no field shows, resolved.
    ///   - defaultForeground: What a glyph stating no ink is drawn in, resolved.
    func frostFields(
        under claims: [OpacityRegion], at position: (x: Int, y: Int), surface: Color, defaultForeground: Color
    ) -> FrostFields? {
        typealias Box = (columns: Range<Int>, rows: Range<Int>, reachX: Int, reachY: Int)
        var boxes: [Box] = []
        for claim in claims {
            guard case .averaging(let reachX, let reachY)? = claim.frost else { continue }
            let left = max(0, claim.offsetX + position.x)
            let right = min(width, claim.offsetX + position.x + claim.width)
            let top = max(0, claim.offsetY + position.y)
            let bottom = min(lines.count, claim.offsetY + position.y + claim.height)
            guard left < right, top < bottom else { continue }
            boxes.append((left..<right, top..<bottom, Int(reachX), Int(reachY)))
        }
        guard !boxes.isEmpty else { return nil }
        // The larger box last, so it is the one a doubly covered cell keeps.
        boxes.sort { ($0.reachX * 2 + 1) * ($0.reachY * 2 + 1) < ($1.reachX * 2 + 1) * ($1.reachY * 2 + 1) }
        let covered = (
            columns: boxes.map(\.columns.lowerBound).min()!..<boxes.map(\.columns.upperBound).max()!,
            rows: boxes.map(\.rows.lowerBound).min()!..<boxes.map(\.rows.upperBound).max()!)
        let readColumns =
            max(0, boxes.map { $0.columns.lowerBound - $0.reachX }.min()!)
            ..< min(width, boxes.map { $0.columns.upperBound + $0.reachX }.max()!)
        let readRows =
            max(0, boxes.map { $0.rows.lowerBound - $0.reachY }.min()!)
            ..< min(lines.count, boxes.map { $0.rows.upperBound + $0.reachY }.max()!)
        let table = Self.summedEffectiveColours(
            of: lines, columns: readColumns, rows: readRows, surface: surface, defaultForeground: defaultForeground)

        var result = FrostFields(
            rows: covered.rows, columns: covered.columns,
            fields: [Color?](repeating: nil, count: covered.rows.count * covered.columns.count))
        for box in boxes {
            for row in box.rows {
                let top = max(readRows.lowerBound, row - box.reachY) - readRows.lowerBound
                let bottom = min(readRows.upperBound, row + box.reachY + 1) - readRows.lowerBound
                let base = (row - covered.rows.lowerBound) * covered.columns.count - covered.columns.lowerBound
                for column in box.columns {
                    let left = max(readColumns.lowerBound, column - box.reachX) - readColumns.lowerBound
                    let right = min(readColumns.upperBound, column + box.reachX + 1) - readColumns.lowerBound
                    result.fields[base + column] = table.average(top: top, bottom: bottom, left: left, right: right)
                }
            }
        }
        return result
    }

    /// A summed-area table of the effective colours of `rows` × `columns` of
    /// `lines`: four channels (red, green, blue, and how many cells had an RGB)
    /// summed over every cell above and to the left of each corner.
    private static func summedEffectiveColours(
        of lines: [String], columns: Range<Int>, rows: Range<Int>, surface: Color, defaultForeground: Color
    ) -> SummedColours {
        var table = SummedColours(width: columns.count, height: rows.count)
        let surfaceRGB = surface.rgbComponents
        for (rowIndex, row) in rows.enumerated() {
            let cells = cells(
                in: lines[row], through: columns.upperBound, defaultForeground: defaultForeground, surface: surface)
            var running = (red: 0, green: 0, blue: 0, cells: 0)
            // A wide glyph's later columns are the glyph's: `cells(in:)` leaves
            // them nil, as it leaves the columns past the line's end, which show
            // the surface.
            var continuation: (rgb: (red: UInt8, green: UInt8, blue: UInt8)?, columns: Int) = (nil, 0)
            for column in 0..<columns.upperBound {
                let rgb: (red: UInt8, green: UInt8, blue: UInt8)?
                if let cell = cells[column] {
                    rgb = effectiveRGB(of: cell, surface: surface, defaultForeground: defaultForeground)
                    continuation = (rgb, cell.character.terminalWidth - 1)
                } else if continuation.columns > 0 {
                    rgb = continuation.rgb
                    continuation.columns -= 1
                } else {
                    rgb = surfaceRGB
                }
                guard column >= columns.lowerBound else { continue }
                if let rgb {
                    running.red += Int(rgb.red)
                    running.green += Int(rgb.green)
                    running.blue += Int(rgb.blue)
                    running.cells += 1
                }
                table.accumulate(running, row: rowIndex, column: column - columns.lowerBound)
            }
        }
        return table
    }

    /// `cell`'s effective colour, as a frost averages it: its field, with its
    /// ink over it at its glyph's coverage — or `nil` where that has no RGB.
    private static func effectiveRGB(
        of cell: RowCell, surface: Color, defaultForeground: Color
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let field = cell.background ?? surface
        let coverage = frostCoverage(of: cell.character)
        guard coverage > 0 else { return field.rgbComponents }
        return (cell.foreground ?? defaultForeground).opacity(coverage, over: field).rgbComponents
    }

    /// How much of a cell `character` inks, roughly: the share of the cell's
    /// colour that is its ink rather than its field, for a frost's average.
    ///
    /// A constant table, not a measurement of any font: a frost averages a
    /// neighbourhood, and these only keep a page of text from frosting to its
    /// field alone or a block from frosting to nothing. Read from the first
    /// scalar, ASCII first: the table is asked of every cell a box reaches.
    static func frostCoverage(of character: Character) -> Double {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        let value = scalar.value
        if value < 0x80 {
            switch value {
            case 0x20: return 0
            case 0x41...0x5A: return 0.35  // A-Z
            case 0x30...0x39, 0x61...0x7A: return 0.3  // 0-9, a-z
            case 0x21...0x7E: return 0.12  // punctuation and symbols
            default: return 0
            }
        }
        switch value {
        case 0x2580...0x259F:
            return blockCoverage[Int(value - 0x2580)]
        case 0x2500...0x257F:
            // Box drawing: a line through the cell.
            return 0.15
        case 0x2800...0x28FF:
            // Braille: a dot is a small share of the cell.
            return Double((value - 0x2800).nonzeroBitCount) * 0.06
        default:
            break
        }
        if character.isLetter || character.isNumber {
            return character.terminalWidth > 1 ? 0.45 : (character.isUppercase ? 0.35 : 0.3)
        }
        if character.isPunctuation || character.isSymbol { return 0.12 }
        return 0.3
    }

    /// The block elements, U+2580…U+259F: the share of the cell each fills —
    /// halves, quadrants, eighths, and the three shades.
    private static let blockCoverage: [Double] = [
        0.5, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875,  // ▀ ▁ ▂ ▃ ▄ ▅ ▆ ▇
        1, 0.875, 0.75, 0.625, 0.5, 0.375, 0.25, 0.125,  // █ ▉ ▊ ▋ ▌ ▍ ▎ ▏
        0.5, 0.25, 0.5, 0.75, 0.125, 0.125, 0.25, 0.25,  // ▐ ░ ▒ ▓ ▔ ▕ ▖ ▗
        0.25, 0.75, 0.5, 0.75, 0.75, 0.25, 0.5, 0.75,  // ▘ ▙ ▚ ▛ ▜ ▝ ▞ ▟
    ]
}

/// A summed-area table of colours: at each corner `(row, column)`, the sums of
/// the red, green and blue bytes, and the count of cells, over every cell
/// above and to the left of it — so a box's sums are four lookups.
private struct SummedColours {
    /// The corners: `(height + 1) × (width + 1)`, four channels each.
    private var sums: [Int]

    private let stride: Int

    init(width: Int, height: Int) {
        stride = width + 1
        sums = [Int](repeating: 0, count: (height + 1) * stride * 4)
    }

    /// Records the corner below and right of cell `(row, column)`: `running`,
    /// that row's sums up to and including the cell, over the corner above.
    mutating func accumulate(_ running: (red: Int, green: Int, blue: Int, cells: Int), row: Int, column: Int) {
        let above = (row * stride + column + 1) * 4
        let corner = ((row + 1) * stride + column + 1) * 4
        sums[corner] = sums[above] + running.red
        sums[corner + 1] = sums[above + 1] + running.green
        sums[corner + 2] = sums[above + 2] + running.blue
        sums[corner + 3] = sums[above + 3] + running.cells
    }

    /// The mean colour of the cells in rows `top..<bottom` and columns
    /// `left..<right`, rounded to the nearest byte, or `nil` where none of them
    /// had an RGB.
    func average(top: Int, bottom: Int, left: Int, right: Int) -> Color? {
        let topLeft = (top * stride + left) * 4
        let topRight = (top * stride + right) * 4
        let bottomLeft = (bottom * stride + left) * 4
        let bottomRight = (bottom * stride + right) * 4
        func total(_ channel: Int) -> Int {
            sums[bottomRight + channel] - sums[topRight + channel] - sums[bottomLeft + channel]
                + sums[topLeft + channel]
        }
        let cells = total(3)
        guard cells > 0 else { return nil }
        // Rounded to the nearest; a mean of bytes cannot leave 0…255.
        func mean(_ channel: Int) -> UInt8 { UInt8((total(channel) + cells / 2) / cells) }
        // swiftlint:disable:next framework_colour_literal - an average of the colours behind, not ink
        return .rgb(mean(0), mean(1), mean(2))
    }
}
