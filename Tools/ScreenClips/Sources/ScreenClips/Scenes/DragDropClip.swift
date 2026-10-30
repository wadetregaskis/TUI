//  🖥️ TUI — A Terminal UI framework for Swift
//  DragDropClip.swift
//
//  `dragdrop`: a task board, all by mouse: To do's top three cards dragged
//  into Doing one at a time, landing apart; three of Done's cards selected (a
//  click and a Shift-click), dragged up their column together and undone; then
//  the three in Doing selected apart (a click and two Option-clicks) and
//  dragged back to To do together — the board as it began, so it loops.
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

/// An Option-click on a cell: its row added to the selection, the rows between
/// left out.
private func optionClick(_ column: Int, _ row: Int) -> [Step] {
    // Option is the report's Meta flag, +8.
    [.mouse(8, column, row), .wait(0.08), .mouse(8, column, row, release: true)]
}

private func dragDropScript() -> [Step] {
    let card = { (column: Int, index: Int) in (column, Board.firstCard + index) }
    // The pointer where the clip leaves it, so the loop's seam does not show.
    var script: [Step] = [.camera(Shot(x: 0, y: 3, width: 84, height: 24)), .point(column: 70, row: 20), .wait(0.8)]
    // One at a time: To do's top card across into Doing, three times, each
    // landing two rows below the last, so Doing holds them apart: rows 0, 2
    // and 4.
    var pointer = (70, 20)
    for slot in [0, 2, 4] {
        script += Step.glide(from: pointer, to: card(Board.todo, 0), over: 0.6)
        script += Step.drag(from: card(Board.todo, 0), to: card(Board.doing, slot), interval: 0.03) + [.wait(0.8)]
        pointer = card(Board.doing, slot)
    }
    // Several side by side: Done's second card clicked, its fourth
    // Shift-clicked — three selected — dragged to the column's top together,
    // and undone. The camera pans across to Done for it: at 84 columns it
    // shows To do and Doing, and Done began just past its edge.
    script += [.camera(Shot(x: 36, y: 3, width: 84, height: 24, over: 0.6))]
    script += Step.glide(from: pointer, to: card(Board.done, 1), over: 0.6)
    script += Step.click(Board.done, Board.firstCard + 1) + [.wait(0.4)]
    script += Step.glide(from: card(Board.done, 1), to: card(Board.done, 3), over: 0.3)
    script += shiftClick(Board.done, Board.firstCard + 3) + [.wait(0.7)]
    script += Step.drag(from: card(Board.done, 2), to: card(Board.done, 0), interval: 0.18) + [.wait(1.0)]
    script += [Step.control("z"), .wait(1.0)]
    // Several apart: the three cards brought into Doing, clicked and
    // Option-clicked, dragged back to the top of To do together, in their
    // order — the board as it began, so the clip loops.
    script += [.camera(Shot(x: 0, y: 3, width: 84, height: 24, over: 0.6))]
    script += Step.glide(from: card(Board.done, 0), to: card(Board.doing, 0), over: 0.6)
    script += Step.click(Board.doing, Board.firstCard) + [.wait(0.35)]
    script += Step.glide(from: card(Board.doing, 0), to: card(Board.doing, 2), over: 0.25)
    script += optionClick(Board.doing, Board.firstCard + 2) + [.wait(0.35)]
    script += Step.glide(from: card(Board.doing, 2), to: card(Board.doing, 4), over: 0.25)
    script += optionClick(Board.doing, Board.firstCard + 4) + [.wait(0.7)]
    script += Step.drag(from: card(Board.doing, 4), to: card(Board.todo, 0), interval: 0.03) + [.wait(1.0)]
    // To do's top card clicked, the one selection the board began with.
    script += Step.click(Board.todo, Board.firstCard) + [.wait(0.3)]
    script += Step.glide(from: card(Board.todo, 0), to: (70, 20), over: 0.6) + [.wait(0.6)]
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
        [BoardCard(id: "Sticky headers", tag: "tables", priority: 2),
         BoardCard(id: "Kitty image cache", tag: "images", priority: 1),
         BoardCard(id: "Warp quirks survey", tag: "terms", priority: 0),
         BoardCard(id: "Braille dithering", tag: "images", priority: 1),
         BoardCard(id: "Menu type-select", tag: "menus", priority: 0),
         BoardCard(id: "Sheet detents", tag: "modals", priority: 1),
         BoardCard(id: "Focus rings", tag: "focus", priority: 2),
         // The rest of the backlog, below what the script drags: a board as full
         // as a real one fills the 16:10 frame.
         BoardCard(id: "Bidi text runs", tag: "text", priority: 1),
         BoardCard(id: "Sixel fallback", tag: "images", priority: 0),
         BoardCard(id: "Table column pinning", tag: "tables", priority: 1),
         BoardCard(id: "Gauge tint parity", tag: "theme", priority: 0),
         BoardCard(id: "Calendar week numbers", tag: "input", priority: 0),
         BoardCard(id: "Popover arrows", tag: "modals", priority: 1),
         BoardCard(id: "Scroll anchoring", tag: "tables", priority: 2),
         BoardCard(id: "OSC 52 paste", tag: "input", priority: 1),
         BoardCard(id: "Emoji ZWJ widths", tag: "text", priority: 1),
         BoardCard(id: "Dialog default button", tag: "modals", priority: 0)],
        [BoardCard(id: "Spring curves", tag: "anim", priority: 2),
         BoardCard(id: "Column resizing", tag: "tables", priority: 1),
         BoardCard(id: "OSC 8 links", tag: "terms", priority: 0),
         BoardCard(id: "Frost backdrops", tag: "images", priority: 2),
         BoardCard(id: "Zoom scaling", tag: "anim", priority: 1),
         BoardCard(id: "Menu mnemonics", tag: "menus", priority: 0),
         BoardCard(id: "Caret blink", tag: "focus", priority: 0)],
        [BoardCard(id: "Grapheme widths", tag: "text", priority: 2),
         BoardCard(id: "Contrast floor", tag: "theme", priority: 1),
         BoardCard(id: "SGR mouse parser", tag: "input", priority: 1),
         BoardCard(id: "Undo grouping", tag: "edit", priority: 0),
         BoardCard(id: "Kitty placements", tag: "images", priority: 1),
         BoardCard(id: "Focus sections", tag: "focus", priority: 1),
         BoardCard(id: "Spring bounce", tag: "anim", priority: 0),
         BoardCard(id: "Date pickers", tag: "input", priority: 1),
         BoardCard(id: "Colour panel", tag: "theme", priority: 0),
         BoardCard(id: "Toolbar items", tag: "modals", priority: 0),
         BoardCard(id: "Link hover", tag: "terms", priority: 0),
         BoardCard(id: "Search fields", tag: "input", priority: 1)],
    ]
    /// Each column's selected cards: several, so they can be dragged together.
    /// To do's top card to begin with, as the script ends, so the clip loops.
    @State private var selections: [Set<String>] = [["Sticky headers"], [], []]

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
                            // Several cards land in their order, each after the
                            // last, and stay selected together.
                            let before = columns
                            var at = index
                            for drop in drops {
                                at = move(drop, to: column, at: at) + 1
                                if drop.column != column { selections[drop.column].remove(drop.id) }
                            }
                            selections[column] = Set(drops.map(\.id))
                            register(before)
                        }
                        .onMove { source, destination in
                            let before = columns
                            columns[column].move(fromOffsets: source, toOffset: destination)
                            register(before)
                        }
                    }
                    // The three cards dragged together all ride the pointer,
                    // rather than one and "+2 more".
                    .dragPreviewRowLimit(5)
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

    /// A card: its priority, title and tag. The tag keeps its size and a long
    /// title gives way: with the title first in line, a row too narrow for both
    /// squeezed the tag, which lost its trailing space.
    private func cardRow(_ card: BoardCard) -> some View {
        HStack(spacing: 1) {
            Text(verbatim: "●").foregroundStyle(priorityColour(card.priority))
            Text(verbatim: card.id).lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: " \(card.tag) ")
                .foregroundStyle(.palette.background)
                .background(tagColour(card.tag))
                .fixedSize()
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
    /// Moves `drop`'s card to `index` of `column`, and answers where it went.
    @discardableResult
    private func move(_ drop: BoardDrag, to column: Int, at index: Int) -> Int {
        guard let from = columns[drop.column].firstIndex(where: { $0.id == drop.id }) else { return index }
        let card = columns[drop.column].remove(at: from)
        var target = index
        if drop.column == column, from < index { target -= 1 }
        let placed = min(max(0, target), columns[column].count)
        columns[column].insert(card, at: placed)
        return placed
    }

    private func register(_ before: [[BoardCard]]) {
        guard before != columns else { return }
        let binding = $columns
        undoManager?.registerRestoring(binding, to: before, actionName: "Move")
    }
}
