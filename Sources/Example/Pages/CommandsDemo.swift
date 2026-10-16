//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The commands a focused view answers: `.onMoveCommand` (the arrows, as a
/// direction), `.onDeleteCommand` (Delete) and `.onExitCommand` (Escape) — a
/// board whose cursor the arrows move, Delete clears the cell under, and
/// Escape fills again.
struct CommandsDemo: View {
    @State private var cursor = (column: 0, row: 0)
    @State private var cleared: Set<Int> = []
    @FocusState private var isFocused: Bool

    private static let size = 4

    var body: some View {
        DemoSection("page.focus.commandsSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.focus.commandsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.size, id: \.self) { row in
                        Text(line(row))
                    }
                }
                .padding(.horizontal, 1)
                .border(isFocused ? .palette.accent : .palette.border)
                .focusable()
                .focused($isFocused)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: cursor.column = max(0, cursor.column - 1)
                    case .right: cursor.column = min(Self.size - 1, cursor.column + 1)
                    case .up: cursor.row = max(0, cursor.row - 1)
                    case .down: cursor.row = min(Self.size - 1, cursor.row + 1)
                    @unknown default: break
                    }
                }
                .onDeleteCommand { cleared.insert(cursor.row * Self.size + cursor.column) }
                .onExitCommand { cleared.removeAll() }
            }
        }
    }

    /// One row of the board: a filled or cleared cell each, the cursor's
    /// bracketed.
    private func line(_ row: Int) -> String {
        (0..<Self.size).map { column in
            let cell = cleared.contains(row * Self.size + column) ? "·" : "■"
            return (column, row) == cursor ? "[\(cell)]" : " \(cell) "
        }.joined()
    }
}
