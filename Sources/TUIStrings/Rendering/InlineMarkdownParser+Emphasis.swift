//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser+Emphasis.swift
//
//  CommonMark's "process emphasis" over the delimiter stack, with cmark-gfm's
//  strikethrough rule, and the flattening of the nodes into spans.
//
//  Created by Wade Tregaskis
//  License: MIT

extension InlineMarkdownParser {
    /// Which openers a closer has already searched, keyed as Foundation's
    /// cmark keys them: the character and the closer's length modulo three.
    /// (CommonMark 0.30 added whether the closer can also open; Foundation's
    /// parser predates it — measured, `&b*__a~t*&_:&t<_:_` stays unpaired.)
    private struct OpenersKey: Hashable {
        let character: Unicode.Scalar
        let lengthModThree: Int
    }

    /// Matches the delimiters above `bottom` into emphasis, strong emphasis
    /// and strikethrough, then drops every delimiter above `bottom`: what is
    /// left of them is text.
    mutating func processEmphasis(bottom: Int) {
        var openersBottom: [OpenersKey: Int] = [:]
        var closerIndex = nextDelimiter(from: bottom)
        while let closer = closerIndex {
            guard delimiters[closer].canClose else {
                closerIndex = nextDelimiter(from: closer + 1)
                continue
            }
            let key = OpenersKey(
                character: delimiters[closer].character, lengthModThree: delimiters[closer].originalCount % 3)
            let floor = max(openersBottom[key] ?? bottom, bottom)
            if let opener = findOpener(for: closer, floor: floor) {
                closerIndex = match(opener: opener, closer: closer)
            } else {
                openersBottom[key] = closer
                if !delimiters[closer].canOpen {
                    delimiters[closer].removed = true
                }
                closerIndex = nextDelimiter(from: closer + 1)
            }
        }
        for index in bottom..<delimiters.count {
            delimiters[index].removed = true
        }
    }

    /// The nearest delimiter at or after `start` still on the stack.
    private func nextDelimiter(from start: Int) -> Int? {
        var index = start
        while index < delimiters.count {
            if !delimiters[index].removed { return index }
            index += 1
        }
        return nil
    }

    /// The nearest opener below `closer`, and at or above `floor`, that may
    /// pair with it.
    private func findOpener(for closer: Int, floor: Int) -> Int? {
        let closing = delimiters[closer]
        var index = closer - 1
        while index >= floor {
            defer { index -= 1 }
            let opening = delimiters[index]
            guard !opening.removed, opening.canOpen, opening.character == closing.character else { continue }
            // The rule of three: a run that can both open and close pairs only
            // when the lengths do not sum to a multiple of three, unless both
            // are multiples of three. cmark-gfm applies it to tildes too.
            let eitherIsBoth = closing.canOpen || opening.canClose
            let sumIsMultiple = (opening.originalCount + closing.originalCount).isMultiple(of: 3)
            if eitherIsBoth, !closing.originalCount.isMultiple(of: 3), sumIsMultiple { continue }
            return index
        }
        return nil
    }

    /// Pairs `opener` with `closer`; returns the delimiter to look at next.
    private mutating func match(opener: Int, closer: Int) -> Int? {
        let used: Int
        let trait: Traits
        if delimiters[closer].character == "~" {
            // cmark-gfm strikes through only between runs of one length; a
            // mismatched pair is spent anyway — both runs, and every delimiter
            // between them, stay as text.
            guard delimiters[opener].remaining == delimiters[closer].remaining else {
                for index in opener...closer {
                    delimiters[index].removed = true
                }
                return nextDelimiter(from: closer + 1)
            }
            used = delimiters[closer].remaining
            trait = .strikethrough
        } else {
            used = delimiters[closer].remaining >= 2 && delimiters[opener].remaining >= 2 ? 2 : 1
            trait = used == 2 ? .strong : .emphasized
        }
        let openerNode = delimiters[opener].node
        let closerNode = delimiters[closer].node
        nodes[openerNode].atoms.removeLast(used)
        nodes[closerNode].atoms.removeFirst(used)
        delimiters[opener].remaining -= used
        delimiters[closer].remaining -= used
        // Foundation turns a style on where its node opens and OFF where it
        // closes, so emphasis nested in emphasis ends the outer one too:
        // `*a *b* c*` is "a b" in italics and " c" upright, measured. Matches
        // resolve innermost first, so a node already carrying this trait is
        // an inner span, and nothing after one gets the trait from this span.
        var passedInner = false
        for index in (openerNode + 1)..<closerNode where !nodes[index].removed {
            if nodes[index].traits.contains(trait) {
                passedInner = true
            } else if !passedInner {
                nodes[index].traits.insert(trait)
            }
        }
        for index in (opener + 1)..<closer {
            delimiters[index].removed = true
        }
        if delimiters[opener].remaining == 0 {
            delimiters[opener].removed = true
            nodes[openerNode].removed = true
        }
        if delimiters[closer].remaining == 0 {
            delimiters[closer].removed = true
            nodes[closerNode].removed = true
            return nextDelimiter(from: closer + 1)
        }
        return closer
    }

    // MARK: - Output

    /// The nodes as spans: empty and removed nodes dropped, neighbours with
    /// the same traits and link merged, as Foundation's runs are.
    func spans() -> [InlineMarkdown.Span] {
        var result: [InlineMarkdown.Span] = []
        for node in nodes where !node.removed && !node.atoms.isEmpty {
            let traits = node.traits
            if let last = result.indices.last, result[last].traits == traits, result[last].link == node.link {
                result[last].atoms += node.atoms
            } else {
                result.append(InlineMarkdown.Span(atoms: node.atoms, traits: traits, link: node.link))
            }
        }
        return result
    }
}
