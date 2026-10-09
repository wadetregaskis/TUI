//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditorLayout.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// A ``TextEditor``'s document laid out: split into lines once for each text
/// the binding holds, rather than once per use.
///
/// The editor used to split its whole document into lines four times over: in
/// its measure, its render, every key's handling and every pointer event's.
/// Its handler keeps one of these instead, keyed by the text it was made from.
/// An untouched document costs one string comparison a frame — `String ==`
/// answers from the storage when the binding hands back the same string — and
/// an edit, which the editor writes itself, hands its lines over with the text,
/// so nothing splits them again.
final class EditorLayout {
    /// The text laid out.
    let text: String

    /// Its lines, as characters, a newline between each and the next. Never
    /// empty: an empty text is one empty line.
    let lines: [[Character]]

    /// The lines wrapped at the widths asked for this frame and the last
    /// (``wrapped(width:tabWidth:)``), each with the frame that last asked.
    var wrappings: [(rows: WrappedRows, tabWidth: TabWidth, frame: UInt)] = []

    /// The frame the wrappings are stamped with, moved on by ``endFrame()``.
    var frame: UInt = 0

    /// How many times this layout has wrapped its lines: what shows a frame
    /// served from the wrappings it kept rather than wrapping again.
    var wrapsMade = 0

    /// Splits `text` into its lines.
    init(text: String) {
        self.text = text
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map { Array($0) }
        lines = parts.isEmpty ? [[]] : parts
    }

    /// The layout of `text`, whose lines the caller already has — the editor's
    /// own edit, written as these lines joined.
    init(text: String, lines: [[Character]]) {
        self.text = text
        self.lines = lines.isEmpty ? [[]] : lines
    }
}
