//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditClip.swift
//
//  `textedit`: a notes app's editor holding a note about TUI's own text
//  editing, each feature shown on the line that names it: a click, Option-
//  arrows, a double-click typed over, an Option-drag block, Ctrl-F, the Emacs
//  keys, Ctrl-Z undoing it all and Ctrl-Shift-Z redoing some — each chord
//  captioned as it is pressed.
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

/// A chord, captioned under the editor as it is pressed: what was pressed and
/// what it does, for a viewer who cannot see the keyboard.
private func chord(_ keys: Step, _ caption: String) -> [Step] {
    [.cue("key \(caption)"), keys]
}

/// Ctrl-Shift-Z, as a terminal speaking the kitty keyboard protocol reports
/// it (`CSI 122 ; 6 u`): in a legacy encoding it arrives as Ctrl-Z.
private let redo = Step.keys("\u{1B}[122;6u")

/// Each feature, shown on the line of the note that names it.
private func textEditScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 76, height: 15)), .wait(0.8)]
    let park: [Step] = [.point(column: Editor.rest.column, row: Editor.rest.row), .wait(0.5)]
    // "Click anywhere to put the caret there." — on "anywhere".
    script += Step.click(Editor.left + 7, Editor.top + 2) + [.wait(0.4)] + park
    // "Option-arrows move a word at a time." — from its start, ⌥→ word by word.
    script += Step.click(Editor.left, Editor.top + 3) + [.wait(0.3)] + park
    script += [.cue("key ⌥→  next word")] + Step.repeat(.optionRight, 5, interval: 0.4)
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
    script += chord(Step.control("f"), "⌃F  find") + [.wait(0.5)]
    script += Step.click(Editor.left + 6, Editor.top) + [.wait(0.2)] + park
    script += Step.type("select", interval: 0.12)
    script += [.wait(0.8), .enter, .wait(0.7), .enter, .wait(0.7), .escape, .wait(0.4)]
    // "- Emacs keys" — to the line's start and end, a word on, the rest killed
    // and yanked back.
    script += Step.click(Editor.left + 12, Editor.top + 9) + [.wait(0.3)] + park
    script += chord(Step.control("a"), "⌃A  start of line") + [.wait(0.7)]
    script += chord(Step.control("e"), "⌃E  end of line") + [.wait(0.7)]
    script += chord(Step.control("a"), "⌃A  start of line") + [.wait(0.5)]
    script += [.cue("key ⌥F  next word")] + Step.repeat(.keys("\u{1B}f"), 3, interval: 0.4)
    script += chord(Step.control("k"), "⌃K  kill to end of line") + [.wait(0.9)]
    script += chord(Step.control("y"), "⌃Y  yank it back") + [.wait(0.9)]
    // "- Ctrl-Z undoes it all, ⌃⇧Z redoes" — back to where it began, two
    // steps redone, and undone again: where the clip loops from.
    script += [.cue("key ⌃Z  undo")] + Step.repeat(Step.control("z"), 12, interval: 0.22)
    script += [.wait(0.6), .cue("key ⌃⇧Z  redo")] + Step.repeat(redo, 2, interval: 0.6)
    script += [.wait(0.6), .cue("key ⌃Z  undo")] + Step.repeat(Step.control("z"), 2, interval: 0.6)
    // The caption goes before the end, as it was at the start: the loop's seam.
    script += [.wait(0.8), .cue("clear"), .wait(0.6)]
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
        - Emacs keys: ⌃A ⌃E ⌃K ⌃Y ⌃T
        - Ctrl-Z undoes it all, ⌃⇧Z redoes
        """
    @State private var selection: Int? = 0
    /// The chord last pressed and what it does, captioned until the next.
    @State private var caption: String?

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
                    Spacer(minLength: 0)
                    if let caption {
                        Text(verbatim: " \(caption) ")
                            .bold()
                            .foregroundStyle(.palette.background)
                            .background(.palette.accent)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(.palette.foregroundTertiary)
            }
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Notes") }
        }
        .task {
            for await cue in ClipCues.stream() {
                withAnimation(.easeOut(duration: 0.15)) {
                    caption = cue.hasPrefix("key ") ? String(cue.dropFirst(4)) : nil
                }
            }
        }
    }
}
