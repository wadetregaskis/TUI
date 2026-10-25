//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditClip.swift
//
//  `textedit`: a notes app's editor in use — a line typed, a word selected
//  and replaced, a search with Ctrl-F, and the edits undone, all through the
//  editor's own keys.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

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

/// Where the new line's last word lands (1-based cells, as a mouse report
/// counts): the editor's text starts in column 25, under the three-row
/// toolbar, and the line typed is the editor's ninth.
private enum Typed {
    static let row = 12
    static let lastWord = 49...53  // "stove"
}

private func textEditScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 21.5, y: 2.6, width: 50, height: 17.5)), .wait(0.5), .tab, .wait(0.4)]
    // To the end of the list, and a new item typed.
    script += Step.repeat(.down, 6, interval: 0.12)
    script += [.end, .wait(0.3), .enter]
    script += Step.type("- Pack the tent and the stove", interval: 0.06)
    script += [.wait(0.5)]
    // The last word selected with the mouse, and typed over.
    script += Step.drag(from: (Typed.lastWord.lowerBound, Typed.row), to: (Typed.lastWord.upperBound + 1, Typed.row),
                        interval: 0.06)
    script += [.wait(0.4)]
    script += Step.type("kettle", interval: 0.08)
    script += [.wait(0.6)]
    // Find "the": the bar opens, the matches light up, Return steps through them.
    // (The bar opens with the editor still holding the keys, so a click puts
    // the query field in charge.)
    script += [Step.control("f"), .wait(0.5)]
    script += Step.click(30, 4)
    script += [.wait(0.3)]
    script += Step.type("the", interval: 0.15)
    script += [.wait(0.9), .enter, .wait(0.6), .enter, .wait(0.8), .escape, .wait(0.5)]
    // Undo it all, back to where it began.
    script += Step.repeat(Step.control("z"), 4, interval: 0.35)
    script += [.wait(0.9)]
    return script
}

struct TextEditApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Notes") {
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
