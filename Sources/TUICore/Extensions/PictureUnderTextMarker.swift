//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureUnderTextMarker.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A picture under a cell's glyph, carried by the cell

/// The mark a glyph over a frosted picture leaves on its cell, where the
/// terminal can draw a picture under text: which image to lay under the
/// glyph, and which pixels of it the cell covers.
///
/// A cell drawing a glyph cannot also be a picture's placeholder, so a glyph
/// over a picture under a translucent layer stood on the frosted copy's
/// average colour — a block behind each letter (graphics notes §14.2). Where
/// the terminal draws a Kitty *classic* placement under text (`z=-1`, below
/// the glyphs and above the cells' default field: Ghostty, §14.5), the cell
/// instead holds no field of its own and carries this mark; the diff writer
/// reads the marked runs back off the finished frame
/// (``extracting(_:)``) and lays the image under each, cropped to the
/// pixels its cells cover. Carried as the cell's styling, the mark is moved,
/// clipped and covered with the cell, as ``HairlineMarker``'s is, and taken
/// out before anything reaches the terminal (``SGRMarks``).
///
/// `ESC [ 7745 : <id high> : <id> : <x> : <y> : <width> : <height> m`: the
/// image id in two halves (a sub-parameter is read as a number, and the
/// whole id may not fit one some reader's way), and the cell's rectangle in
/// the image's own pixels. Contiguous cells of one image whose rectangles sit
/// side by side, one row of the image's cells, make one run.
package enum PictureUnderTextMarker {

    /// The private SGR parameter.
    package static let parameter = 7745

    /// The bytes every mark's parameter starts with, `7745:`.
    private static let parameterBytes: [UInt8] = Array("\(parameter):".utf8)

    /// What one cell's mark says.
    package struct Cell: Hashable, Sendable {
        /// The image to lay under the glyph.
        package var image: UInt32
        /// The cell's rectangle in the image's pixels.
        package var x: Int
        package var y: Int
        package var width: Int
        package var height: Int

        package init(image: UInt32, x: Int, y: Int, width: Int, height: Int) {
            self.image = image
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// A run of marked cells: where it is on its row, and the image's pixels
    /// it covers, which the layer crops the image to.
    package struct Run: Hashable, Sendable {
        /// The run's first cell, in the line's columns.
        package var column: Int
        /// How many cells it covers.
        package var columns: Int
        /// The image, and the rectangle of its pixels the run covers.
        package var image: UInt32
        package var x: Int
        package var y: Int
        package var width: Int
        package var height: Int

        package init(column: Int, columns: Int, image: UInt32, x: Int, y: Int, width: Int, height: Int) {
            self.column = column
            self.columns = columns
            self.image = image
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The escape that turns `cell`'s mark on.
    package static func sequence(_ cell: Cell) -> String {
        "\u{1B}[\(parameter):\(cell.image >> 16):\(cell.image & 0xFFFF):\(cell.x):\(cell.y):\(cell.width):\(cell.height)m"
    }

    /// Whether `line` may carry a mark: a byte search (``SGRMarks/mayCarry(_:parameterBytes:)``).
    package static func mayCarryMark(_ line: String) -> Bool {
        SGRMarks.mayCarry(line, parameterBytes: parameterBytes)
    }

    /// `line` without its marks, and the runs they made, in column order.
    ///
    /// A run is contiguous cells of one image, each rectangle beside the last
    /// on one row of the image's pixels, all one height; a cell under no mark
    /// ends one, as does a cell that does not continue it.
    ///
    /// A wide glyph's mark states its first cell's pixels: it covers as many
    /// again for each further column, so the run's pixels keep pace with its
    /// cells — not two columns drawn from one column's pixels, and the next
    /// cell's continuing where the glyph's second column's would.
    package static func extracting(_ line: String) -> (line: String, runs: [Run]) {
        var runs: [Run] = []
        let stripped = SGRMarks.extracting(line, payload: cell(of:)) { column, columns, cell in
            let width = cell.width * max(columns, 1)
            if var last = runs.last, last.column + last.columns == column, last.image == cell.image,
                last.x + last.width == cell.x, last.y == cell.y, last.height == cell.height
            {
                last.columns += columns
                last.width += width
                runs[runs.count - 1] = last
            } else {
                runs.append(
                    Run(
                        column: column, columns: columns, image: cell.image,
                        x: cell.x, y: cell.y, width: width, height: cell.height))
            }
        }
        return (stripped, runs)
    }

    /// `line` without its marks — ``extracting(_:)``'s line alone, for a
    /// writer that is not drawing them.
    package static func stripping(_ line: String) -> String {
        mayCarryMark(line) ? extracting(line).line : line
    }

    /// The cell a mark parameter states, or `nil` for any other parameter.
    private static func cell(of parameter: Substring) -> Cell? {
        guard let fields = SGRMarks.fields(of: parameter, number: Self.parameter, count: 6),
            let high = UInt32(exactly: fields[0]), high <= 0xFF,
            let low = UInt32(exactly: fields[1]), low <= 0xFFFF,
            fields[2] >= 0, fields[3] >= 0, fields[4] > 0, fields[5] > 0
        else { return nil }
        return Cell(image: high << 16 | low, x: fields[2], y: fields[3], width: fields[4], height: fields[5])
    }
}

// MARK: - Whether this terminal draws a picture under text

extension KittyGraphics {

    /// Whether the terminal painting this app's output draws a Kitty classic
    /// placement under text — below the glyphs, above a cell's default field
    /// (`z=-1`) — so a glyph over a frosted picture can stand on the picture
    /// itself rather than on its average colour (`PictureUnderTextMarker`).
    /// Published from `TerminalClient.applyGraphicsSupport()`.
    ///
    /// A table of hosts somebody measured, ANDed with the handshake, as
    /// ``isHairlineSupported`` is: Ghostty today. iTerm2 3.7.6 refuses the
    /// placement and orders `z` differently; kitty is unmeasured (graphics
    /// notes §14.5). **Defaults to `false`**: everywhere else the glyph stands
    /// on the average colour, as it always has.
    public static var isPictureUnderTextSupported: Bool {
        get { taskPictureUnderTextSupported ?? processPictureUnderTextSupported }
        set { processPictureUnderTextSupported = newValue }
    }

    /// `nonisolated(unsafe)` for the reason ``isSupported`` gives: written
    /// during startup, before the render loop exists, and only read after.
    nonisolated(unsafe) private static var processPictureUnderTextSupported = false

    /// A task-scoped pin, bound by ``withPictureUnderTextSupport(_:operation:)``.
    @TaskLocal private static var taskPictureUnderTextSupported: Bool?

    /// Runs `operation` with ``isPictureUnderTextSupported`` pinned on this
    /// task only: tests run in parallel.
    @discardableResult
    public static func withPictureUnderTextSupport<T>(_ supported: Bool, operation: () throws -> T) rethrows -> T {
        try $taskPictureUnderTextSupported.withValue(supported, operation: operation)
    }
}
