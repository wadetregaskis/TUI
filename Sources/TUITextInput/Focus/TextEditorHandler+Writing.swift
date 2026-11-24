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
    /// (``TextEditorReplacement``), except an undo or a redo, which is a byte
    /// edit of the text spliced in the same way (``writeStep(_:leaving:)``),
    /// or written whole through ``write(_:)`` where it cannot be.
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

    /// Writes `result`, an undo's or a redo's text of a `String`, as the edit
    /// `step` makes of the text the binding holds: its lines spliced into the
    /// layout as a key's are (``EditorLayout/lines(after:)``,
    /// ``writeSpliced(_:)``), so the lines it reached are laid out and
    /// wrapped again and the rest kept, and the highlighting, the marks and
    /// the find bar's matches are carried through it as through a key.
    ///
    /// - Returns: Whether it wrote: not without a layout kept of the text the
    ///   binding holds (one would cost the document laid out, which writing
    ///   the text whole leaves to the next frame, if there is one), nor where
    ///   the step's lines cannot be spliced, or the splice is not `result`
    ///   byte for byte. The caller writes those whole.
    func writeStep(_ step: TextEdit, leaving result: String) -> Bool {
        guard let edit = edit(of: step, leaving: result) else { return false }
        _ = writeSpliced(edit)
        return true
    }

    /// The edit of the kept layout's lines that `step` makes, where it leaves
    /// `result`. A function of its own for the reason
    /// ``edit(making:beforeWriting:)`` is one: the lines, which share the
    /// layout's array, are let go when it returns.
    private func edit(of step: TextEdit, leaving result: String) -> EditorLayout.Edit? {
        guard let layout = cachedLayout, TextEdit.sameBytes(layout.text, text.wrappedValue),
            let lines = layout.lines(after: step), let edit = layout.replacing(lines),
            // A memcmp of the text, against laying it out: the splice must be
            // the step's text exactly, as writing that text whole made it.
            TextEdit.sameBytes(edit.text, result)
        else { return nil }
        return edit
    }

    /// An edit as it is written: spliced into the text's bytes
    /// (``EditorLayout/replacing(_:)``), or, in a text with more than one kind
    /// of line break, its lines joined afresh.
    private enum LinesEdit {
        case spliced(EditorLayout.Edit)
        case joined([TextCharacters])
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
        if TextEditorReplacement.areDescending(replacements) {
            // Thousands, from Replace All: made in one pass, where one at a
            // time each copied the span the ones before had reached.
            lines.apply(descending: replacements)
        } else {
            for replacement in replacements { lines.apply(replacement) }
        }
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
        let marked = markEdit(edit, from: before)
        // The find bar's matches, where they are of the text before.
        let found = findCache?.carries(from: before) == true ? marked?.edit ?? EditorMarkEdit(edit, from: before) : nil
        let previous = (text: before.text, ending: before.lineEnding)
        let after = before.laidOut(edit, reusingStorage: unshared)
        cachedLayout = after
        carryDisplayLayout(through: edit, from: previous)
        if drawsLineStyles { lineStyleCache.replaceLines(edit.replaced, withCount: edit.replacement.count) }
        if let highlighted { sendHighlightEdit(highlighted, leaving: after) }
        if let marked { marks.carry(through: marked.edit, of: marked.text, from: before, to: after) }
        if let found, let findCache {
            findCache.carry(found, to: after)
            marks.note(find: findCache.current, in: after)
        }
        // The lines' rows a line moved with them, those of the lines it
        // put in to be read.
        keptLineGaps = nil
        return EditedLines(after.lines)
    }

    /// Makes a hidden editor's drawn layout (``displayLayout()``) of the text
    /// `edit` leaves from the one of the text before it, `previous`, as the
    /// text's own is made: the lines the edit replaced hidden and spliced in,
    /// and wrapped again, the rest kept. Until TEXTIN-18 every key laid the
    /// whole hidden text out afresh, and wrapped all of it.
    ///
    /// Only where the hidden layout joins its lines with the ending the
    /// text's did (`previous.ending`), so its text is the edited text hidden,
    /// break for break: a one-line text's is LF, laid out afresh, where the
    /// text's own layout can keep a CRLF it no longer has.
    private func carryDisplayLayout(through edit: EditorLayout.Edit, from previous: (text: String, ending: String)) {
        guard let glyph = hidingGlyph, var shown = takeDisplayLayout(of: previous.text, hiddenBy: glyph),
            shown.lineEnding == previous.ending, let hidden = Self.hiddenEdit(edit, of: shown, glyph: glyph)
        else { return }
        // Asked first, not as the call's argument, as ``writeSpliced(_:)``
        // asks: Xcode 26's 6.2.4 aborts the -O build otherwise.
        let unshared = isKnownUniquelyReferenced(&shown)
        cachedDisplayLayout = (edit.text, glyph, shown.laidOut(hidden, reusingStorage: unshared))
    }

    /// The hidden layout kept, taken from the handler, where it is of
    /// `text` hidden by `glyph`; else `nil`, and nothing kept.
    private func takeDisplayLayout(of text: String, hiddenBy glyph: Character) -> EditorLayout? {
        guard let kept = cachedDisplayLayout else { return nil }
        cachedDisplayLayout = nil
        return kept.glyph == glyph && TextEdit.sameBytes(kept.text, text) ? kept.layout : nil
    }

    /// The edit of `shown`, a hidden layout, that `edit` of the text makes:
    /// the same lines replaced, by the same lines hidden. A function of its
    /// own so the lines, which share `shown`'s array, are let go when it
    /// returns.
    private static func hiddenEdit(
        _ edit: EditorLayout.Edit, of shown: EditorLayout, glyph: Character
    ) -> EditorLayout.Edit? {
        let lines = edit.lines.map { TextCharacters(hiding($0.string, with: glyph)) }
        return shown.replacing(EditedLines(base: shown.lines, replacing: edit.replaced, with: lines))
    }

    /// Writes `lines` joined by `ending`: an edit of a text with more than
    /// one kind of line break, which writes each as `ending`.
    private func writeJoined(_ lines: [TextCharacters], ending: String) {
        let joined = lines.map(\.string).joined(separator: ending)
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
