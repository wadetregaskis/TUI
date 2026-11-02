//  🖥️ TUI — A Terminal UI framework for Swift
//  KittyGraphics+PlaceholderRuns.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Reading a picture's cells back off a finished row

extension KittyGraphics {

    /// A run of placeholder cells on one row: where it is on the row, and which
    /// cells of which image it draws. What a host with no placeholders is sent
    /// in place of those cells (`Terminal graphics protocols.md` §15).
    package struct PlaceholderRun: Hashable, Sendable {
        /// The run's first cell, in the line's columns.
        package var column: Int
        /// How many cells it covers.
        package var columns: Int
        /// The image they draw.
        package var image: ImageID
        /// Which of the image's placements they name, in their underline colour
        /// (``placeholderRows(id:columns:rows:placement:)``), or `nil` for its
        /// own.
        package var placement: UInt32?
        /// The first cell's row and column in the image.
        package var imageRow: Int
        package var imageColumn: Int

        package init(
            column: Int, columns: Int, image: ImageID, placement: UInt32? = nil, imageRow: Int, imageColumn: Int
        ) {
            self.column = column
            self.columns = columns
            self.image = image
            self.placement = placement
            self.imageRow = imageRow
            self.imageColumn = imageColumn
        }
    }

    /// `line` with every placeholder cell a space, and the runs those cells
    /// made, in column order: contiguous cells of one placement of one image, on
    /// one of its rows, each the column after the last.
    ///
    /// A cell that names no image (a placeholder in a foreground that is not a
    /// direct colour, which no renderer writes) goes too, and makes no run: on
    /// a host with no placeholders the codepoint can only print as a box.
    ///
    /// The spaces keep the styling in force, so a cell's background is still
    /// what shows through a transparent picture, as it is under a placeholder.
    package static func extractingPlaceholders(_ line: String) -> (line: String, runs: [PlaceholderRun]) {
        guard line.unicodeScalars.contains(.terminalImagePlaceholder) else { return (line, []) }
        var result = ""
        result.reserveCapacity(line.utf8.count)
        var runs: [PlaceholderRun] = []
        var state = SGRState()
        var column = 0
        // `true`: on to the next segment, every time.
        _ = line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, _):
                state.apply(sequence)
                result += sequence
            case .visible(let character):
                guard character.unicodeScalars.first == .terminalImagePlaceholder else {
                    result.append(character)
                    column += character.terminalWidth
                    return true
                }
                result.append(" ")
                append(character, at: column, under: state, to: &runs)
                column += 1
            }
            return true
        }
        return (result, runs)
    }

    /// Adds cell `character`, at `column`, to `runs`: to the last run if it
    /// carries it on, or as one of its own.
    private static func append(
        _ character: Character, at column: Int, under state: SGRState, to runs: inout [PlaceholderRun]
    ) {
        guard case .rgb(let red, let green, let blue)? = state.foregroundColour,
            let cell = placeholderCell(
                character, foreground: (UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue)))
        else { return }
        let placement = state.underlineColourIndex.map { UInt32(clamping: $0) }
        if var last = runs.last, last.column + last.columns == column, last.image == cell.id,
            last.placement == placement, last.imageRow == cell.row, last.imageColumn + last.columns == cell.column
        {
            last.columns += 1
            runs[runs.count - 1] = last
        } else {
            runs.append(
                PlaceholderRun(
                    column: column, columns: 1, image: cell.id, placement: placement, imageRow: cell.row,
                    imageColumn: cell.column))
        }
    }

    /// `line` with every placeholder cell a space — ``extractingPlaceholders(_:)``'s
    /// line alone, for a writer that places nothing for them.
    package static func strippingPlaceholders(_ line: String) -> String {
        extractingPlaceholders(line).line
    }
}
