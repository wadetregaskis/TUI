//  🖥️ TUI — A Terminal UI framework for Swift
//  ArrowFocusDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Three rows of three buttons, where the two ways the arrow keys can move the
/// focus part: in Tab order, Down goes along the row to the next button; with
/// `TUI_ARROW_FOCUS=geometric` it goes to the button below. Its own focus
/// section, so the arrows stay in the grid.
struct ArrowFocusDemo: View {
    var body: some View {
        DemoSection("page.focus.arrowsSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.focus.arrowsDescription")
                    .foregroundStyle(.palette.foregroundSecondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { column in
                                // A String, not a literal: a cell's name, not a
                                // key for the string tables.
                                Button(Self.name(row: row, column: column)) {}
                            }
                        }
                    }
                }
                .focusSection("focus-arrows-grid")
            }
        }
    }

    /// The cell's name, its row as a letter and its column as a digit: `A1` … `C3`.
    private static func name(row: Int, column: Int) -> String {
        let rows = ["A", "B", "C"]
        return "\(rows[row])\(column + 1)"
    }
}
