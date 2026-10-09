//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnWidth.swift
//
//  How wide a table column is asked to be, and how the columns that share the
//  leftover width divide it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - ColumnWidth

/// The two TUI-only ways to size a table column, beyond SwiftUI's
/// `width(_:)` and `width(min:ideal:max:)`.
///
/// ```swift
/// TableColumn("Name", value: \.name).width(.fit)
/// TableColumn("Notes", value: \.notes).width(.ratio(0.5))
/// ```
public enum ColumnWidth: Sendable, Equatable {
    /// Proportional width as a ratio of total available space.
    /// For example, `.ratio(0.5)` takes 50% of available width.
    case ratio(Double)

    /// Sizes the column to fit its content — the width of the widest of the
    /// column header and every cell value in the column (so nothing in the
    /// column is truncated, space permitting). This mirrors the content-based
    /// sizing of a SwiftUI table's automatic columns.
    ///
    /// It scans all of the column's values to find that width, so it is O(rows);
    /// for very large tables where a per-frame content scan is undesirable,
    /// prefer a fixed width or the default. The fitted width is stable as the
    /// table scrolls (it considers every row, not just the visible ones), so
    /// the columns do not jump while scrolling.
    case fit
}

// MARK: - The width a column was given

/// How a column is sized, from whichever of its width modifiers spoke last.
enum _TableColumnWidth: Equatable {
    /// Shares the width the other columns leave: starting from `ideal` (or
    /// `min`), any space left over split evenly, and never outside
    /// `min...max`. With no bounds at all this is the default column, and the
    /// columns that share split the leftover evenly.
    case flexible(min: Int?, ideal: Int?, max: Int?)

    /// Exactly this many cells.
    case fixed(Int)

    /// A proportion of the width available to the columns.
    case ratio(Double)

    /// The widest of the header and every cell.
    case fit

    /// The default: a flexible column with no bounds.
    static var flexible: Self { .flexible(min: nil, ideal: nil, max: nil) }

    /// Whether the column grows with the width on offer.
    var growsWithAvailableWidth: Bool {
        switch self {
        case .flexible, .ratio: true
        case .fixed, .fit: false
        }
    }
}

// MARK: - Sharing the leftover width

enum TableFlexibleWidths {
    /// Divides `available` cells among flexible columns with these bounds.
    ///
    /// SwiftUI's rule, measured on macOS 26.2: a column starts at its ideal
    /// width, and the space left over is split evenly among the columns that
    /// can still grow (with `min: 40, ideal: 90, max: 200`, `ideal: 120` and an
    /// unbounded column of ideal 100 — `NSTableColumn`'s default — sharing 457
    /// points, they ended at 139, 169 and 149: each ideal plus 49). Here an
    /// unbounded column's ideal is zero, so columns with no bounds split the
    /// space evenly, the earliest getting the odd cell — exactly the rule the
    /// table had before columns could be bounded.
    ///
    /// When the ideals do not fit, every column gets its minimum and what is
    /// left goes to the columns still below their ideal, evenly. Columns whose
    /// minimums alone overflow keep them, as a fixed column keeps its width;
    /// the row clips.
    static func widths(
        _ bounds: [(min: Int?, ideal: Int?, max: Int?)], sharing available: Int
    ) -> [Int] {
        let floors = bounds.map { Swift.max(0, $0.min ?? 0) }
        let ceilings = bounds.indices.map { index in
            Swift.max(floors[index], bounds[index].max ?? Int.max)
        }
        let starts = bounds.indices.map { index in
            Swift.min(ceilings[index], Swift.max(floors[index], bounds[index].ideal ?? 0))
        }
        let wanted = starts.reduce(0, +)
        var widths: [Int]
        var spare: Int
        var limits: [Int]
        if wanted <= available {
            widths = starts
            spare = available - wanted
            limits = ceilings
        } else {
            widths = floors
            spare = Swift.max(0, available - floors.reduce(0, +))
            limits = starts
        }
        var open = widths.indices.filter { widths[$0] < limits[$0] }
        while spare > 0, !open.isEmpty {
            let share = spare / open.count
            let odd = spare % open.count
            var given = 0
            for (offset, index) in open.enumerated() {
                let grant = Swift.min(share + (offset < odd ? 1 : 0), limits[index] - widths[index])
                widths[index] += grant
                given += grant
            }
            guard given > 0 else { break }
            spare -= given
            open = open.filter { widths[$0] < limits[$0] }
        }
        return widths
    }
}
