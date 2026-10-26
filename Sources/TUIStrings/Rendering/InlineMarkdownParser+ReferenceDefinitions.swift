//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser+ReferenceDefinitions.swift
//
//  Link reference definitions — `[label]: destination "title"` — and the
//  reference links that use them, `[text][label]`, `[label][]` and `[label]`,
//  as Foundation's parser reads them in the inline-only mode SwiftUI draws a
//  key with (owner ruling B86, 2026-10-26).
//
//  Created by Wade Tregaskis
//  License: MIT

/// What Foundation does, measured on macOS 15.8 (an `AttributedString(markdown:)`
/// probe with `.inlineOnlyPreservingWhitespace`, 43 cases):
///
/// - Definitions are read only at the very start of the text, at its first
///   column, one after another; one anywhere else, or after a blank line or a
///   leading space, is text. Each takes the one line ending after it.
/// - A definition is CommonMark's: a label of up to 999 characters, not blank;
///   a colon; spaces and at most one line ending; a destination, `<…>` or bare;
///   and optionally, after whitespace that may hold one line ending, a title,
///   `"…"`, `'…'` or `(…)`; then nothing but spaces to the line's end. A title
///   or anything else left on the line makes the line text, where a title on
///   the next line that fails leaves the definition ending at its destination.
/// - A destination that runs into the end of the text makes no definition
///   (`[a]: https://x.com` alone is text, `[a]: https://x.com ` with a space is
///   a definition and draws nothing), as the inline link's scan already has it.
/// - Labels match case-insensitively — fully folded, `ß` matching `SS` — with
///   their ends trimmed and every run of whitespace one space. The first of
///   two definitions of a label is the one used.
/// - `[text][label]` is a link to `label`'s destination, `[label][]` (or a
///   second label of nothing but whitespace) and `[label]` to their own
///   text's; a `[text][label]` naming no definition is
///   text, not a shortcut. An inline `[text](destination)` is read first. An
///   image reference draws its alt text, as an image does.
extension InlineMarkdownParser {
    /// Reads the definitions the source opens with into ``definitions``, and
    /// starts the parse after them.
    mutating func parseReferenceDefinitions() {
        guard source.first?.is("[") == true else { return }
        var found: [String: [Atom]] = [:]
        var index = 0
        while let (label, destination, end) = scanDefinition(at: index) {
            if found[label] == nil { found[label] = destination }
            index = end
        }
        guard index > 0 else { return }
        definitions = found
        position = index
    }

    /// After a link's or image's `]` at ``position``, the destination a
    /// reference gives it, or `nil`: `[label]` after it, an empty `[]`, or
    /// neither — a `[` that starts no label counts as nothing — naming `text`
    /// (the bracket's own text) for the last two. A `[label]` naming no
    /// definition makes no link. Leaves ``position`` past a following label
    /// on success.
    mutating func parseReferenceTail(text: Range<Int>) -> [Atom]? {
        guard !definitions.isEmpty else { return nil }
        if atom(at: position)?.is("[") == true {
            guard let close = labelEnd(from: position + 1) else { return definition(labelled: text) }
            // A blank second label — `[]`, or nothing but whitespace, as
            // Foundation reads it — names the bracket's own text.
            let label = normalizedLabel((position + 1)..<close) == nil ? text : (position + 1)..<close
            guard let destination = definition(labelled: label) else { return nil }
            position = close + 1
            return destination
        }
        return definition(labelled: text)
    }

    // MARK: - Definitions

    /// The definition starting at `start`: its normalized label, its
    /// destination, and where the text after it starts.
    private func scanDefinition(at start: Int) -> (String, [Atom], Int)? {
        guard atom(at: start)?.is("[") == true, let close = labelEnd(from: start + 1),
            atom(at: close + 1)?.is(":") == true, let label = normalizedLabel(start + 1..<close)
        else { return nil }
        let destinationStart = skipLinkWhitespace(from: close + 2)
        guard let (destination, afterDestination) = scanLinkDestination(from: destinationStart),
            !destination.isEmpty || atom(at: destinationStart)?.is("<") == true
        else { return nil }
        let titleStart = skipLinkWhitespace(from: afterDestination)
        if titleStart > afterDestination, let afterTitle = scanLinkTitle(from: titleStart),
            let end = lineEnd(from: afterTitle)
        {
            return (label, Self.decodingReferences(in: destination), end)
        }
        guard let end = lineEnd(from: afterDestination) else { return nil }
        return (label, Self.decodingReferences(in: destination), end)
    }

    /// Past the spaces and tabs at `start` and the line ending after them, or
    /// the end of the source; `nil` where anything else is on the line.
    private func lineEnd(from start: Int) -> Int? {
        var index = start
        while let atom = atom(at: index), atom.is(" ") || atom.is("\t") { index += 1 }
        guard let atom = atom(at: index) else { return index }
        return atom.is("\n") ? index + 1 : nil
    }

    // MARK: - Labels

    /// The index of the `]` that ends the label starting at `start`, or `nil`:
    /// up to 999 characters, a backslash escaping the next, and no unescaped
    /// `[` among them.
    private func labelEnd(from start: Int) -> Int? {
        var index = start
        while let atom = atom(at: index), index - start <= 999 {
            if atom.is("\\"), self.atom(at: index + 1) != nil {
                index += 2
                continue
            }
            if atom.is("]") { return index }
            if atom.is("[") { return nil }
            index += 1
        }
        return nil
    }

    /// The definition labelled by the source's `range`, if there is one.
    private func definition(labelled range: Range<Int>) -> [Atom]? {
        normalizedLabel(range).flatMap { definitions[$0] }
    }

    /// The source's `range` as a label is matched: case folded, its ends
    /// trimmed and each run of whitespace one space; `nil` for a blank label,
    /// one longer than 999 characters, or one holding an interpolated value,
    /// which no definition can name.
    private func normalizedLabel(_ range: Range<Int>) -> String? {
        guard range.count <= 999 else { return nil }
        var label = ""
        var pendingSpace = false
        for index in range {
            guard let scalar = source[index].scalar else { return nil }
            if scalar.properties.isWhitespace {
                pendingSpace = !label.isEmpty
                continue
            }
            if pendingSpace { label.unicodeScalars.append(" ") }
            pendingSpace = false
            label.unicodeScalars.append(scalar)
        }
        guard !label.isEmpty else { return nil }
        // Full case folding, as cmark's: upper then lower takes `ß` to `ss`,
        // which lower case alone leaves as it is.
        return label.uppercased().lowercased()
    }
}
