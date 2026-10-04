//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Markdown.swift
//
//  The Markdown SwiftUI applies to a `Text` made from a key, as a `Text`'s
//  runs. The parse itself is `InlineMarkdown`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Text {
    /// A key's text with its Markdown applied: the plain text, and the runs
    /// that style it — `nil` when one plain run is all there is.
    ///
    /// The template is parsed BEFORE the arguments go in, each placeholder one
    /// opaque slot, because that is SwiftUI's order (measured on macOS 15.8):
    /// `Text("**\(name)**")` is bold whatever `name` holds, a `*` inside a
    /// value is drawn rather than parsed, and a URL that arrives as a value is
    /// not autolinked. A value takes the style of where its placeholder
    /// stands, so `"**\(count)** new"` makes the count bold.
    ///
    /// A run holding a live argument — `\(date, style: .relative)` — is a live
    /// run, read again at each frame as any live text is, and keeps its style.
    static func markdownRuns(
        in template: String, key: LocalizedStringKey
    ) -> (content: String, runs: [Run]?) {
        var atoms: [InlineMarkdown.Atom] = []
        var placeholders: [LocalizedStringKey.Placeholder] = []
        if key.arguments.isEmpty {
            // A key with no interpolations has no placeholders to read: its
            // `%` is a percent, as everywhere else.
            atoms = template.unicodeScalars.map(InlineMarkdown.Atom.scalar)
        } else {
            // A UTF-8 byte count bounds the scalar count, so this is the one
            // allocation; and each character's scalars go straight in, where a
            // `map` per character allocated an array for every one.
            atoms.reserveCapacity(template.utf8.count)
            LocalizedStringKey.walk(
                template,
                text: { character in
                    for scalar in character.unicodeScalars { atoms.append(.scalar(scalar)) }
                },
                placeholder: { placeholder in
                    atoms.append(.argument(placeholders.count))
                    placeholders.append(placeholder)
                })
        }
        var runs: [Run] = []
        for span in InlineMarkdown.parse(atoms) {
            let pieces = MarkdownRunSource.pieces(of: span.atoms, placeholders: placeholders)
            let source = MarkdownRunSource(pieces: pieces, key: key)
            let link = span.link.flatMap { destination in
                linkURL(MarkdownRunSource(pieces: MarkdownRunSource.pieces(of: destination, placeholders: placeholders), key: key).text)
            }
            let run = Run(
                text: source.text, style: Self.style(of: span.traits),
                live: source.isLive ? LiveTextBox(source) : nil, link: link)
            if let last = runs.last, last.live == nil, run.live == nil, last.style == run.style,
                last.link == run.link
            {
                runs[runs.count - 1] = Run(text: last.text + run.text, style: run.style, link: run.link)
            } else {
                runs.append(run)
            }
        }
        let content = runs.map(\.text).joined()
        guard runs.count > 1 || runs.first.map({ $0.style != TextStyle() || $0.link != nil || $0.live != nil }) == true
        else { return (content, nil) }
        return (content, runs)
    }

    /// What a span's traits draw as. Code is monospaced, which every cell
    /// already is, so it draws as the text around it.
    private static func style(of traits: InlineMarkdown.Traits) -> TextStyle {
        var style = TextStyle()
        if traits.contains(.strong) { style.isBold = true }
        if traits.contains(.emphasized) { style.isItalic = true }
        if traits.contains(.strikethrough) { style.isStrikethrough = true }
        return style
    }

    /// The URL a Markdown link's destination names, or `nil` for none.
    ///
    /// `URL(string:)`, as Foundation's parse makes a link (measured: `<a b>`
    /// links to `a%20b`, and an empty destination is no link at all). Where
    /// that refuses a destination — swift-foundation is stricter about some
    /// characters than Darwin's — the destination is percent-encoded first, so
    /// the link survives on both.
    nonisolated static func linkURL(_ destination: String) -> URL? {
        guard !destination.isEmpty else { return nil }
        if let url = URL(string: destination) { return url }
        return destination.addingPercentEncoding(withAllowedCharacters: Self.linkCharacters)
            .flatMap(URL.init(string:))
    }

    /// Everything a URL may hold as written: the unreserved characters, the
    /// reserved ones (which are its syntax) and `%`.
    nonisolated private static let linkCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
}

// MARK: - A run of a key's Markdown

/// The words of one Markdown run of a key: its text, and the placeholders the
/// key's arguments fill — read with the arguments as they were when the key
/// was built, or, for a live run, at the frame being drawn.
struct MarkdownRunSource: LiveTextSource, Equatable {
    enum Piece: Equatable, Sendable {
        case text(String)
        case argument(LocalizedStringKey.Placeholder)
    }

    let pieces: [Piece]
    let key: LocalizedStringKey

    /// `atoms` as pieces, each argument slot its placeholder.
    static func pieces(
        of atoms: [InlineMarkdown.Atom], placeholders: [LocalizedStringKey.Placeholder]
    ) -> [Piece] {
        var pieces: [Piece] = []
        var text = String.UnicodeScalarView()
        for atom in atoms {
            switch atom {
            case .scalar(let scalar):
                text.append(scalar)
            case .argument(let slot):
                if !text.isEmpty {
                    pieces.append(.text(String(text)))
                    text = String.UnicodeScalarView()
                }
                pieces.append(.argument(placeholders[slot]))
            }
        }
        if !text.isEmpty { pieces.append(.text(String(text))) }
        return pieces
    }

    /// Whether any placeholder here takes an argument that reads the clock.
    var isLive: Bool {
        pieces.contains {
            if case .argument(let placeholder) = $0 { key.liveArguments[placeholder.argument] != nil } else { false }
        }
    }

    /// The words as the key's arguments read when it was built.
    var text: String {
        words { key.arguments.indices.contains($0) ? key.arguments[$0] : nil }
    }

    func text(at date: Date, in environment: LiveTextEnvironment) -> String {
        words { argument in
            if let live = key.liveArguments[argument] { return live.source.text(at: date, in: environment) }
            return key.arguments.indices.contains(argument) ? key.arguments[argument] : nil
        }
    }

    func nextChange(after date: Date, in environment: LiveTextEnvironment) -> Date? {
        pieces.compactMap { piece -> Date? in
            guard case .argument(let placeholder) = piece, let live = key.liveArguments[placeholder.argument]
            else { return nil }
            return live.source.nextChange(after: date, in: environment)
        }.min()
    }

    /// The pieces joined, each placeholder filled with `value(argument)` — or
    /// with nothing, for an argument the key does not have, as the plain
    /// substitution does.
    private func words(_ value: (Int) -> String?) -> String {
        var result = ""
        for piece in pieces {
            switch piece {
            case .text(let text): result += text
            case .argument(let placeholder):
                if let filled = value(placeholder.argument) { result += placeholder.filled(with: filled) }
            }
        }
        return result
    }
}
