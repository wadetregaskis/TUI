//  🖥️ TUI — A Terminal UI framework for Swift
//  SoftWrapLayout.swift
//
//  The rows an editable text soft-wraps into, in terminal cells, and the
//  mapping between a caret's character offset and a row and a column.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The rows an editable text soft-wraps into at a width, in terminal cells, and
/// the two-way mapping between a character offset — a caret, an end of a
/// selection — and a row and a column.
///
/// `Text` wraps for display (``TextWrapping``): it drops the space it breaks
/// at, and leaves a word too long for its line to be truncated. Text being
/// edited cannot lose a character, so here every character of the text is on
/// exactly one row, and every caret offset has a cell to be drawn on. The rules
/// are the macOS text system's, measured on a vertical `TextField` (macOS
/// 15.8):
///
/// - A newline ends a row, and is itself drawn nowhere. Text ending in a
///   newline has an empty last row, where the caret after it sits.
/// - A row may break after a run of spaces. The run stays at the end of the row
///   it breaks, hanging past the wrap width rather than starting the next row
///   with a space (`"aaa bbb ccc "` then `"ddd"`).
/// - A word too long for a row is broken between characters.
/// - A row may also break before or after a wide character, as ``TextWrapping``
///   allows, so a line of CJK with no spaces wraps rather than breaking
///   wherever it overflows.
/// - A tab is a break opportunity, as a space is, and hangs the same way.
///   Where a character's width depends on the column it starts at — a tab
///   reaching the next tab stop — the stops are measured from the start of its
///   row: an `NSTextView`'s stops sit on its text container's left edge, which
///   every row starts at (measured on macOS 15.8, a SwiftUI `TextEditor` whose
///   tab after a wrap reached the row's first stop).
///
/// **The last cell of the width is a margin.** Text wraps one cell short of the
/// width, so the caret after the last character of a full row — at a newline,
/// or at the end of the text — has a cell to sit on, as does the first space
/// hanging off a row. A caret further into a hanging run sits on the margin
/// too; the macOS text system clamps it to the edge the same way.
///
/// An offset where a row was soft-wrapped is both the end of that row and the
/// start of the next. Which one the caret is drawn at is its affinity:
/// ``TextSelectionAffinity/upstream`` draws it at the end of the earlier row,
/// and anything else at the start of the later one. Under `.automatic` the
/// handlers pass the caret's own lean (``CaretLean``), as the macOS text
/// system keeps one per caret: upstream after an edit, downstream after an
/// arrow key (measured on macOS 15.8).
///
/// Shared by the vertical field and ``TextEditor`` (decisions B62 and A43): the
/// field gives each character one width, the editor a width that depends on its
/// column, for its tabs.
struct SoftWrapLayout: Equatable {
    /// One row: the characters it draws, and how it ends.
    struct Row: Equatable {
        /// The offset of the row's first character.
        let start: Int

        /// The offset one past the row's last character, its newline excluded.
        let end: Int

        /// Whether a newline or the end of the text follows the row. A row that
        /// does not was soft-wrapped, and the offset at its end is also the
        /// start of the next row.
        let endsParagraph: Bool
    }

    /// The rows, top to bottom. Never empty: an empty text is one empty row.
    var rows: Rows { Rows(laidOut: laidOutRows, oneRowCount: Int(oneRowCount)) }

    /// How many rows: `rows.count`, read without the rows.
    var rowCount: Int { laidOutRows.isEmpty ? 1 : laidOutRows.count }

    /// A layout's rows, read as an array of them is: the array the walk made,
    /// or a one-row layout's row, made when it is read.
    struct Rows: RandomAccessCollection {
        typealias Indices = Range<Int>

        fileprivate let laidOut: [Row]
        fileprivate let oneRowCount: Int

        var startIndex: Int { 0 }
        var endIndex: Int { laidOut.isEmpty ? 1 : laidOut.count }

        subscript(position: Int) -> Row {
            guard laidOut.isEmpty else { return laidOut[position] }
            precondition(position == 0, "Row index out of range")
            return Row(start: 0, end: oneRowCount, endsParagraph: true)
        }
    }

    // A one-row layout. Most of an editor's lines fit their row and are of
    // characters one cell each, and for those there is nothing to keep but how
    // many characters they are: kept as an array of one row and an array of
    // ones, such a line was about 180 of the 280 bytes a line a large
    // document's first frame held (EDMEM-1's measure). A one-row layout keeps
    // its arrays empty, which allocates nothing, and its count in
    // `oneRowCount`, beside the width in the word the width had to itself; every
    // question asked of it is O(1). Every layout that is one row of one-cell
    // characters is kept so, whichever walk made it, so two layouts of a line
    // are `==`. Not an enum of the two forms: Darwin's arrays and dictionaries
    // leave a tag no spare bits, so one was a byte more and a layout 40 bytes
    // in place of 32 (`SoftWrapOneRowTests`).

    /// The rows, as the walk made them; empty for a one-row layout.
    private let laidOutRows: [Row]

    /// Each character's width in cells, by offset, a newline's 0: a byte
    /// each, for a width under 255 — every character but a tab past a stop
    /// that far out — and 255 for one whose width is in ``wideCells``. An
    /// `Int` each was 8 bytes a character for every width an editor kept its
    /// document wrapped at, the most of what a large text cost (tuitree's M4
    /// feedback, item 3). Read through ``cellWidth(at:)``. Empty for a one-row
    /// layout, whose every character is one cell.
    private let narrowWidths: [UInt8]

    /// The widths of 255 cells and more, by offset.
    private let wideCells: [Int: Int]

    /// The width, in 32 bits beside `oneRowCount`: a width of more than
    /// two billion cells is taken as that many, which no line reaches.
    private let packedWidth: Int32

    /// A one-row layout's characters, no more than its width; 0 for any other.
    private let oneRowCount: Int32

    /// Whether every character is one cell, on one row: a one-row layout,
    /// whose columns are its offsets.
    private var isOneRow: Bool { laidOutRows.isEmpty }

    /// The cells the character at `offset` takes; a newline's is 0.
    func cellWidth(at offset: Int) -> Int {
        guard !isOneRow else {
            precondition(offset >= 0 && offset < Int(oneRowCount), "Character offset out of range")
            return 1
        }
        let narrow = narrowWidths[offset]
        return narrow == .max ? wideCells[offset, default: Int(narrow)] : Int(narrow)
    }

    /// Each character's width in cells, by offset: for a test, which reads
    /// them all.
    var cellWidths: [Int] { (0..<characterCount).map(cellWidth(at:)) }

    /// The cells a row may draw on. Text wraps at one fewer (the margin).
    var width: Int { Int(packedWidth) }

    /// The number of characters laid out — the largest caret offset.
    var characterCount: Int { isOneRow ? Int(oneRowCount) : narrowWidths.count }

    /// A layout of `count` characters of one cell each, on one row, `width`
    /// cells wide: `count` no more than the width, which a row that fits is.
    private init(oneRow count: Int, width: Int) {
        (laidOutRows, narrowWidths, wideCells) = ([], [], [:])
        packedWidth = Int32(clamping: width)
        oneRowCount = Int32(clamping: count)
    }

    /// Lays out `characters` in rows `width` cells wide.
    ///
    /// - Parameters:
    ///   - characters: The text, as characters.
    ///   - width: The cells a row may draw on, the margin included.
    ///   - cellWidth: A character's width in cells. Called for every character
    ///     that is not a newline.
    init(_ characters: TextCharacters, width: Int, cellWidth: (Character) -> Int) {
        self.init(characters, width: width) { character, column in column + cellWidth(character) }
    }

    /// Lays out an editor's line in rows `width` cells wide, each character
    /// advancing as `TabLayout.advance(from:over:tabWidth:)` says: a tab to
    /// its next stop, the stops counted from its row's start.
    ///
    /// A line of ASCII is walked through its bytes, each told from its byte
    /// alone (`TabLayout.advance(from:overASCII:tabWidth:)`). A wrap reads
    /// each character two or three times, and made into a `Character`,
    /// compared with a space, a tab and the newlines and measured, the
    /// characters were 90% of the time a document took to wrap (EDMEM-2).
    /// One that fits its row and holds no tab and no newline is not walked:
    /// each of its characters is one cell, and it is one row.
    init(_ characters: TextCharacters, width: Int, tabWidth: TabWidth) {
        let laid = unsafe characters.withASCIIBytes { bytes in
            let width = Self.packable(width)
            if bytes.count < width, unsafe !bytes.contains(where: { (0x09...0x0D).contains($0) }) {
                return Self(oneRow: bytes.count, width: width)
            }
            return unsafe Self(laying: bytes, width: width, measure: ASCIITabs(tabWidth: tabWidth))
        }
        if let laid {
            self = laid
        } else {
            self.init(characters, width: width) { character, column in
                TabLayout.advance(from: column, over: character, tabWidth: tabWidth)
            }
        }
    }

    /// Lays out `characters` in rows `width` cells wide, each character's
    /// width depending on the column it starts at, counted from its row's
    /// start.
    ///
    /// - Parameters:
    ///   - characters: The text, as characters.
    ///   - width: The cells a row may draw on, the margin included.
    ///   - advance: The column after a character that starts at `column` —
    ///     ``TabLayout/advance(from:over:tabWidth:)``'s shape. Called for every
    ///     character that is not a newline, perhaps twice: once as the row
    ///     before it looks for where to break, and once on its own row.
    init(_ characters: TextCharacters, width: Int, advance: (_ character: Character, _ column: Int) -> Int) {
        // An ASCII line walked through its bytes, which a wrap reads two or
        // three times a character: through the string's index arithmetic it
        // was 80 ms of `bigtext-find`'s first click (EDMEM-1).
        self = withoutActuallyEscaping(advance) { advance in
            let laid = unsafe characters.withASCIIBytes { bytes in
                unsafe Self(laying: bytes, width: width, measure: ASCIIAdvance(step: advance))
            }
            return laid ?? Self(laying: characters, width: width, measure: CharacterAdvance(step: advance))
        }
    }

    /// `init(_:width:advance:)` of any characters, each read and measured
    /// as a character: the walk the byte walks are checked against
    /// (`SoftWrapLayoutTests`).
    init<Characters: RandomAccessCollection<Character>>(
        walking characters: Characters, width: Int, advance: (_ character: Character, _ column: Int) -> Int
    ) where Characters.Index == Int {
        self = withoutActuallyEscaping(advance) { advance in
            Self(laying: characters, width: width, measure: CharacterAdvance(step: advance))
        }
    }

    /// Lays out `text`, its units indexed from 0, as `measure` measures them.
    private init<Text: RandomAccessCollection, Measure: SoftWrapMeasure>(
        laying text: Text, width: Int, measure: Measure
    ) where Text.Index == Int, Text.Element == Measure.Unit {
        let width = Self.packable(width)
        let budget = max(1, width - 1)
        var widths = WidthWriter(count: text.count)
        var rows: [Row] = []
        var start = 0
        for offset in 0..<text.count where measure.isNewline(text[offset]) {
            Self.wrap(text, from: start, to: offset, budget: budget, measure: measure, widths: &widths, into: &rows)
            start = offset + 1
        }
        Self.wrap(text, from: start, to: text.count, budget: budget, measure: measure, widths: &widths, into: &rows)
        if rows.count == 1, widths.wide.isEmpty, widths.narrow.allSatisfy({ $0 == 1 }) {
            self.init(oneRow: text.count, width: width)
        } else {
            self.init(rows: rows, widths: widths, width: width)
        }
    }

    /// A layout keeping `rows` and `widths`, `width` cells wide.
    private init(rows: [Row], widths: WidthWriter, width: Int) {
        (laidOutRows, narrowWidths, wideCells) = (rows, widths.narrow, widths.wide)
        (packedWidth, oneRowCount) = (Int32(clamping: width), 0)
    }

    /// `width` as a layout keeps it: at least one cell, and at most what 32
    /// bits hold (`packedWidth`).
    private static func packable(_ width: Int) -> Int {
        min(max(1, width), Int(Int32.max))
    }

    /// Lays one paragraph, `start..<end`, into rows of `budget` cells, the last
    /// of which ends the paragraph, writing each character's width on its own
    /// row into `widths`.
    private static func wrap<Text: RandomAccessCollection, Measure: SoftWrapMeasure>(
        _ text: Text, from start: Int, to end: Int, budget: Int, measure: Measure, widths: inout WidthWriter,
        into rows: inout [Row]
    ) where Text.Index == Int, Text.Element == Measure.Unit {
        var rowStart = start
        while true {
            // Each row walks from its own start, so a character the row before
            // measured while looking for its break is measured again here, at
            // the column it really starts at.
            let rowEnd = rowBreak(text, from: rowStart, to: end, budget: budget, measure: measure, widths: &widths)
            guard rowEnd < end else {
                rows.append(Row(start: rowStart, end: end, endsParagraph: true))
                return
            }
            rows.append(Row(start: rowStart, end: rowEnd, endsParagraph: false))
            rowStart = rowEnd
        }
    }

    /// Where the row starting at `start` ends: `end` when the rest of the
    /// paragraph fits, else the last place it may break.
    private static func rowBreak<Text: RandomAccessCollection, Measure: SoftWrapMeasure>(
        _ text: Text, from start: Int, to end: Int, budget: Int, measure: Measure, widths: inout WidthWriter
    ) -> Int where Text.Index == Int, Text.Element == Measure.Unit {
        var cells = 0  // the row's cells, not counting a run of spaces at its end
        var hanging = 0  // that run's cells
        var lastBreak: Int?  // the latest offset the row may end at
        var offset = start
        while offset < end {
            let unit = text[offset]
            let column = cells + hanging
            let width = max(0, measure.advance(over: unit, from: column) - column)
            widths.write(width, at: offset)
            if measure.hangs(unit) {
                hanging += width
                offset += 1
                lastBreak = offset
                continue
            }
            if width >= 2, offset > start { lastBreak = offset }
            guard cells + hanging + width <= budget else {
                if let lastBreak, lastBreak > start { return lastBreak }
                // One character wider than the whole row still goes on it.
                return offset > start ? offset : offset + 1
            }
            cells += hanging + width
            hanging = 0
            offset += 1
            if width >= 2 { lastBreak = offset }
        }
        return end
    }

    // MARK: - Offsets and rows

    /// The row the caret at `offset` is drawn on.
    func row(of offset: Int, affinity: TextSelectionAffinity) -> Int {
        let offset = min(max(0, offset), characterCount)
        // The last row starting at or before the offset.
        var low = 0
        var high = rows.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rows[middle].start <= offset { low = middle } else { high = middle - 1 }
        }
        if affinity == .upstream, low > 0, rows[low].start == offset, !rows[low - 1].endsParagraph {
            return low - 1
        }
        return low
    }

    /// The cells `row`'s characters before `offset` take.
    func cells(inRow row: Int, before offset: Int) -> Int {
        let row = rows[row]
        let upper = min(max(row.start, offset), row.end)
        // A one-row layout's cells are its characters.
        if isOneRow { return upper - row.start }
        return (row.start..<upper).reduce(0) { $0 + cellWidth(at: $1) }
    }

    /// The column the caret at `offset` is drawn at on `row`: the cells before
    /// it, held to the last cell.
    func column(of offset: Int, inRow row: Int) -> Int {
        min(cells(inRow: row, before: offset), width - 1)
    }

    /// The largest offset on `row` whose caret is drawn there: the row's end
    /// where it ends a paragraph, or under `.upstream`; otherwise the offset
    /// before its last character, since the end is drawn on the next row.
    func lastCaretOffset(inRow row: Int, affinity: TextSelectionAffinity) -> Int {
        let row = rows[row]
        guard !row.endsParagraph, affinity != .upstream else { return row.end }
        return max(row.start, row.end - 1)
    }

    /// The smallest offset on `row` whose caret is drawn there: the row's
    /// start, except under `.upstream` on a row that continues a paragraph,
    /// whose start is drawn at the end of the row before it
    /// (``row(of:affinity:)``), so its first caret is after its first
    /// character.
    func firstCaretOffset(inRow row: Int, affinity: TextSelectionAffinity) -> Int {
        let span = rows[row]
        guard affinity == .upstream, row > 0, !rows[row - 1].endsParagraph else { return span.start }
        return min(span.start + 1, span.end)
    }

    /// The caret offset on `row` nearest `column`: before the character whose
    /// cells hold the column, or the row's last caret offset past its text —
    /// and always one whose caret is drawn on `row` by `affinity`, so a caret
    /// moved to a row, or clicked onto one, is on it. Under `.upstream` the
    /// start of a wrapped row is the end of the row before, and Down landing
    /// there drew the caret back on the row it came from: every later Down
    /// came back to it.
    func offset(inRow row: Int, atColumn column: Int, affinity: TextSelectionAffinity) -> Int {
        offset(
            inRow: row, atColumn: column, first: firstCaretOffset(inRow: row, affinity: affinity),
            last: lastCaretOffset(inRow: row, affinity: affinity))
    }

    /// The offset a selection's end takes at `column` of `row` — where a drag
    /// starts or reaches, or a Shift-click extends to: as
    /// ``offset(inRow:atColumn:affinity:)``, except that a row's first
    /// character is always reachable. A selection's end is drawn as the edge
    /// of a range, never as a caret, so `.upstream`'s lean has nothing to say
    /// about it: under it a drag starting on a wrapped row's first cell could
    /// not take that row's first character, "bbbb" selecting as "bbb".
    func selectionOffset(inRow row: Int, atColumn column: Int, affinity: TextSelectionAffinity) -> Int {
        offset(
            inRow: row, atColumn: column, first: rows[row].start,
            last: lastCaretOffset(inRow: row, affinity: affinity))
    }

    /// The offset before the character whose cells hold `column`, held to
    /// `first...last`, or `last` past the row's text.
    private func offset(inRow row: Int, atColumn column: Int, first: Int, last: Int) -> Int {
        if isOneRow {
            // A cell a character: the one at the column, if the row reaches it.
            let span = rows[row]
            let offset = span.start + max(0, column)
            return offset < span.end ? max(first, min(offset, last)) : last
        }
        var cellX = 0
        for offset in rows[row].start..<rows[row].end {
            let next = cellX + cellWidth(at: offset)
            if column < next { return max(first, min(offset, last)) }
            cellX = next
        }
        return last
    }
}

// MARK: - What a wrap measures

/// What a wrap asks of each unit of its text — a character, or the byte an
/// ASCII character is. A protocol, not closures, so each walk is compiled for
/// its own units and asks them nothing through a call it cannot see into.
private protocol SoftWrapMeasure {
    associatedtype Unit

    /// Whether `unit` ends a paragraph: drawn nowhere, in no cells.
    func isNewline(_ unit: Unit) -> Bool

    /// Whether a row may break after `unit`, hanging it past the margin: a
    /// space or a tab.
    func hangs(_ unit: Unit) -> Bool

    /// The column after `unit` when it starts at `column`.
    func advance(over unit: Unit, from column: Int) -> Int
}

/// Characters, each measured by `step`.
private struct CharacterAdvance: SoftWrapMeasure {
    let step: (Character, Int) -> Int

    func isNewline(_ unit: Character) -> Bool { unit.isNewline }
    func hangs(_ unit: Character) -> Bool { unit == " " || unit == "\t" }
    func advance(over unit: Character, from column: Int) -> Int { step(unit, column) }
}

/// ASCII characters as their bytes, each measured by `step` as the character
/// it is. A byte is a newline as its character is: LF, VT, FF or CR, the
/// ASCII ones of `Character.isNewline`'s.
private struct ASCIIAdvance: SoftWrapMeasure {
    let step: (Character, Int) -> Int

    func isNewline(_ unit: UInt8) -> Bool { (0x0A...0x0D).contains(unit) }
    func hangs(_ unit: UInt8) -> Bool { unit == 0x20 || unit == 0x09 }
    func advance(over unit: UInt8, from column: Int) -> Int { step(TextCharacters.character(ascii: unit), column) }
}

/// An editor's ASCII line as its bytes: each one cell, a tab to its next stop.
private struct ASCIITabs: SoftWrapMeasure {
    let tabWidth: TabWidth

    func isNewline(_ unit: UInt8) -> Bool { (0x0A...0x0D).contains(unit) }
    func hangs(_ unit: UInt8) -> Bool { unit == 0x20 || unit == 0x09 }
    func advance(over unit: UInt8, from column: Int) -> Int {
        TabLayout.advance(from: column, overASCII: unit, tabWidth: tabWidth)
    }
}

/// Each character's width as a wrap writes it: a byte each, one of 255 and
/// more kept beside (`SoftWrapLayout`'s `narrowWidths` and `wideCells`),
/// written straight into them rather than through an `Int` a character. A
/// character measured twice — by the row before, looking for its break, and
/// on its own row — keeps its second width.
private struct WidthWriter {
    var narrow: [UInt8]
    var wide: [Int: Int] = [:]

    init(count: Int) {
        narrow = [UInt8](repeating: 0, count: count)
    }

    mutating func write(_ cells: Int, at offset: Int) {
        if cells >= Int(UInt8.max) {
            narrow[offset] = .max
            wide[offset] = cells
        } else {
            if narrow[offset] == .max { wide[offset] = nil }
            narrow[offset] = UInt8(cells)
        }
    }
}
