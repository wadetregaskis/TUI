//  🖥️ TUI — A Terminal UI framework for Swift
//  DragDropClip.swift
//
//  `dragdrop`: a task board, all by mouse: a card dragged from one column to
//  the next, a card dragged to the top of its own column, and three of Done's
//  cards selected (a click and a Shift-click) and dragged up their column
//  together; then the three moves undone.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let dragDropClip = Clip(
    id: "dragdrop",
    title: "Drag & drop",
    columns: 124,
    rows: 30,
    output: 800,
    script: dragDropScript(),
    run: { await DragDropApp.main() }
)

/// Where the board's cards sit (1-based cells, as a mouse report counts):
/// three columns of 38 two apart, the first card on row 7.
private enum Board {
    static let todo = 12
    static let doing = 52
    static let done = 92
    static let firstCard = 7
}

/// A Shift-click on a cell: the selection extended to it.
private func shiftClick(_ column: Int, _ row: Int) -> [Step] {
    // Shift is the report's +4.
    [.mouse(4, column, row), .wait(0.08), .mouse(4, column, row, release: true)]
}

private func dragDropScript() -> [Step] {
    let card = { (column: Int, index: Int) in (column, Board.firstCard + index) }
    var script: [Step] = [.camera(Shot(x: 0, y: 3, width: 84, height: 15)), .wait(0.8)]
    // Across: To do's second card into Doing, between its first two.
    script += Step.glide(from: (70, 20), to: card(Board.todo, 1), over: 0.7)
    script += Step.drag(from: card(Board.todo, 1), to: card(Board.doing, 1), interval: 0.035) + [.wait(1.0)]
    // Within a column: Doing's last card, now its fourth, to its top.
    script += Step.glide(from: card(Board.doing, 1), to: card(Board.doing, 3), over: 0.4)
    script += Step.drag(from: card(Board.doing, 3), to: card(Board.doing, 0), interval: 0.12) + [.wait(1.0)]
    // Several at once: Done's second card clicked, its fourth Shift-clicked —
    // three selected — and the three dragged to the column's top together.
    script += Step.glide(from: card(Board.doing, 0), to: card(Board.done, 1), over: 0.6)
    script += Step.click(Board.done, Board.firstCard + 1) + [.wait(0.4)]
    script += Step.glide(from: card(Board.done, 1), to: card(Board.done, 3), over: 0.3)
    script += shiftClick(Board.done, Board.firstCard + 3) + [.wait(0.7)]
    script += Step.drag(from: card(Board.done, 2), to: card(Board.done, 0), interval: 0.18) + [.wait(1.2)]
    // Undone, the three moves, and back where it began.
    script += Step.glide(from: card(Board.done, 0), to: (70, 20), over: 0.6)
    script += [Step.control("z"), .wait(0.5), Step.control("z"), .wait(0.5), Step.control("z"), .wait(1.2)]
    return script
}

struct DragDropApp: App {
    var body: some Scene {
        WindowGroup("TUI · Board") {
            TaskBoard()
                .palette(SystemPalette(.amber))
        }
    }
}

/// A card on the board.
struct BoardCard: Identifiable, Hashable {
    let id: String
    let tag: String
    /// Whose it is, by initials.
    let owner: String
    /// 0 low, 1 normal, 2 high.
    let priority: Int
}

/// What a drag carries: the card, and the column it left.
struct BoardDrag {
    let column: Int
    let id: String
}

/// A task board: To do, Doing, Done.
struct TaskBoard: View {
    @Environment(\.undoManager) private var undoManager
    @State private var columns: [[BoardCard]] = [
        [BoardCard(id: "Sticky headers", tag: "tables", owner: "AL", priority: 2),
         BoardCard(id: "Kitty image cache", tag: "images", owner: "GH", priority: 1),
         BoardCard(id: "Warp quirks survey", tag: "terms", owner: "KJ", priority: 0),
         BoardCard(id: "Braille dithering", tag: "images", owner: "GH", priority: 1),
         BoardCard(id: "Menu type-select", tag: "menus", owner: "AL", priority: 0),
         BoardCard(id: "Sheet detents", tag: "modals", owner: "MH", priority: 1),
         BoardCard(id: "Focus rings", tag: "focus", owner: "KJ", priority: 2)],
        [BoardCard(id: "Spring curves", tag: "anim", owner: "MH", priority: 2),
         BoardCard(id: "Column resizing", tag: "tables", owner: "AL", priority: 1),
         BoardCard(id: "OSC 8 links", tag: "terms", owner: "GH", priority: 0)],
        [BoardCard(id: "Grapheme widths", tag: "text", owner: "KJ", priority: 2),
         BoardCard(id: "Contrast floor", tag: "theme", owner: "MH", priority: 1),
         BoardCard(id: "SGR mouse parser", tag: "input", owner: "AL", priority: 1),
         BoardCard(id: "Undo grouping", tag: "edit", owner: "GH", priority: 0)],
    ]
    /// Each column's selected cards: several, so they can be dragged together.
    @State private var selections: [Set<String>] = [[], [], []]

    private let titles = ["To do", "Doing", "Done"]

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(0..<3, id: \.self) { column in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(verbatim: titles[column]).bold()
                        Text(verbatim: "\(columns[column].count)").foregroundStyle(.palette.foregroundTertiary)
                    }
                    List(selection: selectionBinding(column)) {
                        ForEach(columns[column]) { card in
                            // Done's cards are dropped into, never dragged out: its own
                            // reorder takes a drag there, and carries every selected card.
                            if column == 2 {
                                cardRow(card)
                            } else {
                                cardRow(card).draggable(BoardDrag(column: column, id: card.id))
                            }
                        }
                        .dropDestination(for: BoardDrag.self) { drops, index in
                            let before = columns
                            for drop in drops { move(drop, to: column, at: index) }
                            register(before)
                        }
                        .onMove { source, destination in
                            let before = columns
                            columns[column].move(fromOffsets: source, toOffset: destination)
                            register(before)
                        }
                    }
                }
                .frame(width: 38)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Board · TUI 1.0") }
        }
    }

    /// A card: its priority, title, tag and owner.
    private func cardRow(_ card: BoardCard) -> some View {
        HStack(spacing: 1) {
            Text(verbatim: "●").foregroundStyle(priorityColour(card.priority))
            Text(verbatim: card.id).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 0)
            Text(verbatim: " \(card.tag) ")
                .foregroundStyle(.palette.background)
                .background(tagColour(card.tag))
            Text(verbatim: card.owner).foregroundStyle(.palette.foregroundSecondary)
        }
    }

    private func priorityColour(_ priority: Int) -> Color {
        [Color.palette.foregroundTertiary, .palette.warning, .palette.error][priority]
    }

    /// Each tag its own colour, the same wherever it shows.
    private func tagColour(_ tag: String) -> Color {
        let colours: [Color] = [
            .rgb(120, 170, 255), .rgb(255, 170, 90), .rgb(140, 220, 140), .rgb(230, 130, 220),
            .rgb(250, 220, 100), .rgb(120, 220, 220),
        ]
        return colours[tag.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colours.count]
    }

    private func selectionBinding(_ column: Int) -> Binding<Set<String>> {
        Binding(get: { selections[column] }, set: { selections[column] = $0 })
    }

    /// Puts the dragged card at `index` in `column`: `index` counts the
    /// column's cards as they were before the move, the dragged one included
    /// if it came from this column (as `onMove`'s destination does).
    private func move(_ drop: BoardDrag, to column: Int, at index: Int) {
        guard let from = columns[drop.column].firstIndex(where: { $0.id == drop.id }) else { return }
        let card = columns[drop.column].remove(at: from)
        var target = index
        if drop.column == column, from < index { target -= 1 }
        columns[column].insert(card, at: min(max(0, target), columns[column].count))
        selections[column] = [card.id]
    }

    private func register(_ before: [[BoardCard]]) {
        guard before != columns else { return }
        let binding = $columns
        undoManager?.registerRestoring(binding, to: before, actionName: "Move")
    }
}
