//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+FrostBackdrop.swift
//
//  What a material frosts where a picture the terminal draws is behind it:
//  one picture of everything behind the glass — the pictures' pixels and the
//  cells between them — blurred as one, so the frost runs across a picture's
//  edge as glass does instead of stopping at it (`Terminal graphics
//  protocols.md` §14.6).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension FrameBuffer {
    /// The parsed rows of `covered` with each cell a box covers replaced by
    /// its cell of a backdrop: a picture of the cells read behind the frost,
    /// each picture cell its small copy's pixels and every other cell its
    /// effective colour (``effectiveRGB(of:surface:defaultForeground:)``),
    /// blurred as the frost's box blurs (``DerivedImages/frosted(_:width:height:reach:)``)
    /// and cut to `covered` — or no rows at all, where no picture is behind.
    ///
    /// Before, each picture was frosted on its own, inside its own box, and
    /// the cells between pictures by the box average, cell by cell: the
    /// owner, on the Materials clip, "the jagged-looking frosting, where the
    /// images behind have rectangles cut off in the blurred version". Read
    /// from the whole reach of the boxes, not just what they cover, so the
    /// blur at the glass's edge takes in what is beyond it, as the averages do.
    ///
    /// - Parameters:
    ///   - parsed: The destination rows the frost took apart, by row, each
    ///     through `read.columns.upperBound`.
    ///   - boxes: The cells each averaging claim covers.
    ///   - covered: Their union's bounds.
    ///   - read: What the frost read: `covered` and its boxes' reach.
    ///   - reach: The largest box's reach, in cells either way.
    static func frostBackdrop(
        parsed: [Int: [RowCell?]], boxes: [(columns: Range<Int>, rows: Range<Int>)],
        covered: (columns: Range<Int>, rows: Range<Int>), read: (columns: Range<Int>, rows: Range<Int>),
        reach: (columns: Int, rows: Int), surface: Color, defaultForeground: Color, images: TerminalImageStore
    ) -> [Int: [RowCell?]] {
        // Only where a picture is behind: anywhere else the averages are the frost.
        let picturesBehind = read.rows.contains { row in
            guard let cells = parsed[row] else { return false }
            return read.columns.contains { column in
                cells.indices.contains(column)
                    && cells[column]?.character.unicodeScalars.first == .terminalImagePlaceholder
            }
        }
        guard picturesBehind else { return [:] }

        let across = DerivedImages.pixelsAcross
        let down = DerivedImages.pixelsDown
        let width = read.columns.count * across
        let height = read.rows.count * down
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let surfaceRGB = surface.rgbComponents
        for (rowIndex, row) in read.rows.enumerated() {
            let cells = parsed[row] ?? []
            for (columnIndex, column) in read.columns.enumerated() {
                let cell = cells.indices.contains(column) ? cells[column] : nil
                let block = Self.backdropPixels(
                    of: cell, surface: surfaceRGB, surfaceColour: surface, defaultForeground: defaultForeground,
                    images: images)
                for y in 0..<down {
                    let start = ((rowIndex * down + y) * width + columnIndex * across) * 4
                    pixels.replaceSubrange(start..<(start + across * 4), with: block[(y * across * 4)..<((y + 1) * across * 4)])
                }
            }
        }
        let blurred = DerivedImages.frosted(pixels, width: width, height: height, reach: reach)
        // Cut to what the boxes cover.
        let left = (covered.columns.lowerBound - read.columns.lowerBound) * across
        let top = (covered.rows.lowerBound - read.rows.lowerBound) * down
        let cutWidth = covered.columns.count * across
        var cut: [UInt8] = []
        cut.reserveCapacity(cutWidth * covered.rows.count * down * 4)
        for y in top..<(top + covered.rows.count * down) {
            let start = (y * width + left) * 4
            cut += blurred[start..<(start + cutWidth * 4)]
        }
        guard let id = images.backdrop(pixels: cut, columns: covered.columns.count, rows: covered.rows.count)
        else { return [:] }

        var rows: [Int: [RowCell?]] = [:]
        for row in covered.rows {
            guard var cells = parsed[row] else { continue }
            for column in covered.columns where cells.indices.contains(column)
                && boxes.contains(where: { $0.columns.contains(column) && $0.rows.contains(row) })
            {
                cells[column] = Self.placeholderRowCell(
                    KittyGraphics.PlaceholderCell(
                        id: id, row: row - covered.rows.lowerBound, column: column - covered.columns.lowerBound))
            }
            rows[row] = cells
        }
        return rows
    }

    /// One cell's pixels in a backdrop, RGBA, ``DerivedImages/pixelsAcross`` ×
    /// ``DerivedImages/pixelsDown``: a picture cell's small copy, or a solid
    /// block of any other cell's effective colour — the surface past a line's
    /// end, and transparent where no colour has an RGB.
    private static func backdropPixels(
        of cell: RowCell?, surface: (red: UInt8, green: UInt8, blue: UInt8)?, surfaceColour: Color,
        defaultForeground: Color, images: TerminalImageStore
    ) -> [UInt8] {
        let count = DerivedImages.pixelsAcross * DerivedImages.pixelsDown
        if let cell, let ink = cell.foreground?.rgbComponents,
            let picture = KittyGraphics.placeholderCell(cell.character, foreground: ink),
            let block = images.cellPixels(of: picture)
        {
            return block
        }
        let rgb =
            cell.map { effectiveRGB(of: $0, surface: surfaceColour, defaultForeground: defaultForeground) } ?? surface
        guard let rgb else { return [UInt8](repeating: 0, count: count * 4) }
        var block: [UInt8] = []
        block.reserveCapacity(count * 4)
        for _ in 0..<count { block += [rgb.red, rgb.green, rgb.blue, 255] }
        return block
    }

    /// A row cell drawing `picture`'s cell, as a parsed placeholder is: the
    /// placeholder and its marks, the id in a direct-colour foreground.
    private static func placeholderRowCell(_ picture: KittyGraphics.PlaceholderCell) -> RowCell {
        // An image's id spelled as a colour, as its cells spell it.
        // swiftlint:disable:next framework_colour_literal
        let id = Color.rgb(UInt8((picture.id >> 16) & 0xFF), UInt8((picture.id >> 8) & 0xFF), UInt8(picture.id & 0xFF))
        return RowCell(
            character: picture.character, style: SGRState().settingForeground(id, depth: .truecolor),
            foreground: id, background: nil)
    }
}
