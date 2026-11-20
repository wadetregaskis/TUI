//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Writing.swift
//
//  How a TextEditor's edit is written: its replacements made over the
//  layout's lines, the edit spliced into the text, and the layout of the text
//  the binding takes made from the one before, in its own storage.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextEditorHandler {
    /// Makes `replacements`, in order, each on the lines the one before it
    /// left, and writes the lines they leave. Every edit the editor makes to
    /// its text is made here, as the ranges it replaces
    /// (``TextEditorReplacement``), except the two that replace the text
    /// whole through ``write(_:)``: an undo or a redo, and the find bar's
    /// Replace All.
    ///
    /// The replacements are made in an ``EditedLines`` over the layout's
    /// lines, not in a copy of them: the lines they reach are all an edit
    /// copies (``edit(making:beforeWriting:)``).
    ///
    /// - Parameter prepare: Given the lines the replacements leave, before
    ///   they are written: for an edit whose caret is placed by them.
    /// - Returns: The lines written.
    @discardableResult
    func writeReplacing(
        _ replacements: [TextEditorReplacement], beforeWriting prepare: (EditedLines) -> Void = { _ in }
    ) -> EditedLines {
        // The same edit in an attributed editor's value, in place (B-ATTRED-3).
        attributedSource?.stage(replacements, in: layout())
        switch edit(making: replacements, beforeWriting: prepare) {
        case .spliced(let edit): return writeSpliced(edit)
        case .joined(let lines):
            writeJoined(lines, ending: layout().lineEnding)
            return EditedLines(lines)
        }
    }

    /// An edit as it is written: spliced into the text's bytes
    /// (``EditorLayout/replacing(_:)``), or, in a text with more than one kind
    /// of line break, its lines joined afresh.
    private enum LinesEdit {
        case spliced(EditorLayout.Edit)
        case joined([[Character]])
    }

    /// Makes `replacements` in an ``EditedLines`` over the layout's lines,
    /// hands them to `prepare`, and makes the edit of the text they are.
    ///
    /// A function of its own so the lines, which share the layout's array,
    /// are let go when it returns: held while the edit is made in that array
    /// (``writeSpliced(_:)``), they would make it copy the array.
    private func edit(
        making replacements: [TextEditorReplacement], beforeWriting prepare: (EditedLines) -> Void
    ) -> LinesEdit {
        var lines = EditedLines(readLines())
        for replacement in replacements { lines.apply(replacement) }
        prepare(lines)
        return layout().replacing(lines).map(LinesEdit.spliced) ?? .joined(lines.array)
    }

    /// Writes `edit`'s text to the bound text, and makes the layout of the
    /// text written from the one before, its wrappings with it
    /// (``EditorLayout/laidOut(_:reusingStorage:)``), so a key costs the lines
    /// it changed.
    ///
    /// The layout before is left whole until the binding takes the text, so
    /// one it refuses leaves the handler that layout; once it is taken, the
    /// edit is made in that layout's own arrays where nothing else holds them.
    private func writeSpliced(_ edit: EditorLayout.Edit) -> EditedLines {
        var before = layout()
        write(edit.text)
        // Unless the binding kept something else: that is laid out afresh by
        // the next read.
        guard !edit.isUnchanged, text.wrappedValue == edit.text else {
            return EditedLines(base: before.lines, replacing: edit.replaced, with: edit.lines)
        }
        // The layout before is the edit's alone once the handler lets go,
        // unless a caller still holds it: that one's arrays are copied, and it
        // keeps its lines.
        cachedLayout = nil
        // Asked first, not as the call's argument: as the argument, Xcode 26's
        // 6.2.4 aborts the -O build ("Load borrow invalidated by a local
        // write"; Tools/CompilerBugs, `UniquenessCheckAsArgument`), and an
        // unoptimised build's check counts the reference the call holds, so
        // it never says unshared.
        let unshared = isKnownUniquelyReferenced(&before)
        // Made while `before` has its lines: laid out in place, it has none.
        let highlighted = highlightEdit(edit, from: before)
        let after = before.laidOut(edit, reusingStorage: unshared)
        cachedLayout = after
        if drawsLineStyles { lineStyleCache.replaceLines(edit.replaced, withCount: edit.replacement.count) }
        if let highlighted { sendHighlightEdit(highlighted, leaving: after) }
        // The lines' rows a line moved with them, those of the lines it
        // put in to be read.
        keptLineGaps = nil
        return EditedLines(after.lines)
    }

    /// Writes `lines` joined by `ending`: an edit of a text with more than
    /// one kind of line break, which writes each as `ending`.
    private func writeJoined(_ lines: [[Character]], ending: String) {
        let joined = lines.map { String($0) }.joined(separator: ending)
        write(joined)
        // The lines just written are the layout of the text just written —
        // unless the binding kept something else (one that transforms what it
        // is given), which the next read lays out afresh.
        // Each line as its string's characters, as an edit spliced in keeps
        // them (``EditorLayout/segmented(_:)``).
        if text.wrappedValue == joined {
            cachedLayout = EditorLayout(text: joined, lines: lines.map(EditorLayout.segmented), lineEnding: ending)
            if drawsLineStyles { lineStyleCache.removeAll() }
            keptLineGaps = nil
        }
    }
}
