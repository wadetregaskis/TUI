//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser.swift
//
//  The inline parse itself: CommonMark's algorithm, a list of nodes with a
//  delimiter stack and a bracket stack over it, plus cmark-gfm's strikethrough
//  and autolink extensions. See `InlineMarkdown` for what it reads.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One inline parse. Single use: ``run()`` consumes it.
///
/// The structure is CommonMark's reference algorithm (spec appendix, "An
/// algorithm for parsing nested emphasis and links"), flattened: instead of a
/// tree, every node carries the traits and link of everything that encloses
/// it, which is all a `Text` run needs and all Foundation's runs say.
struct InlineMarkdownParser {
    typealias Atom = InlineMarkdown.Atom
    typealias Traits = InlineMarkdown.Traits

    let source: [Atom]
    var position = 0
    var nodes: [Node] = []
    var delimiters: [Delimiter] = []
    var brackets: [Bracket] = []
    /// The link reference definitions the source opens with, by normalized
    /// label (``parseReferenceDefinitions()``): empty for nearly every key.
    var definitions: [String: [Atom]] = [:]

    init(source: [Atom]) {
        self.source = source
    }

    /// A piece of the output, in source order.
    struct Node {
        enum Kind {
            /// Text: literal characters, escapes, references.
            case text
            /// A delimiter run (`*`, `_`, `~`) — text until it is matched.
            case delimiter
            /// A `[`, `![` or `^[` — text until its `]` makes it something.
            case bracket
            /// Code span contents.
            case code
            /// An autolink's text, already linked.
            case autolink
            /// Raw HTML, which SwiftUI draws as the text it is — kept apart so
            /// nothing inside a tag is read as a delimiter or an address.
            case html
        }

        var atoms: [Atom]
        var kind: Kind
        var traits: Traits = []
        var link: [Atom]?
        var removed = false
    }

    /// An entry on the delimiter stack.
    struct Delimiter {
        let node: Int
        let character: Unicode.Scalar
        /// The run's length as written — what the rule of three counts.
        let originalCount: Int
        /// What is left of it after matches.
        var remaining: Int
        let canOpen: Bool
        let canClose: Bool
        var removed = false
    }

    /// An entry on the bracket stack.
    struct Bracket {
        enum Kind { case link, image, attribute }
        let node: Int
        let kind: Kind
        /// Where the bracket's text starts in the source, after its `[`: a
        /// reference link's label, when it is used as one.
        let textStart: Int
        /// The delimiter stack's height when the bracket opened: emphasis
        /// inside the brackets is resolved down to here and no further.
        let delimiterBottom: Int
        var active = true
    }

    // MARK: - Driver

    /// Parses the whole source.
    mutating func run() -> [InlineMarkdown.Span] {
        parseReferenceDefinitions()
        while position < source.count {
            parseOne()
        }
        processEmphasis(bottom: 0)
        linkEmailAddresses()
        return spans()
    }

    private mutating func parseOne() {
        guard let scalar = source[position].scalar else {
            appendText(source[position])
            position += 1
            return
        }
        switch scalar {
        case "\\":
            parseBackslash()
        case "`":
            parseCodeSpan()
        case "*", "_", "~":
            parseDelimiterRun(scalar)
        case "[":
            pushBracket(.link, length: 1)
        case "!" where atom(at: position + 1)?.is("[") == true:
            pushBracket(.image, length: 2)
        case "^" where atom(at: position + 1)?.is("[") == true:
            pushBracket(.attribute, length: 2)
        case "]":
            closeBracket()
        case "<":
            parseAngleAutolink()
        case "&":
            parseReference()
        case "w" where matchWWWAutolink():
            break
        case ":" where matchURLAutolink():
            break
        default:
            appendText(source[position])
            position += 1
        }
    }

    func atom(at index: Int) -> Atom? {
        index >= 0 && index < source.count ? source[index] : nil
    }

    /// Appends literal text, joining the previous node when that is text too.
    mutating func appendText(_ atoms: [Atom]) {
        if let last = nodes.indices.last, nodes[last].kind == .text, !nodes[last].removed {
            nodes[last].atoms += atoms
        } else {
            nodes.append(Node(atoms: atoms, kind: .text))
        }
    }

    /// Appends one literal atom, as the array form does: the parse's
    /// commonest step, a plain character, without building a one-element
    /// array for it.
    mutating func appendText(_ atom: Atom) {
        if let last = nodes.indices.last, nodes[last].kind == .text, !nodes[last].removed {
            nodes[last].atoms.append(atom)
        } else {
            nodes.append(Node(atoms: [atom], kind: .text))
        }
    }

    /// cmark's `isspace`: space, tab, line feed, vertical tab, form feed,
    /// carriage return.
    static func isASCIIWhitespace(_ atom: Atom) -> Bool {
        guard let scalar = atom.scalar else { return false }
        return scalar == " " || (0x09...0x0D).contains(scalar.value)
    }

    static func isASCIIPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E: return true
        default: return false
        }
    }

    // MARK: - Escapes and code spans

    private mutating func parseBackslash() {
        let next = atom(at: position + 1)
        if let escaped = next?.scalar, Self.isASCIIPunctuation(escaped) {
            appendText(.scalar(escaped))
            position += 2
        } else if next?.is("\n") == true {
            // A hard line break, which SwiftUI draws as the newline it is.
            appendText(.scalar("\n"))
            position += 2
        } else {
            appendText(.scalar("\\"))
            position += 1
        }
    }

    private mutating func parseCodeSpan() {
        let start = position
        while position < source.count, source[position].is("`") { position += 1 }
        let length = position - start
        var search = position
        while search < source.count {
            guard source[search].is("`") else {
                search += 1
                continue
            }
            let closeStart = search
            while search < source.count, source[search].is("`") { search += 1 }
            guard search - closeStart == length else { continue }
            var content = source[position..<closeStart].map { $0.is("\n") ? Atom.scalar(" ") : $0 }
            if content.count >= 2, content[0].is(" "), content[content.count - 1].is(" "),
                content.contains(where: { !$0.is(" ") })
            {
                content.removeFirst()
                content.removeLast()
            }
            nodes.append(Node(atoms: content, kind: .code, traits: .code))
            position = search
            return
        }
        // No closer: the backticks are literal, and parsing resumes after them.
        appendText(Array(source[start..<position]))
    }

    // MARK: - Delimiter runs

    private mutating func parseDelimiterRun(_ character: Unicode.Scalar) {
        let start = position
        while position < source.count, source[position].is(character) { position += 1 }
        let length = position - start
        let run = Array(source[start..<position])
        // GitHub's strikethrough takes one tilde or two; a longer run is text.
        guard character != "~" || length <= 2 else {
            appendText(run)
            return
        }
        // cmark-gfm makes the strikethrough tilde a "skip character": the
        // characters either side of a run are found by stepping over any
        // tildes beside it. Measured through Foundation — `*x ~*` stays text,
        // because the closer's neighbour is the space, and `x*~~a~~*` is
        // emphasis, because the opener's is the `a`.
        var beforeIndex = start - 1
        while atom(at: beforeIndex)?.is("~") == true { beforeIndex -= 1 }
        var afterIndex = position
        while atom(at: afterIndex)?.is("~") == true { afterIndex += 1 }
        let before = atom(at: beforeIndex)
        let after = atom(at: afterIndex)
        let beforeIsWhitespace = before?.isWhitespace ?? true
        let afterIsWhitespace = after?.isWhitespace ?? true
        let beforeIsPunctuation = before?.isPunctuation ?? false
        let afterIsPunctuation = after?.isPunctuation ?? false
        let leftFlanking =
            !afterIsWhitespace && (!afterIsPunctuation || beforeIsWhitespace || beforeIsPunctuation)
        let rightFlanking =
            !beforeIsWhitespace && (!beforeIsPunctuation || afterIsWhitespace || afterIsPunctuation)
        let canOpen: Bool
        let canClose: Bool
        if character == "_" {
            // An underscore may not open or close inside a word.
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunctuation)
            canClose = rightFlanking && (!leftFlanking || afterIsPunctuation)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        nodes.append(Node(atoms: run, kind: .delimiter))
        delimiters.append(
            Delimiter(
                node: nodes.count - 1, character: character, originalCount: length, remaining: length,
                canOpen: canOpen, canClose: canClose))
    }

    // MARK: - Brackets

    private mutating func pushBracket(_ kind: Bracket.Kind, length: Int) {
        nodes.append(Node(atoms: Array(source[position..<(position + length)]), kind: .bracket))
        brackets.append(
            Bracket(node: nodes.count - 1, kind: kind, textStart: position + length, delimiterBottom: delimiters.count))
        position += length
    }

    /// Whether any bracket is open — inside one, cmark-gfm matches no bare-URL
    /// autolink.
    var isInBracket: Bool { !brackets.isEmpty }

    private mutating func closeBracket() {
        let closer = position
        position += 1
        guard let opener = brackets.last else {
            appendText(.scalar("]"))
            return
        }
        guard opener.active else {
            brackets.removeLast()
            appendText(.scalar("]"))
            return
        }
        let destination: [Atom]?
        if opener.kind == .attribute {
            destination = parseAttributeTail().map { _ in [] }
        } else {
            destination = parseLinkTail() ?? parseReferenceTail(text: opener.textStart..<closer)
        }
        guard let destination else {
            brackets.removeLast()
            appendText(.scalar("]"))
            return
        }
        processEmphasis(bottom: opener.delimiterBottom)
        for index in (opener.node + 1)..<nodes.count where !nodes[index].removed {
            switch opener.kind {
            case .link:
                // Foundation keeps none of the emphasis inside a link's text
                // (measured: `[a *b*](u)` is one plain linked run), and
                // nothing inside a link is autolinked.
                nodes[index].traits = []
                nodes[index].link = destination
                if nodes[index].kind == .text || nodes[index].kind == .delimiter {
                    nodes[index].kind = .autolink
                }
            case .image:
                // SwiftUI draws an image's alt text, plain.
                nodes[index].traits = []
                nodes[index].link = nil
            case .attribute:
                break
            }
        }
        if opener.kind == .image,
            !nodes[(opener.node + 1)...].contains(where: { !$0.removed && !$0.atoms.isEmpty })
        {
            // An image with no alt text is the attachment character, as in
            // Foundation's string.
            nodes.append(Node(atoms: [.scalar("\u{FFFC}")], kind: .html))
        }
        nodes[opener.node].removed = true
        brackets.removeLast()
        if opener.kind == .link {
            // Links do not nest: every `[` before this one is now text.
            for index in brackets.indices where brackets[index].kind == .link {
                brackets[index].active = false
            }
        }
    }

    /// `(destination "title")` after a `]`, or `nil` if what follows is not
    /// one. Leaves ``position`` past the `)` on success.
    private mutating func parseLinkTail() -> [Atom]? {
        guard atom(at: position)?.is("(") == true else { return nil }
        guard let (destination, afterDestination) = scanLinkDestination(from: skipLinkWhitespace(from: position + 1))
        else { return nil }
        var index = skipLinkWhitespace(from: afterDestination)
        // A title needs whitespace between it and the destination.
        if index > afterDestination, let afterTitle = scanLinkTitle(from: index) {
            index = skipLinkWhitespace(from: afterTitle)
        } else if index > afterDestination, let opening = atom(at: index)?.scalar,
            opening == "\"" || opening == "'" || opening == "("
        {
            return nil
        }
        guard atom(at: index)?.is(")") == true else { return nil }
        position = index + 1
        return Self.decodingReferences(in: destination)
    }

    /// A link destination at `start` and the index past it, or `nil`.
    ///
    /// Scanned as Foundation's cmark scans it, which is older than the
    /// CommonMark spec in one way that shows: a bare destination may leave a
    /// `(` unclosed when whitespace ends it (measured, `[b](x(y )` links to
    /// `x(y`). Running into the end of the source is a failure either way.
    func scanLinkDestination(from start: Int) -> ([Atom], Int)? {
        var destination: [Atom] = []
        var index = start
        let bracketed = atom(at: index)?.is("<") == true
        if bracketed { index += 1 }
        var depth = 0
        while true {
            guard let atom = atom(at: index) else { return nil }
            if atom.is("\\"), let next = self.atom(at: index + 1)?.scalar, Self.isASCIIPunctuation(next) {
                destination.append(.scalar(next))
                index += 2
                continue
            }
            if bracketed {
                if atom.is(">") {
                    // Something must follow: at the very least the `)`.
                    return index + 1 < source.count ? (destination, index + 1) : nil
                }
                if atom.is("\n") || atom.is("<") { return nil }
            } else if atom.is("(") {
                depth += 1
                guard depth <= 32 else { return nil }
            } else if atom.is(")") {
                if depth == 0 { return (destination, index) }
                depth -= 1
            } else if Self.isASCIIWhitespace(atom) {
                return (destination, index)
            }
            destination.append(atom)
            index += 1
        }
    }

    /// A link title — `"…"`, `'…'` or `(…)` — at `start` and the index past it,
    /// or `nil`.
    func scanLinkTitle(from start: Int) -> Int? {
        guard let opening = atom(at: start)?.scalar, opening == "\"" || opening == "'" || opening == "(" else {
            return nil
        }
        let closing: Unicode.Scalar = opening == "(" ? ")" : opening
        var index = start + 1
        while let atom = atom(at: index) {
            if atom.is("\\"), self.atom(at: index + 1) != nil {
                index += 2
                continue
            }
            if atom.is(closing) { return index + 1 }
            if opening == "(", atom.is("(") { return nil }
            index += 1
        }
        return nil
    }

    /// Spaces and tabs, and at most one line ending among them.
    func skipLinkWhitespace(from start: Int) -> Int {
        var index = start
        var sawNewline = false
        while let atom = atom(at: index) {
            if atom.is(" ") || atom.is("\t") {
                index += 1
            } else if atom.is("\n"), !sawNewline {
                sawNewline = true
                index += 1
            } else {
                break
            }
        }
        return index
    }

    /// The `(…)` of Apple's `^[text](attributes)`: anything, parentheses
    /// balanced and quotes respected. TUI reads none of the attributes —
    /// it has no inflection — so this only finds the end.
    private mutating func parseAttributeTail() -> Void? {
        guard atom(at: position)?.is("(") == true else { return nil }
        var index = position + 1
        var depth = 0
        var quote: Unicode.Scalar?
        while let atom = atom(at: index) {
            defer { index += 1 }
            guard let scalar = atom.scalar else { continue }
            if let open = quote {
                if scalar == "\\" {
                    index += 1
                } else if scalar == open {
                    quote = nil
                }
                continue
            }
            switch scalar {
            case "\"", "'": quote = scalar
            case "(": depth += 1
            case ")":
                if depth == 0 {
                    position = index + 1
                    return ()
                }
                depth -= 1
            default: break
            }
        }
        return nil
    }
}
