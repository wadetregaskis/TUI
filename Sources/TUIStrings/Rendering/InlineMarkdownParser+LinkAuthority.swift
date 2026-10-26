//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser+LinkAuthority.swift
//
//  Whether a link's destination names a host and port Foundation's parse can
//  make a URL of. Where it cannot, Foundation draws the link's text and no
//  link, for every kind of link (measured, 2026-10-26).
//
//  Created by Wade Tregaskis
//  License: MIT

extension InlineMarkdownParser {
    /// Whether `destination`'s authority — what follows `//`, up to a `/`, a
    /// `?` or a `#` — is one Foundation's `URL(string:)` accepts, which is when
    /// its Markdown parse makes a link of it.
    ///
    /// Everything else in a destination is percent-encoded and linked (a `"`
    /// in a path is `%22`), and so is the user information before the last
    /// `@`. What fails is the host and the port after it, measured through
    /// `AttributedString(markdown:)` on macOS 15 for a bare URL, a `www.` one,
    /// an `<…>` autolink, an inline link and a reference:
    ///
    /// - a host holding `"`, `<`, `>`, `\`, `^`, a backtick, `{`, `|`, `}`,
    ///   `[`, `]`, a space or a control, or a `%` not followed by two hex
    ///   digits (`x.com%41` is linked, `x.com%4` is not); anything outside
    ///   ASCII is fine, being spelled through IDNA;
    /// - a port that is not all digits (`x.com:80` is linked, `x.com:80b`
    ///   and `x.com:8:9` are not).
    ///
    /// A destination with no `//` has no authority, and a value interpolated
    /// into one is not known here; both are accepted.
    static func hasLinkableAuthority(_ destination: [InlineMarkdown.Atom]) -> Bool {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(destination.count)
        for atom in destination {
            guard case .scalar(let scalar) = atom else { return true }
            scalars.append(scalar)
        }
        guard let start = authorityStart(in: scalars) else { return true }
        var end = start
        while end < scalars.count, !["/", "?", "#"].contains(scalars[end]) { end += 1 }
        var hostStart = start
        for index in start..<end where scalars[index] == "@" { hostStart = index + 1 }
        let hostPort = scalars[hostStart..<end]
        let colon = hostPort.firstIndex(of: ":")
        let host = hostPort[..<(colon ?? hostPort.endIndex)]
        if let colon, !hostPort[(colon + 1)...].allSatisfy(isASCIIDigit) { return false }
        var index = host.startIndex
        while index < host.endIndex {
            let scalar = host[index]
            if scalar == "%" {
                guard isHexDigit(host[safe: index + 1]), isHexDigit(host[safe: index + 2]) else { return false }
                index += 3
                continue
            }
            if scalar.value < 0x21 || scalar.value == 0x7F || unlinkableInHost.contains(scalar) { return false }
            index += 1
        }
        return true
    }

    /// Where the authority begins: just past the `//` after a scheme
    /// (`https://`), or after a leading `//`; `nil` where there is none.
    private static func authorityStart(in scalars: [Unicode.Scalar]) -> Int? {
        if scalars.starts(with: ["/", "/"]) { return 2 }
        guard let first = scalars.first, isASCIILetter(first) else { return nil }
        var index = 1
        while index < scalars.count,
            isASCIIAlphanumeric(scalars[index]) || ["+", "-", "."].contains(scalars[index])
        {
            index += 1
        }
        guard scalars[safe: index] == ":", scalars[safe: index + 1] == "/", scalars[safe: index + 2] == "/" else {
            return nil
        }
        return index + 3
    }

    /// The ASCII a host may not hold, beyond spaces and controls.
    private static let unlinkableInHost: Set<Unicode.Scalar> = ["\"", "<", ">", "\\", "^", "`", "{", "|", "}", "[", "]"]

    private static func isHexDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return isASCIIDigit(scalar) || ("a"..."f").contains(scalar) || ("A"..."F").contains(scalar)
    }
}

private extension Collection where Index == Int {
    /// The element at `index`, or `nil` past either end.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
