//  🖥️ TUI — A Terminal UI framework for Swift
//  ScreenSelection+TextFrames.swift
//
//  The highlight keeps to the text it crosses: each `Text` files its frame
//  (`FrameBuffer.filingTextFrame(context:)`), and on every row the highlight is
//  drawn on the frames the selection crosses there, not on the padding round
//  them or the gap between two texts side by side.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension ScreenSelection {
    /// The cells `selection`'s highlight is drawn on, row by row, top to
    /// bottom: each row's spans, left to right. A row the selection does not
    /// reach is left out, as is one where nothing of it is drawn.
    ///
    /// The selection's cells, in reading order as ever (``columns(of:onRow:cells:)``),
    /// kept to what is drawn there:
    ///
    /// - **A text's frame** (`frames`): the cells of every frame the
    ///   selection crosses on that row — exactly, so a bordered card's
    ///   padding, the blanks past the end of a row and the gap between two
    ///   texts side by side are not highlighted. A frame is a text's
    ///   rectangle, so a wrapped paragraph's rows are highlighted to its
    ///   trailing edge, a block, as a Mac's text view draws them.
    /// - **Drawing that is no `Text`** — a shape, a custom view's cells, a
    ///   field's text, a table's text columns, a picture (`pictures`) — files
    ///   no frame, and is taken as today: its characters (not its blanks, not
    ///   the box-drawing characters of a border or a rule) are highlighted,
    ///   and the blanks between two of them on a row, or between one of them
    ///   and a text's frame, as a terminal highlights a run of text. Blanks
    ///   between two frames, or between a frame or a character and a wall,
    ///   are not: a frame's edge is exact, and a wall is no text.
    /// - **A selection that crosses no frame at all** — over a picture, a
    ///   table's text, a blank stretch of page — is drawn as it always was:
    ///   every cell it covers, padding and all.
    ///
    /// What is SELECTED is unchanged by any of this: the text read is the
    /// cells the selection covers (``text(of:in:)``), blanks between texts
    /// included, as a terminal copies them.
    ///
    /// - Parameters:
    ///   - selection: The selection, its unit not yet applied.
    ///   - frames: The text frames drawn, in the page's coordinates
    ///     (`[HitTestRegion].textFrames`).
    ///   - pictures: The pictures drawn, in the same coordinates
    ///     (`[HitTestRegion].pictureRects`).
    ///   - cells: Row `n`'s cells (``cells(of:)``).
    package static func highlightedSpans(
        of selection: Selection, frames: [CellRect], pictures: [CellRect] = [], cells: (Int) -> [Character?]
    ) -> [(row: Int, spans: [Range<Int>])] {
        let (start, end) = ends(of: selection, cells: cells)
        var resolved = selection
        (resolved.anchor, resolved.head) = (start, end)
        resolved.unit = .character
        let rows = start.y...max(start.y, end.y)
        var covered: [(row: Int, columns: Range<Int>)] = []
        for row in rows {
            if let columns = Self.columns(of: resolved, onRow: row, cells: cells(row)) { covered.append((row, columns)) }
        }
        let framed = Self.columnsByRow(frames, rows: rows)
        let crossesFrame = covered.contains { row, columns in
            framed[row]?.contains { $0.overlaps(columns) } ?? false
        }
        guard crossesFrame else { return covered.map { ($0.row, [$0.columns]) } }
        let pictured = pictures.isEmpty ? [:] : Self.columnsByRow(pictures, rows: rows)
        return covered.compactMap { row, columns in
            let spans = Self.drawnSpans(
                of: columns, cells: cells(row), frames: framed[row] ?? [], pictures: pictured[row] ?? [])
            return spans.isEmpty ? nil : (row, spans)
        }
    }

    /// The columns each of `rects` covers on each of `rows` it reaches, by
    /// row: one pass over the rectangles, so a page of texts costs a
    /// selection its frames once, not once per row.
    static func columnsByRow(_ rects: [CellRect], rows: ClosedRange<Int>) -> [Int: [Range<Int>]] {
        var byRow: [Int: [Range<Int>]] = [:]
        for rect in rects where rect.width > 0 {
            let top = max(rect.y, rows.lowerBound)
            let bottom = min(rect.maxY, rows.upperBound + 1)
            guard top < bottom else { continue }
            for row in top..<bottom { byRow[row, default: []].append(rect.x..<rect.maxX) }
        }
        return byRow
    }

    /// What a cell of a row shows, for ``drawnSpans(of:cells:frames:pictures:)``.
    private enum Drawn {
        /// Inside a text's frame.
        case frame
        /// A character drawn by something other than a text, or a picture's
        /// cell.
        case drawing
        /// A box-drawing character: a border's wall, a rule.
        case wall
        /// A blank.
        case blank

        var isHighlighted: Bool { self == .frame || self == .drawing }
    }

    /// The spans of `columns`, one row's covered cells, that the highlight is
    /// drawn on where the selection crosses a text's frame: the rule
    /// ``highlightedSpans(of:frames:pictures:cells:)`` states.
    static func drawnSpans(
        of columns: Range<Int>, cells: [Character?], frames: [Range<Int>], pictures: [Range<Int>]
    ) -> [Range<Int>] {
        func kind(of character: Character?) -> Drawn {
            guard let character, !character.isWhitespace else { return .blank }
            let scalar = character.unicodeScalars.first?.value ?? 0
            return (0x2500...0x259F).contains(scalar) ? .wall : .drawing
        }
        var kinds: [Drawn] = []
        kinds.reserveCapacity(columns.count)
        for column in columns {
            guard column < cells.count else {
                kinds.append(.blank)
                continue
            }
            // A wide character's second cell is the character's.
            var first = column
            while first > 0, cells[first] == nil { first -= 1 }
            kinds.append(kind(of: cells[first]))
        }
        func mark(_ spans: [Range<Int>], as drawn: Drawn) {
            for span in spans {
                let clamped = span.clamped(to: columns)
                for column in clamped { kinds[column - columns.lowerBound] = drawn }
            }
        }
        mark(pictures, as: .drawing)
        mark(frames, as: .frame)
        // A run of blanks is highlighted between two highlighted cells, one
        // of them drawing that is no text.
        var index = 0
        while index < kinds.count {
            guard kinds[index] == .blank else {
                index += 1
                continue
            }
            var past = index
            while past < kinds.count, kinds[past] == .blank { past += 1 }
            if index > 0, past < kinds.count, kinds[index - 1].isHighlighted, kinds[past].isHighlighted,
                kinds[index - 1] == .drawing || kinds[past] == .drawing
            {
                for blank in index..<past { kinds[blank] = .drawing }
            }
            index = past
        }
        var spans: [Range<Int>] = []
        var open: Int?
        for (offset, drawn) in kinds.enumerated() {
            let column = columns.lowerBound + offset
            if drawn.isHighlighted {
                if open == nil { open = column }
            } else if let from = open {
                spans.append(from..<column)
                open = nil
            }
        }
        if let from = open { spans.append(from..<columns.upperBound) }
        return spans
    }
}
