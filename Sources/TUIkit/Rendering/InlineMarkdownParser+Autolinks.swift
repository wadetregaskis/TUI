//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InlineMarkdownParser+Autolinks.swift
//
//  Links that need no brackets: CommonMark's `<scheme:…>` and `<email>`, and
//  cmark-gfm's bare `www.`, `http(s)://`/`ftp://` and email-address autolinks,
//  with cmark-gfm's rules for where one ends.
//
//  Created by Wade Tregaskis
//  License: MIT

extension InlineMarkdownParser {
    // MARK: - <scheme:…> and <email>

    mutating func parseAngleAutolink() {
        if let (content, end) = scanAngleAutolink() {
            let isEmail = !content.contains { $0.is(":") }
            let destination = isEmail ? Self.atoms("mailto:") + content : content
            nodes.append(Node(atoms: content, kind: .autolink, link: destination))
            position = end
        } else if let end = scanRawHTML() {
            nodes.append(Node(atoms: Array(source[position..<end]), kind: .html))
            position = end
        } else {
            appendText(.scalar("<"))
            position += 1
        }
    }

    /// The contents of a `<…>` autolink at ``position`` and the index past its
    /// `>`, or `nil`.
    private func scanAngleAutolink() -> ([Atom], Int)? {
        var index = position + 1
        var content: [Unicode.Scalar] = []
        while let atom = atom(at: index), !atom.is(">") {
            guard let scalar = atom.scalar else { return nil }
            content.append(scalar)
            index += 1
        }
        guard atom(at: index)?.is(">") == true, !content.isEmpty else { return nil }
        let atoms = content.map(Atom.scalar)
        return Self.isURIAutolink(content) || Self.isEmailAutolink(content) ? (atoms, index + 1) : nil
    }

    /// CommonMark's absolute URI: a 2–32 character scheme, a colon, and no
    /// spaces, controls or angle brackets.
    private static func isURIAutolink(_ content: [Unicode.Scalar]) -> Bool {
        guard let colon = content.firstIndex(of: ":"), (2...32).contains(colon), isASCIILetter(content[0])
        else { return false }
        for scalar in content[1..<colon] {
            guard isASCIILetter(scalar) || isASCIIDigit(scalar) || "+.-".unicodeScalars.contains(scalar) else {
                return false
            }
        }
        return content[(colon + 1)...].allSatisfy { $0.value > 0x20 && $0 != "<" && $0 != ">" && $0.value != 0x7F }
    }

    /// CommonMark's email autolink: HTML's valid e-mail address.
    private static func isEmailAutolink(_ content: [Unicode.Scalar]) -> Bool {
        guard let at = content.firstIndex(of: "@"), at > 0, at < content.count - 1 else { return false }
        let localSpecials = ".!#$%&'*+/=?^_`{|}~-".unicodeScalars
        guard content[..<at].allSatisfy({ isASCIILetter($0) || isASCIIDigit($0) || localSpecials.contains($0) })
        else { return false }
        let labels = content[(at + 1)...].split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard let first = label.first, let last = label.last, label.count <= 63 else { return false }
            return isASCIIAlphanumeric(first) && isASCIIAlphanumeric(last)
                && label.allSatisfy { isASCIIAlphanumeric($0) || $0 == "-" }
        }
    }

    // MARK: - Bare www. and URL autolinks (cmark-gfm `www_match`, `url_match`)

    /// A `www.` autolink at ``position``, if one starts here.
    mutating func matchWWWAutolink() -> Bool {
        guard !isInBracket else { return false }
        if let before = atom(at: position - 1) {
            guard before.isWhitespace || before.is("*") || before.is("_") || before.is("~") || before.is("(")
            else { return false }
        }
        guard Self.startsWith("www.", in: source, at: position) else { return false }
        let domain = checkDomain(from: position, allowShort: false)
        guard domain > 0 else { return false }
        let end = autolinkDelimit(from: position, end: extendPath(from: position + domain))
        guard end > position else { return false }
        let text = Array(source[position..<end])
        nodes.append(Node(atoms: text, kind: .autolink, link: Self.atoms("http://") + text))
        position = end
        return true
    }

    /// A `scheme://` autolink whose colon is at ``position``, if the letters
    /// before it name `http`, `https` or `ftp`.
    mutating func matchURLAutolink() -> Bool {
        guard !isInBracket, atom(at: position + 1)?.is("/") == true, atom(at: position + 2)?.is("/") == true,
            position + 3 < source.count
        else { return false }
        var rewind = 0
        while let previous = atom(at: position - rewind - 1)?.scalar, Self.isASCIILetter(previous) {
            rewind += 1
        }
        let scheme = String(String.UnicodeScalarView(source[(position - rewind)..<position].compactMap(\.scalar)))
            .lowercased()
        guard ["http", "https", "ftp"].contains(scheme),
            let afterSlashes = atom(at: position + 3)?.scalar, Self.isASCIIAlphanumeric(afterSlashes)
        else { return false }
        // The scheme's letters are already in the text node being built.
        guard rewind > 0, let last = nodes.indices.last, nodes[last].kind == .text, !nodes[last].removed,
            nodes[last].atoms.count >= rewind,
            nodes[last].atoms.suffix(rewind).elementsEqual(source[(position - rewind)..<position])
        else { return false }
        let domain = checkDomain(from: position + 3, allowShort: true)
        guard domain > 0 else { return false }
        let end = autolinkDelimit(from: position, end: extendPath(from: position + 3 + domain))
        guard end > position else { return false }
        nodes[last].atoms.removeLast(rewind)
        let text = Array(source[(position - rewind)..<end])
        nodes.append(Node(atoms: text, kind: .autolink, link: text))
        position = end
        return true
    }

    /// cmark-gfm's `check_domain`: how far a host name runs from `start`, or 0
    /// when it is not one — an underscore in either of the last two labels, or
    /// (unless `allowShort`) no dot at all.
    private func checkDomain(from start: Int, allowShort: Bool) -> Int {
        let size = source.count - start
        var index = 1
        var dots = 0
        var underscoresBeforeLastDot = 0
        var underscoresSinceLastDot = 0
        while index < size - 1 {
            if source[start + index].is("\\"), index < size - 2 {
                index += 1
            }
            let atom = source[start + index]
            if atom.is("_") {
                underscoresSinceLastDot += 1
            } else if atom.is(".") {
                underscoresBeforeLastDot = underscoresSinceLastDot
                underscoresSinceLastDot = 0
                dots += 1
            } else if !Self.isHostCharacter(atom), !atom.is("-") {
                break
            }
            index += 1
        }
        if underscoresBeforeLastDot > 0 || underscoresSinceLastDot > 0 { return 0 }
        return allowShort || dots > 0 ? index : 0
    }

    private static func isHostCharacter(_ atom: Atom) -> Bool {
        atom.scalar != nil && !atom.isWhitespace && !atom.isPunctuation
    }

    /// Past the path: everything up to whitespace, a `<` or an argument.
    private func extendPath(from start: Int) -> Int {
        var end = start
        while let atom = atom(at: end), atom.scalar != nil, !atom.isWhitespace, !atom.is("<") {
            end += 1
        }
        return end
    }

    /// cmark-gfm's `autolink_delim`: where a link that runs from `start` to
    /// `end` really ends — at a `<`, and short of trailing punctuation, an
    /// unbalanced `)` and a trailing entity-like `&name;`.
    private func autolinkDelimit(from start: Int, end: Int) -> Int {
        Self.autolinkDelimit(Array(source[start..<end])) + start
    }

    static func autolinkDelimit(_ atoms: [Atom]) -> Int {
        var end = atoms.count
        var opening = 0
        var closing = 0
        for (index, atom) in atoms.enumerated() {
            if atom.is("<") {
                end = index
                break
            } else if atom.is("(") {
                opening += 1
            } else if atom.is(")") {
                closing += 1
            }
        }
        while end > 0 {
            guard let last = atoms[end - 1].scalar else { return end }
            switch last {
            case ")":
                if closing <= opening { return end }
                closing -= 1
                end -= 1
            case "?", "!", ".", ",", ":", "*", "_", "~", "'", "\"":
                end -= 1
            case ";":
                var newEnd = end - 2
                while newEnd > 0, let scalar = atoms[newEnd].scalar, isASCIILetter(scalar) { newEnd -= 1 }
                if newEnd < end - 2, atoms[newEnd].is("&") {
                    end = newEnd
                } else {
                    end -= 1
                }
            default:
                return end
            }
        }
        return end
    }

    // MARK: - Email addresses (cmark-gfm's text post-process)

    /// Links every bare email address in the plain text, as cmark-gfm's
    /// post-process does once the inline parse is finished.
    mutating func linkEmailAddresses() {
        var result: [Node] = []
        var pending: Node?
        func flush() {
            guard let node = pending else { return }
            result += Self.splittingEmailAddresses(node)
            pending = nil
        }
        for node in nodes {
            // A spent delimiter or bracket is where an emphasis or a link began
            // or ended — a different parent in cmark's tree, whose text nodes
            // are consolidated only among siblings.
            guard !node.removed else {
                flush()
                continue
            }
            let isPlain = (node.kind == .text || node.kind == .delimiter) && node.link == nil
            if isPlain, var current = pending, current.traits == node.traits {
                current.atoms += node.atoms
                pending = current
            } else {
                flush()
                if isPlain {
                    var plain = node
                    plain.kind = .text
                    pending = plain
                } else {
                    result.append(node)
                }
            }
        }
        flush()
        nodes = result
    }

    private static func splittingEmailAddresses(_ node: Node) -> [Node] {
        var pieces: [Node] = []
        var atoms = node.atoms
        var offset = 0
        while let link = emailAddress(in: atoms, from: offset) {
            if link.start > 0 {
                pieces.append(Node(atoms: Array(atoms[..<link.start]), kind: .text, traits: node.traits))
            }
            let text = Array(atoms[link.start..<link.end])
            pieces.append(
                Node(
                    atoms: text, kind: .autolink, traits: node.traits,
                    link: link.addsMailto ? Self.atoms("mailto:") + text : text))
            atoms = Array(atoms[link.end...])
            offset = 0
        }
        if !atoms.isEmpty {
            pieces.append(Node(atoms: atoms, kind: .text, traits: node.traits))
        }
        return pieces
    }

    /// cmark-gfm's `postprocess_text`: the next email address at or after
    /// `start`, as a range, and whether its link needs `mailto:`.
    ///
    /// Its loop, kept as written, quirk included: when the scan past an `@`
    /// meets a second `@`, it starts again from that one WITHOUT resetting its
    /// count of dots — so `a@b.c@d` links `b.c@d`, whose own domain has none.
    /// Measured through Foundation.
    private static func emailAddress(
        in atoms: [Atom], from start: Int
    ) -> (start: Int, end: Int, addsMailto: Bool)? {
        var offset = start
        while offset < atoms.count {
            guard var at = atoms[offset...].firstIndex(where: { $0.is("@") }) else { return nil }
            var maxRewind = at - offset
            var dots = 0
            var scheme = AddressScheme()
            var rewind = 0
            var linkEnd = 1
            while true {
                rewind = rewindLocalPart(atoms, at: at, maxRewind: maxRewind, scheme: &scheme)
                guard rewind > 0 else { break }
                switch scanDomain(atoms, at: at, isXMPP: scheme.isXMPP, dots: &dots) {
                case .end(let end):
                    linkEnd = end
                case .anotherAt(let next):
                    maxRewind = next - at - 1
                    at = next
                    continue
                }
                break
            }
            offset = at + 1
            guard rewind > 0, linkEnd >= 2, dots > 0, let last = atoms[at + linkEnd - 1].scalar,
                isASCIILetter(last) || last == "."
            else { continue }
            let delimited = autolinkDelimit(Array(atoms[at..<(at + linkEnd)]))
            guard delimited > 0 else { continue }
            return (at - rewind, at + delimited, scheme.addsMailto)
        }
        return nil
    }

    /// Whether an address was written with its scheme: `mailto:` spells its
    /// own link, `xmpp:` too and lets a resource follow a `/`.
    private struct AddressScheme {
        var addsMailto = true
        var isXMPP = false
    }

    /// How far back from the `@` at `at` the local part reaches, no further
    /// than `maxRewind`: letters, digits and `.+-_`, and a `mailto:` or `xmpp:`
    /// before them.
    private static func rewindLocalPart(
        _ atoms: [Atom], at: Int, maxRewind: Int, scheme: inout AddressScheme
    ) -> Int {
        var rewind = 0
        while rewind < maxRewind {
            guard let scalar = atoms[at - rewind - 1].scalar else { break }
            if isASCIIAlphanumeric(scalar) || ".+-_".unicodeScalars.contains(scalar) {
                rewind += 1
                continue
            }
            if scalar == ":", precedes(atoms, colon: at - rewind - 1, protocol: "mailto", floor: at - maxRewind) {
                scheme.addsMailto = false
                rewind += 1
                continue
            }
            if scalar == ":", precedes(atoms, colon: at - rewind - 1, protocol: "xmpp", floor: at - maxRewind) {
                scheme.addsMailto = false
                scheme.isXMPP = true
                rewind += 1
                continue
            }
            break
        }
        return rewind
    }

    private enum DomainScan {
        /// The address runs this far past its `@`.
        case end(Int)
        /// Another `@` stands here; the scan starts again from it.
        case anotherAt(Int)
    }

    /// The domain after the `@` at `at`, counting into `dots` each dot
    /// followed by a letter or digit.
    private static func scanDomain(_ atoms: [Atom], at: Int, isXMPP: Bool, dots: inout Int) -> DomainScan {
        var linkEnd = 1
        while at + linkEnd < atoms.count {
            guard let scalar = atoms[at + linkEnd].scalar else { break }
            if isASCIIAlphanumeric(scalar) || scalar == "-" || scalar == "_" || (scalar == "/" && isXMPP) {
                linkEnd += 1
                continue
            }
            if scalar == "@" { return .anotherAt(at + linkEnd) }
            guard scalar == ".", at + linkEnd + 1 < atoms.count,
                let next = atoms[at + linkEnd + 1].scalar, isASCIIAlphanumeric(next)
            else { break }
            dots += 1
            linkEnd += 1
        }
        return .end(linkEnd)
    }

    /// Whether the letters before the colon at `colon` spell `name`, inside
    /// the scan's reach (`floor`), and start a word.
    private static func precedes(_ atoms: [Atom], colon: Int, protocol name: String, floor: Int) -> Bool {
        let letters = Array(name.unicodeScalars)
        let first = colon - letters.count
        guard first >= floor else { return false }
        guard zip(atoms[first..<colon], letters).allSatisfy({ $0.scalar == $1 }) else { return false }
        guard first > floor, let before = atoms[first - 1].scalar else { return true }
        return !isASCIIAlphanumeric(before)
    }

    // MARK: - Helpers

    static func atoms(_ string: String) -> [Atom] {
        string.unicodeScalars.map(Atom.scalar)
    }

    static func startsWith(_ prefix: String, in source: [Atom], at index: Int) -> Bool {
        let scalars = Array(prefix.unicodeScalars)
        guard index + scalars.count <= source.count else { return false }
        return zip(source[index..<(index + scalars.count)], scalars).allSatisfy { $0.scalar == $1 }
    }

    static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIILetter(scalar) || isASCIIDigit(scalar)
    }
}
