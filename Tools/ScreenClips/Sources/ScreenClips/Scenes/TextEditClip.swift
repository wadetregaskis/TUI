//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditClip.swift
//
//  `textedit`: a notes app's editor holding a note about TUI's own text
//  editing, each feature shown on the line that names it: a click, Option-
//  arrows, a double-click typed over, an Option-drag block, Ctrl-F, and Ctrl-Z
//  undoing it all.
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
/// its text starts in column `left` on row `top`, one row per line. `rest` is
/// where the pointer waits between uses, over the notes list, off the text.
private enum Editor {
    static let left = 25
    static let top = 4
    static let rest = (column: 9, row: 17)
}

/// Each feature, shown on the line of the note that names it.
private func textEditScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 76, height: 15)), .wait(0.8)]
    let park: [Step] = [.point(column: Editor.rest.column, row: Editor.rest.row), .wait(0.5)]
    // "Click anywhere to put the caret there." — on "anywhere".
    script += Step.click(Editor.left + 7, Editor.top + 2) + [.wait(0.4)] + park
    // "Option-arrows move a word at a time." — from its start, ⌥→ word by word.
    script += Step.click(Editor.left, Editor.top + 3) + [.wait(0.3)] + park
    script += Step.repeat(.optionRight, 5, interval: 0.4)
    script += [.wait(0.4)]
    // "Double-click a word to select it." — "word", selected and typed over.
    script += Step.doubleClick(Editor.left + 16, Editor.top + 4) + [.wait(0.5)]
    script += Step.type("phrase", interval: 0.1)
    script += [.wait(0.3)] + park
    // "- Option-drag selects a block" — down the bullets: a block, deleted
    // from every row at once, and put back.
    script += Step.drag(from: (Editor.left, Editor.top + 7), to: (Editor.left + 2, Editor.top + 9), interval: 0.1,
                        option: true)
    script += [.wait(0.5)] + park + [.keys("\u{7F}"), .wait(0.9), Step.control("z"), .wait(0.7)]
    // "- Ctrl-F finds, Return steps on" — "select": the bar opens, the
    // matches light up, Return steps through them. (A click puts the query
    // field in charge; the bar opens with the editor holding the keys.)
    script += [Step.control("f"), .wait(0.5)]
    script += Step.click(Editor.left + 6, Editor.top) + [.wait(0.2)] + park
    script += Step.type("select", interval: 0.12)
    script += [.wait(0.8), .enter, .wait(0.7), .enter, .wait(0.7), .escape, .wait(0.4)]
    // "- Ctrl-Z undoes it all" — and it does, back to where it began.
    script += Step.repeat(Step.control("z"), 8, interval: 0.25)
    script += [.wait(1.0)]
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
        # Editing in TUI

        Click anywhere to put the caret there.
        Option-arrows move a word at a time.
        Double-click a word to select it.

        ## And
        - Option-drag selects a block
        - Ctrl-F finds, Return steps on
        - Ctrl-Z undoes it all
        """
    @State private var selection: Int? = 0

    private let notes = ["Editing in TUI", "Reading list", "Recipes", "Book club", "Ideas"]

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
