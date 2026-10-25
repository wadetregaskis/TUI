//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragDropClip.swift
//
//  `dragdrop`: a task board whose cards are dragged with the mouse from one
//  column to the next — the camera following the card — and then reordered
//  in their new column from the keyboard.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let dragDropClip = Clip(
    id: "dragdrop",
    title: "Drag & drop",
    columns: 112,
    rows: 30,
    script: dragDropScript(),
    run: { await DragDropApp.main() }
)

/// Where the board's cards sit (1-based cells, as a mouse report counts):
/// three columns of 34, the first card on row 7.
private enum Board {
    static let todo = 14
    static let doing = 50
    static let firstCard = 7
}

private func dragDropScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 1.5, y: 4.2, width: 46, height: 16)), .wait(1.0)]
    // The second card of To do, across into Doing, between its two cards; the
    // camera drifts right with it.
    script += [.camera(Shot(x: 19, y: 4.2, width: 46, height: 16, over: 1.2))]
    script += Step.drag(from: (Board.todo, Board.firstCard + 1), to: (Board.doing, Board.firstCard + 1), interval: 0.035)
    script += [.wait(1.0)]
    // Another, the top one, to the end of Doing.
    script += Step.drag(from: (Board.todo, Board.firstCard), to: (Board.doing, Board.firstCard + 3), interval: 0.03)
    script += [.wait(0.8)]
    // Keyboard: in Doing, the selected card up one place with ⌥↑.
    script += Step.click(Board.doing, Board.firstCard + 3)
    script += [.wait(0.5), .optionUp, .wait(0.6), .optionUp, .wait(0.9)]
    // Undo all three, and back where it began. The camera stays where it is:
    // the loop's own seam is its cut back to the start (a move costs more
    // bytes than anything else in a clip).
    script += [Step.control("z"), .wait(0.45), Step.control("z"), .wait(0.45), Step.control("z"), .wait(0.45),
               Step.control("z"), .wait(1.2)]
    return script
}

struct DragDropApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Board") {
            TaskBoard()
                .palette(SystemPalette(.amber))
        }
    }
}

/// A card on the board.
struct BoardCard: Identifiable, Hashable {
    let id: String
    let tag: String
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
        [BoardCard(id: "Sticky table headers", tag: "tables"), BoardCard(id: "Kitty image cache", tag: "images"),
         BoardCard(id: "Warp quirks survey", tag: "terminals"), BoardCard(id: "Braille dithering", tag: "images"),
         BoardCard(id: "Menu type-select", tag: "menus")],
        [BoardCard(id: "Spring curves", tag: "animation"), BoardCard(id: "Sheet detents", tag: "presentation")],
        [BoardCard(id: "Grapheme widths", tag: "text"), BoardCard(id: "Palette contrast floor", tag: "theming"),
         BoardCard(id: "SGR mouse parser", tag: "input")],
    ]
    @State private var selections: [String?] = [nil, nil, nil]

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
                            HStack(spacing: 1) {
                                Text(verbatim: card.id)
                                Spacer()
                                Text(verbatim: card.tag).foregroundStyle(.palette.foregroundTertiary)
                            }
                            .draggable(BoardDrag(column: column, id: card.id))
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
                .frame(width: 34)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Board · TUIkit 1.0") }
        }
    }

    private func selectionBinding(_ column: Int) -> Binding<String?> {
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
        selections[column] = card.id
    }

    private func register(_ before: [[BoardCard]]) {
        guard before != columns else { return }
        let binding = $columns
        undoManager?.registerRestoring(binding, to: before, actionName: "Move")
    }
}
