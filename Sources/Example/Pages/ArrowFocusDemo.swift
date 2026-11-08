//  🖥️ TUI — A Terminal UI framework for Swift
//  ArrowFocusDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Eight rows of twelve buttons in a scroll view much smaller than they are,
/// where the two ways the arrow keys can move the focus part: in Tab order,
/// Down goes along the row to the next button; with `TUI_ARROW_FOCUS=geometric`
/// it goes to the button below, out of sight or not, and the grid scrolls to
/// show it. Its own focus section, so the arrows stay in the grid.
struct ArrowFocusDemo: View {
    var body: some View {
        DemoSection("page.focus.arrowsSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.focus.arrowsDescription")
                    .foregroundStyle(.palette.foregroundSecondary)
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<Self.rows.count, id: \.self) { row in
                            HStack(spacing: 2) {
                                ForEach(0..<Self.columns, id: \.self) { column in
                                    // A String, not a literal: a cell's name,
                                    // not a key for the string tables.
                                    Button(Self.name(row: row, column: column)) {}
                                }
                            }
                        }
                    }
                }
                .frame(width: 36, height: 4)
                .focusSection("focus-arrows-grid")
            }
        }
    }

    /// The rows' letters.
    private static let rows = ["A", "B", "C", "D", "E", "F", "G", "H"]

    /// How many buttons each row holds.
    private static let columns = 12

    /// The cell's name, its row as a letter and its column as two digits, so
    /// every button is as wide as every other: `A01` … `H12`.
    private static func name(row: Int, column: Int) -> String {
        let number = column + 1
        return "\(rows[row])\(number < 10 ? "0" : "")\(number)"
    }
}
