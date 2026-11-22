//  🖥️ TUI — A Terminal UI framework for Swift
//  EditedLines.swift
//
//  An edit's lines as the lines before it with one span replaced: what a
//  TextEditor's edit is made as, so no key copies the document's lines.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The lines an edit leaves: the lines before it, ``base``, with one span of
/// them (``replaced``) given way to ``replacement``.
///
/// What ``TextEditorHandler/writeReplacing(_:beforeWriting:)`` makes its
/// replacements in, where it used to make them in a copy of the document's
/// lines: an array of forty thousand lines copied on the first write, then
/// released with the layout before (14.1% and 12.7% of the `bigtext`
/// session's time, 2026-11-19). The base is the layout's own array, shared
/// and never written; the replacement holds the lines the edit reached.
struct EditedLines {
    /// The lines before the edit.
    let base: [TextCharacters]
    /// The lines of ``base`` the edit replaced.
    private(set) var replaced: Range<Int>
    /// What took their place: never all of the text's lines unless the edit
    /// replaced them all.
    private(set) var replacement: [TextCharacters]

    /// `lines`, unedited.
    init(_ lines: [TextCharacters]) {
        base = lines
        replaced = 0..<0
        replacement = []
    }

    /// `base` with `replaced` given way to `replacement`.
    init(base: [TextCharacters], replacing replaced: Range<Int>, with replacement: [TextCharacters]) {
        self.base = base
        self.replaced = replaced
        self.replacement = replacement
    }

    /// How many lines there are.
    var count: Int { base.count - replaced.count + replacement.count }

    /// Whether the edit has reached no line.
    private var isUnedited: Bool { replaced.isEmpty && replacement.isEmpty }

    /// Line `index`, from the replacement where the edit reached it and from
    /// the base elsewhere.
    subscript(index: Int) -> TextCharacters {
        if index < replaced.lowerBound { return base[index] }
        let inside = index - replaced.lowerBound
        if inside < replacement.count { return replacement[inside] }
        return base[index - replacement.count + replaced.count]
    }

    /// Every line, as one array: what the lines were as an array, for an edit
    /// that is joined whole.
    var array: [TextCharacters] {
        if isUnedited { return base }
        var lines: [TextCharacters] = []
        lines.reserveCapacity(count)
        lines += base[..<replaced.lowerBound]
        lines += replacement
        lines += base[replaced.upperBound...]
        return lines
    }

    /// Makes `edit`, on the lines the edits before it left, as
    /// ``TextEditorReplacement/apply(to:)`` makes it in an array: the span
    /// replaced grown to take in the lines it reaches.
    mutating func apply(_ edit: TextEditorReplacement) {
        let reached = edit.start.line..<(edit.end.line + 1)
        // The span, in the lines as they are now, that the replacement holds.
        let held = isUnedited ? reached.lowerBound..<reached.lowerBound
            : replaced.lowerBound..<(replaced.lowerBound + replacement.count)
        let lower = min(held.lowerBound, reached.lowerBound)
        let upper = max(held.upperBound, reached.upperBound)
        // The lines before `held` are the base's at the same index, those after
        // it the base's moved by the difference the replacement makes.
        let baseLower = lower
        let baseUpper = isUnedited ? upper : upper - replacement.count + replaced.count
        var window: [TextCharacters] = []
        window.reserveCapacity(upper - lower)
        for index in lower..<upper { window.append(self[index]) }
        TextEditorReplacement(
            from: TextEditorPosition(line: edit.start.line - lower, column: edit.start.column),
            to: TextEditorPosition(line: edit.end.line - lower, column: edit.end.column),
            with: edit.replacement
        ).apply(to: &window)
        replaced = baseLower..<baseUpper
        replacement = window
    }

    /// Makes `edits`, last in the text first, on these lines unedited, in one
    /// pass: the lines they leave as ``apply(_:)`` would leave them one at a
    /// time, which copies the span the ones before reached at each, so a
    /// Replace All of thousands of matches cost their count times the lines
    /// between the first and the last.
    ///
    /// The lines between two edits that neither reaches keep their storage,
    /// as ``TextEditorReplacement/apply(to:)`` keeps it.
    ///
    /// - Precondition: ``TextEditorReplacement/areDescending(_:)``, and no
    ///   edit made yet.
    mutating func apply(descending edits: [TextEditorReplacement]) {
        guard let highest = edits.first, let lowest = edits.last else { return }
        precondition(isUnedited, "the edits are made on the lines unedited")
        var window: [TextCharacters] = []
        var current: TextCharacters = []
        // Where in the base the text not yet taken starts.
        var (line, column) = (lowest.start.line, lowest.start.column)
        current += base[line][..<column]
        for edit in edits.reversed() {
            while line < edit.start.line {
                if column == 0, current.isEmpty {
                    window.append(base[line])
                } else {
                    current += base[line][column...]
                    window.append(current)
                    current = []
                }
                (line, column) = (line + 1, 0)
            }
            current += base[line][column..<edit.start.column]
            current += edit.replacement[0]
            for next in edit.replacement.dropFirst() {
                window.append(current)
                current = next
            }
            (line, column) = (edit.end.line, edit.end.column)
        }
        current += base[line][column...]
        window.append(current)
        replaced = lowest.start.line..<(highest.end.line + 1)
        replacement = window
    }
}
