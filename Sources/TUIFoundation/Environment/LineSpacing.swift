//  🖥️ TUI — A Terminal UI framework for Swift
//  LineSpacing.swift
//
//  Blank rows between the wrapped lines of a `Text`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Environment

private struct LineSpacingKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Blank rows inserted between the wrapped lines of a ``Text``, in **rows**.
    ///
    /// Set via ``View/lineSpacing(_:)``. Default: none.
    public var lineSpacing: Int {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = max(0, newValue) }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the space between the wrapped lines of text in this view.
    ///
    /// ```swift
    /// Text(longProse)
    ///     .lineSpacing(1)          // one blank row between lines
    /// ```
    ///
    /// - Note: SwiftUI measures this in points and permits fractions. A terminal
    ///   can only insert whole rows, so the unit here is **rows** and the type is
    ///   `Int` — the argument label is unchanged, so the call site reads the
    ///   same. Negative values clamp to zero; text cannot overlap itself on a
    ///   cell grid.
    ///
    /// Spacing goes BETWEEN lines, so a single-line text is unaffected however
    /// large the value, and *n* lines occupy `n + (n − 1) × spacing` rows.
    ///
    /// It also does not change what ``View/lineLimit(_:)-(Int?)`` counts: a limit is a
    /// number of LINES OF TEXT, as in SwiftUI, not of rows on screen. Three
    /// lines at spacing 1 are three lines and five rows.
    ///
    /// - Parameter lineSpacing: Blank rows between lines.
    /// - Returns: A view whose text is spaced.
    nonisolated public func lineSpacing(_ lineSpacing: Int) -> some View {
        environment(\.lineSpacing, max(0, lineSpacing.heldToStatedLength))
    }
}

// MARK: - Row arithmetic

/// Converting between lines of text and the rows they occupy once spacing is
/// interleaved.
///
/// One place, because the measure and the render both need it and must agree:
/// the measure reports the total, the render decides how many lines it may draw
/// to stay inside the space it was given. That is the measure/render parity bug
/// class — reserve rows nothing fills, or draw past what the parent allowed.
enum LineSpacingRows {
    /// The display rows `lines` lines occupy at `spacing`.
    ///
    /// Gaps go BETWEEN lines, so *n* lines carry *n − 1* of them.
    static func displayRows(forLines lines: Int, spacing: Int) -> Int {
        guard lines > 0 else { return 0 }
        guard spacing > 0 else { return lines }
        return lines + (lines - 1) * spacing
    }

    /// The most lines of text that fit in `rows` display rows at `spacing`.
    ///
    /// The inverse of ``displayRows(forLines:spacing:)``, and never zero for a
    /// positive budget: one line always fits in one row, since its gap would
    /// come after it and is never drawn.
    static func lines(fittingRows rows: Int, spacing: Int) -> Int {
        guard rows > 0 else { return 0 }
        guard spacing > 0 else { return rows }
        return max(1, (rows + spacing) / (spacing + 1))
    }

    // MARK: With a paragraph's line height

    // An attributed text's paragraphs may each take more rows a line
    // (`lineHeight`, `Text+ParagraphStyle.swift`): `gaps[i]` blank rows after
    // line `i`, on top of `spacing`, and none after the last line drawn. A line
    // past `gaps`' end has none (a reservation's padding). `nil` is the plain
    // arithmetic above, so a text with no line height pays nothing.

    /// The display rows `lines` lines occupy at `spacing`, line `i` followed by
    /// `gaps[i]` more blank rows unless it is the last.
    static func displayRows(forLines lines: Int, spacing: Int, gaps: [Int]?) -> Int {
        guard let gaps, lines > 1 else { return displayRows(forLines: lines, spacing: spacing) }
        return displayRows(forLines: lines, spacing: spacing) + gaps.prefix(lines - 1).reduce(0, +)
    }

    /// The most lines of text that fit in `rows` display rows at `spacing` and
    /// `gaps`: the inverse of ``displayRows(forLines:spacing:gaps:)``, and never
    /// zero for a positive budget.
    static func lines(fittingRows rows: Int, spacing: Int, gaps: [Int]?) -> Int {
        guard let gaps else { return lines(fittingRows: rows, spacing: spacing) }
        guard rows > 0 else { return 0 }
        var (count, used) = (1, 1)
        // Line by line while the lines have gaps of their own; past them, each
        // takes `spacing + 1`, so the rest is a division (a budget may be huge).
        while count - 1 < gaps.count {
            let next = spacing + gaps[count - 1] + 1
            guard used + next <= rows else { return count }
            used += next
            count += 1
        }
        return count + (rows - used) / (spacing + 1)
    }

    /// `rows` with `spacing` copies of `blank` after each but the last, and
    /// `gaps[i]` more after row `i`.
    static func interleaved<Row>(_ rows: [Row], spacing: Int, gaps: [Int]?, blank: Row) -> [Row] {
        guard let gaps, rows.count > 1 else { return interleaved(rows, spacing: spacing, blank: blank) }
        var spaced: [Row] = []
        spaced.reserveCapacity(displayRows(forLines: rows.count, spacing: spacing, gaps: gaps))
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let gap = index - 1 < gaps.count ? gaps[index - 1] : 0
                spaced.append(contentsOf: repeatElement(blank, count: spacing + gap))
            }
            spaced.append(row)
        }
        return spaced
    }

    /// The display row line `line` is drawn on at `spacing` and `gaps`.
    static func row(ofLine line: Int, spacing: Int, gaps: [Int]?) -> Int {
        line * (spacing + 1) + (gaps?.prefix(line).reduce(0, +) ?? 0)
    }

    /// `rows` with `spacing` copies of `blank` interleaved between them.
    ///
    /// Generic because a spaced `Text` interleaves two parallel arrays — the
    /// styled lines and their cell widths — and they must gain their gaps in
    /// lockstep or a parent aligning the column reads a width against the wrong
    /// row.
    static func interleaved<Row>(_ rows: [Row], spacing: Int, blank: Row) -> [Row] {
        guard spacing > 0, rows.count > 1 else { return rows }
        var spaced: [Row] = []
        spaced.reserveCapacity(displayRows(forLines: rows.count, spacing: spacing))
        for (index, row) in rows.enumerated() {
            if index > 0 { spaced.append(contentsOf: repeatElement(blank, count: spacing)) }
            spaced.append(row)
        }
        return spaced
    }
}
