//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditClip.swift
//
//  `textedit`: a notes app's editor in use — a line typed, a word selected
//  and replaced, a search with Ctrl-F, and the edits undone, all through the
//  editor's own keys.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let textEditClip = Clip(
    id: "textedit",
    title: "Text editing",
    columns: 112,
    rows: 30,
    terminal: "warp",
    script: textEditScript(),
    run: { await TextEditApp.main() }
)

/// Where things are in the editor (1-based cells, as a mouse report counts):
/// its text starts in column `left` on row `top`, one row per line.
private enum Editor {
    static let left = 25
    static let top = 4
}

private func textEditScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 76, height: 18)), .wait(0.6)]
    // A click into "Four days, 55 km, huts booked.", then a word at a time
    // with ⌥→ to the 55, double-clicked and typed over.
    script += Step.click(Editor.left, Editor.top + 2)
    script += [.wait(0.5)]
    script += Step.repeat(.optionRight, 3, interval: 0.4)
    script += [.wait(0.3)]
    script += Step.doubleClick(Editor.left + 11, Editor.top + 2)
    script += [.wait(0.5)]
    script += Step.type("62", interval: 0.12)
    script += [.wait(0.5)]
    // To the end of the list, and a new item typed.
    script += Step.click(Editor.left + 32, Editor.top + 7)
    script += [.wait(0.3), .end, .wait(0.2), .enter]
    script += Step.type("- Pack the tent and the stove", interval: 0.05)
    script += [.wait(0.4)]
    // "stove" double-clicked and typed over.
    script += Step.doubleClick(Editor.left + 26, Editor.top + 8)
    script += [.wait(0.4)]
    script += Step.type("kettle", interval: 0.08)
    script += [.wait(0.6)]
    // An Option-drag down the bullets' column: a block, deleted from every row
    // at once — and put back.
    script += Step.drag(from: (Editor.left, Editor.top + 5), to: (Editor.left + 2, Editor.top + 8), interval: 0.08,
                        option: true)
    script += [.wait(0.6), .keys("\u{7F}"), .wait(0.9), Step.control("z"), .wait(0.7)]
    // Find "the": the bar opens, the matches light up, Return steps through them.
    // (The bar opens with the editor still holding the keys, so a click puts
    // the query field in charge.)
    script += [Step.control("f"), .wait(0.5)]
    script += Step.click(Editor.left + 6, Editor.top)
    script += [.wait(0.3)]
    script += Step.type("the", interval: 0.15)
    script += [.wait(0.8), .enter, .wait(0.6), .enter, .wait(0.7), .escape, .wait(0.4)]
    // Undo it all, back to where it began.
    script += Step.repeat(Step.control("z"), 5, interval: 0.3)
    script += [.wait(0.9)]
    return script
}

struct TextEditApp: App {
    var body: some Scene {
        WindowGroup("TUI · Notes") {
            NotesEditor()
                .palette(AppleTerminalPalette(.manPage))
        }
    }
}

/// A notes app: the notes down the side, the open one in an editor.
struct NotesEditor: View {
    @State private var text = """
        # Hiking trip, Laugavegur

        Four days, 55 km, huts booked.

        ## To pack
        - Boots, gaiters and the rain shell
        - Map of the route and a compass
        - Food for the first two days
        """
    @State private var selection: Int? = 0

    private let notes = ["Hiking trip", "Reading list", "Recipes", "Book club", "Ideas"]

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            List(notes.indices, id: \.self, selection: $selection) { index in
                Text(verbatim: notes[index])
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $text)
                HStack(spacing: 2) {
                    Text(verbatim: "\(text.split(whereSeparator: \.isWhitespace).count) words")
                    Text(verbatim: "Markdown")
                }
                .foregroundStyle(.palette.foregroundTertiary)
            }
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Notes") }
        }
    }
}
