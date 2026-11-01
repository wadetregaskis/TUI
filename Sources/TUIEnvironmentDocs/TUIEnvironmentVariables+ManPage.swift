//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables+ManPage.swift
//
//  The table as the ENVIRONMENT section of a man page.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Which macro package a man page is written in.
///
/// A TUI-specific type, with no SwiftUI counterpart.
public enum ManPageFormat: String, Sendable, Hashable, CaseIterable {
    /// The `man(7)` macros: `.SH`, `.TP`. The older of the two, and what a page starting
    /// with `.TH` is written in.
    case man

    /// The `mdoc(7)` macros: `.Sh`, `.Bl`, `.It`. What a page starting with `.Dd`
    /// is written in.
    case mdoc
}

extension TUIEnvironmentVariables {
    /// The variables for `audience`, as the ENVIRONMENT section of a man page, to put
    /// into a page of your own.
    ///
    /// ```swift
    /// print(TUIEnvironmentVariables.manPageSection(format: .mdoc))
    /// ```
    ///
    /// Each topic is a subsection, and each variable has a value line and a description.
    ///
    /// - Parameters:
    ///   - format: Which macros to write it in. By default, `man(7)`.
    ///   - audience: Whose variables. By default, those for the person running the app.
    ///   - includesHeading: Whether it starts with `ENVIRONMENT`'s own heading.
    ///     Pass `false` to put your program's own variables under that heading first.
    /// - Returns: The text, ending in a newline, in nothing but ASCII.
    public static func manPageSection(
        format: ManPageFormat = .man, audience: TUIEnvironmentVariable.Audience = .endUser,
        includesHeading: Bool = true
    ) -> String {
        let writer = ManPageWriter(format: format)
        var lines: [String] = []
        if includesHeading { lines.append(writer.sectionHeading("ENVIRONMENT")) }
        lines += writer.paragraph(introduction(for: audience))
        for group in grouped(variables(for: audience)) {
            lines.append(writer.subsectionHeading(group.topic.title))
            lines += writer.definitions(group.variables)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// What differs between writing a page in `man(7)` and in `mdoc(7)`.
private struct ManPageWriter {
    let format: ManPageFormat

    func sectionHeading(_ title: String) -> String {
        format == .man ? ".SH \(title)" : ".Sh \(title)"
    }

    func subsectionHeading(_ title: String) -> String {
        format == .man ? ".SS \(title)" : ".Ss \(title)"
    }

    /// A paragraph that starts a section or subsection, so that needs no macro of its own.
    func paragraph(_ markdown: String) -> [String] {
        sentences(markdown)
    }

    /// `variables` as a list of terms and their descriptions.
    func definitions(_ variables: [TUIEnvironmentVariable]) -> [String] {
        var lines: [String] = []
        if format == .mdoc { lines.append(".Bl -tag -width Ds") }
        for variable in variables {
            switch format {
            case .man:
                lines += [".TP", ".B \(variable.name)"]
            case .mdoc:
                lines.append(".It Ev \(variable.name)")
            }
            if variable.audience != .detected {
                lines += sentences("Values: \(variable.values).")
            }
            lines += sentences(variable.effect)
        }
        if format == .mdoc { lines.append(".El") }
        return lines
    }

    /// Markdown, as source lines of one sentence each, which is what both macro packages
    /// ask for: a roff line that ends a sentence gets a sentence's space.
    private func sentences(_ markdown: String) -> [String] {
        ManPageText.sentences(in: markdown).flatMap { sentence in
            switch format {
            case .man: ManPageText.manLines(sentence)
            case .mdoc: ManPageText.mdocLines(sentence)
            }
        }
    }
}

/// Turning the table's Markdown into roff: one sentence to a line, with its code spans
/// set off and with what roff would otherwise take for itself escaped.
private enum ManPageText {
    /// `text`, with a backslash said so that roff keeps it.
    static func escaped(_ text: String) -> String {
        text.split(separator: "\\", omittingEmptySubsequences: false).joined(separator: "\\e")
    }

    /// `text` from a code span, with its hyphens said too. A bare hyphen is what roff can
    /// turn into a typographer's, which doesn't copy and paste as a flag or a name.
    static func escapedCode(_ text: String) -> String {
        escaped(text).split(separator: "-", omittingEmptySubsequences: false).joined(separator: "\\-")
    }

    /// `markdown` split after each `.` that ends a sentence: one with a space after it,
    /// outside a code span.
    static func sentences(in markdown: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var inCode = false
        let characters = Array(markdown)
        for (index, character) in characters.enumerated() {
            if character == "`" { inCode.toggle() }
            if !inCode, character == " ", index > 0, characters[index - 1] == "." {
                sentences.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    /// The parts of `markdown` in order, each saying whether it was a code span.
    private static func spans(of markdown: String) -> [(text: String, isCode: Bool)] {
        markdown.split(separator: "`", omittingEmptySubsequences: false).enumerated().compactMap { index, part in
            part.isEmpty ? nil : (String(part), !index.isMultiple(of: 2))
        }
    }

    /// The `man(7)` lines for one sentence, with each code span in bold.
    static func manLines(_ sentence: String) -> [String] {
        let text = spans(of: sentence).map { span in
            span.isCode ? "\\fB\(escapedCode(span.text))\\fR" : escaped(span.text)
        }
        return filled(text.joined())
    }

    /// `mdoc(7)` lines for one sentence. A code span has to be a macro line of its own
    /// (`.Li`), with any punctuation that follows it on that line, where `mdoc` places
    /// it without a space.
    static func mdocLines(_ sentence: String) -> [String] {
        var lines: [String] = []
        var pendingCode: String?
        for span in spans(of: sentence) {
            if span.isCode {
                if let code = pendingCode { lines.append(".Li \(code)") }
                pendingCode = quoted(span.text)
                continue
            }
            var text = span.text
            if let code = pendingCode {
                // Punctuation straight after the span goes on its macro line.
                let punctuation = text.prefix { ",.:;)".contains($0) }
                text.removeFirst(punctuation.count)
                lines.append(punctuation.isEmpty ? ".Li \(code)" : ".Li \(code) \(punctuation.map(String.init).joined(separator: " "))")
                pendingCode = nil
            }
            lines += filled(escaped(text))
        }
        if let code = pendingCode { lines.append(".Li \(code)") }
        return lines
    }

    /// `text` as one argument of a macro.
    private static func quoted(_ text: String) -> String {
        let code = escapedCode(text)
        return code.contains(" ") ? "\"\(code)\"" : code
    }

    /// `text` as source lines of at most 80 bytes, which roff fills back together, each
    /// safe to start a line: a `.` or a `'` there would make it a request.
    private static func filled(_ text: String) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty, line.utf8.count + 1 + word.utf8.count > 80 {
                lines.append(line)
                line = ""
            }
            line += line.isEmpty ? String(word) : " \(word)"
        }
        if !line.isEmpty { lines.append(line) }
        return lines.map { $0.hasPrefix(".") || $0.hasPrefix("'") ? "\\&" + $0 : $0 }
    }
}
