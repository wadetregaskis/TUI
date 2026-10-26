//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser+HTML.swift
//
//  CommonMark's raw inline HTML. SwiftUI draws it as the text it is, so all
//  recognising it does is keep what is inside a tag from being read as Markdown
//  — `<a href="x_y_z">` is not emphasis.
//
//  Created by Wade Tregaskis
//  License: MIT

extension InlineMarkdownParser {
    /// The index past the raw HTML at ``position`` (a `<`), or `nil`.
    ///
    /// CommonMark 0.29's forms, as cmark scans them: an open tag with its
    /// attributes, a closing tag, a comment, a processing instruction, a
    /// declaration and a CDATA section.
    func scanRawHTML() -> Int? {
        let start = position + 1
        guard let first = atom(at: start)?.scalar else { return nil }
        switch first {
        case "/": return scanClosingTag(from: start + 1)
        case "?": return scanUntil("?>", from: start + 1)
        case "!":
            if Self.startsWith("--", in: source, at: start + 1) { return scanComment(from: start + 3) }
            if Self.startsWith("[CDATA[", in: source, at: start + 1) { return scanUntil("]]>", from: start + 8) }
            return scanDeclaration(from: start + 1)
        default: return scanOpenTag(from: start)
        }
    }

    private func scalar(at index: Int) -> Unicode.Scalar? {
        atom(at: index)?.scalar
    }

    private func isSpace(_ index: Int) -> Bool {
        guard let scalar = scalar(at: index) else { return false }
        return scalar == " " || (0x09...0x0D).contains(scalar.value)
    }

    private func skipSpaces(from start: Int) -> Int {
        var index = start
        while isSpace(index) { index += 1 }
        return index
    }

    /// Past a tag name — an ASCII letter, then letters, digits and hyphens —
    /// or `nil`.
    private func scanTagName(from start: Int) -> Int? {
        guard let first = scalar(at: start), Self.isASCIILetter(first) else { return nil }
        var index = start + 1
        while let scalar = scalar(at: index), Self.isASCIIAlphanumeric(scalar) || scalar == "-" { index += 1 }
        return index
    }

    private func scanOpenTag(from start: Int) -> Int? {
        guard var index = scanTagName(from: start) else { return nil }
        while true {
            let afterSpace = skipSpaces(from: index)
            // An attribute needs whitespace before it.
            guard afterSpace > index, let attribute = scanAttribute(from: afterSpace) else {
                index = afterSpace
                break
            }
            index = attribute
        }
        if scalar(at: index) == "/" { index += 1 }
        return scalar(at: index) == ">" ? index + 1 : nil
    }

    private func scanAttribute(from start: Int) -> Int? {
        guard let first = scalar(at: start), Self.isASCIILetter(first) || first == "_" || first == ":" else {
            return nil
        }
        var index = start + 1
        while let scalar = scalar(at: index),
            Self.isASCIIAlphanumeric(scalar) || "_.:-".unicodeScalars.contains(scalar)
        {
            index += 1
        }
        let beforeValue = skipSpaces(from: index)
        guard scalar(at: beforeValue) == "=" else { return index }
        let valueStart = skipSpaces(from: beforeValue + 1)
        guard let opening = scalar(at: valueStart) else { return nil }
        if opening == "\"" || opening == "'" {
            var end = valueStart + 1
            while let scalar = scalar(at: end), scalar != opening { end += 1 }
            guard scalar(at: end) == opening else { return nil }
            return end + 1
        }
        var end = valueStart
        while let scalar = scalar(at: end), !isSpace(end), !"\"'=<>`".unicodeScalars.contains(scalar) {
            end += 1
        }
        return end > valueStart ? end : nil
    }

    private func scanClosingTag(from start: Int) -> Int? {
        guard let name = scanTagName(from: start) else { return nil }
        let index = skipSpaces(from: name)
        return scalar(at: index) == ">" ? index + 1 : nil
    }

    /// `<!--` has been read: text that does not start with `>` or `->`, holds
    /// no `--`, does not end with `-`, then `-->`.
    private func scanComment(from start: Int) -> Int? {
        if scalar(at: start) == ">" { return nil }
        if scalar(at: start) == "-", scalar(at: start + 1) == ">" { return nil }
        var index = start
        while let scalar = scalar(at: index) {
            if scalar == "-", self.scalar(at: index + 1) == "-" {
                return self.scalar(at: index + 2) == ">" ? index + 3 : nil
            }
            index += 1
        }
        return nil
    }

    /// `<!` has been read: uppercase letters, whitespace, anything but `>`.
    private func scanDeclaration(from start: Int) -> Int? {
        var index = start
        while let scalar = scalar(at: index), (0x41...0x5A).contains(scalar.value) { index += 1 }
        guard index > start, isSpace(index) else { return nil }
        while let scalar = scalar(at: index), scalar != ">" { index += 1 }
        return scalar(at: index) == ">" ? index + 1 : nil
    }

    /// Past the first `terminator` at or after `start`, with no argument
    /// between; `nil` when there is none.
    private func scanUntil(_ terminator: String, from start: Int) -> Int? {
        let count = terminator.unicodeScalars.count
        var index = start
        while index + count <= source.count {
            if source[index].scalar == nil { return nil }
            if Self.startsWith(terminator, in: source, at: index) { return index + count }
            index += 1
        }
        return nil
    }
}
