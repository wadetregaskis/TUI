//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayout+ByteEdit.swift
//
//  A byte edit of a TextEditor's text — an undo's or a redo's — as the lines
//  it leaves, so it is spliced into the layout as a key's edit is rather than
//  the text laid out again whole (H-87, TEXTIN-8).
//
//  Created by Wade Tregaskis
//  License: MIT

extension EditorLayout {
    /// The lines `edit`, a byte edit of this layout's text, leaves: the lines
    /// its bytes reach, from the start of the first to the break after the
    /// last, made again from their bytes with the edit's spliced in, and every
    /// other line this layout's own. What an undo or a redo hands the layout
    /// (``TextUndoHistory``'s steps are byte edits, ``TextEdit``), to be
    /// spliced in as a key's edit is (``replacing(_:)``): so it costs the
    /// lines it reached, where writing its text whole cost the document laid
    /// out and wrapped again.
    ///
    /// The lines are found by the byte span alone, so an edit that splits a
    /// character or a CRLF in two is still placed: whatever its bytes make of
    /// the lines it reaches is what they are split into.
    ///
    /// - Returns: `nil` where the text mixes kinds of line break, or where the
    ///   lines the edit reached break by any but ``lineEnding`` once it is
    ///   made — it put in or took out a break of another kind, or half a
    ///   CRLF: there joining the lines would not give back the edit's bytes,
    ///   and the caller writes the text whole. `nil` too for an edit that
    ///   reaches past the text, which is not one of this text's, and for one
    ///   that leaves a single line in a text whose ending is not LF, which a
    ///   layout made afresh gives LF.
    func lines(after edit: TextEdit) -> EditedLines? {
        guard hasOneLineEnding else { return nil }
        var source = text
        // Bridged text read as UTF-8 once, so the offsets below are bytes.
        source.makeContiguousUTF8()
        let utf8 = source.utf8
        let end = edit.offset + edit.removed.count
        guard end <= utf8.count else { return nil }
        let first = line(containingUTF8Offset: edit.offset)
        let last = line(containingUTF8Offset: end)
        // The span of the lines reached, with the break after the last where
        // a line follows it: so an edit at a line's very end, or to its break,
        // is inside it.
        let followed = last + 1 < lineStarts.count
        let lower = lineStarts[first]
        let upper = followed ? lineStarts[last + 1] : utf8.count
        var bytes: [UInt8] = []
        bytes.reserveCapacity(upper - lower - edit.removed.count + edit.inserted.count)
        bytes += utf8[utf8.index(utf8.startIndex, offsetBy: lower)..<utf8.index(utf8.startIndex, offsetBy: edit.offset)]
        bytes += edit.inserted
        bytes += utf8[utf8.index(utf8.startIndex, offsetBy: end)..<utf8.index(utf8.startIndex, offsetBy: upper)]
        // Bytes, not `Data`: lines' UTF-8 and an edit's, which the text was.
        // swiftlint:disable:next optional_data_string_conversion
        let spliced = String(decoding: bytes, as: UTF8.self)
        let breaks = Self.lineBreaks(in: spliced)
        // One line, or lines broken as the text's are.
        guard breaks.starts.count == 1 || (breaks.isUniform && breaks.ending == lineEnding) else { return nil }
        // A text of one line is laid out afresh with LF as its ending, whatever
        // breaks it had, and the next Return puts in an LF: so the step that
        // leaves one is written whole, as it was until H-87, rather than keep
        // this layout's CRLF or CR. One line is cheap to lay out.
        if lineEnding != "\n", first == 0, last == lineStarts.count - 1, breaks.starts.count == 1 { return nil }
        var lines = Self.lines(of: spliced, startingAt: breaks.starts)
        // The break after the last line reached ends the span: what follows
        // it is the next line's, kept.
        if followed { lines.removeLast() }
        return EditedLines(base: self.lines, replacing: first..<(last + 1), with: lines)
    }
}
