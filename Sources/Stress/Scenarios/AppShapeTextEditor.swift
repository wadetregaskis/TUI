//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppShapeTextEditor.swift
//
//  A notes app's editor over a long document: what a TextEditor costs a frame
//  when the whole document is laid out, which is what soft wrapping prices.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// One `TextEditor` over two thousand lines of prose, each a tenth longer than
/// the 120-cell screen the bench draws, so every line overflows the editor.
///
/// The `code-editor` shape is not this: it is two thousand `Text` rows in a
/// lazy stack, and no `TextEditor` lays out a document the size of a real
/// one anywhere else in the harness (the notes session's are a few lines).
/// The editor holds the focus, so its caret is drawn.
///
/// `typing` changes one line every tick — the edit frame, where the bound
/// text is new and the editor lays it out again — against the settled
/// document's idle frame.
struct TextEditorApp: View {
    let lines: Int
    var typing = false
    /// Whether the editor wraps its lines, as it does by default, or scrolls
    /// sideways (`textEditorWrapsLines(false)`): the pair prices the wrap.
    var wraps = true

    /// The document, written once: synthesising it in the body would be
    /// measured as the editor's cost.
    let document: String

    init(lines: Int, seed: UInt64, typing: Bool = false, wraps: Bool = true) {
        self.lines = lines
        self.typing = typing
        self.wraps = wraps
        self.document = Self.document(lines: lines, seed: seed)
    }

    /// The width a line is written to: a tenth past the bench's 120 columns.
    static let lineWidth = 132

    @Environment(StressClock.self) private var clock

    var body: some View {
        // An edit lands in the middle of the document, as typing in a long
        // note does: every line is laid out either side of it.
        let text = typing ? Self.typed(document, tick: clock.tick) : document
        return VStack(alignment: .leading, spacing: 0) {
            Text(
                Lf(
                    "stress.scenario.app-shapes.heading",
                    typing ? "text-editor-typing" : wraps ? "text-editor" : "text-editor-unwrapped", lines)
            ).bold()
            TextEditor(text: .constant(text))
                .textEditorWrapsLines(wraps)
        }
    }

    /// The document: `lines` lines of seeded prose, each `lineWidth` long.
    static func document(lines: Int, seed: UInt64) -> String {
        (0..<lines).map { index in
            var line = ""
            var word = 0
            while line.count < lineWidth {
                line += (line.isEmpty ? "" : " ") + Synth.sentence(mix(seed, index &* 31 &+ word), words: 6)
                word += 1
            }
            return String(line.prefix(lineWidth))
        }.joined(separator: "\n")
    }

    /// `document` with its middle line's first word replaced by one that
    /// moves with the tick.
    private static func typed(_ document: String, tick: Int) -> String {
        var lines = document.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return document }
        let middle = lines.count / 2
        lines[middle] = Substring("typing \(tick % 1_000) ") + lines[middle]
        return lines.joined(separator: "\n")
    }
}
