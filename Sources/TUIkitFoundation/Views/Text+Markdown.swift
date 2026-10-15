//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Markdown.swift
//
//  The Markdown SwiftUI applies to a `Text` made from a key, as a `Text`'s
//  runs. The parse itself is `InlineMarkdown`; `MarkdownTemplate` keeps it
//  per template.
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
    ///
    /// That order is also why the parse is kept: it never sees a value, so
    /// one parse of a template serves every `Text` built from it, and a
    /// literal rebuilt each frame only puts its values in. See
    /// ``MarkdownTemplate``.
    static func markdownRuns(
        in template: String, key: LocalizedStringKey
    ) -> (content: String, runs: [Run]?) {
        MarkdownTemplate.parsed(template, for: key).filled(by: key)
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

extension LocalizedStringKey {
    /// This key drawn as a `Text` would draw it, with its plain words, when its
    /// Markdown styles any of it; `nil` for a key Markdown leaves alone, which
    /// is most of them and costs a byte scan.
    ///
    /// For a control that keeps its title as a `String` (a `Button`, a
    /// `ColorPicker`): SwiftUI parses a control's title key as it parses a
    /// `Text`'s (measured: `Button("**Save**") {}` draws the bold), so such a
    /// control draws a styled key as this `Text`, and keeps the plain words as
    /// the title for whatever reads it as text.
    @MainActor package var markdownTitle: (text: Text, plain: String)? {
        let template = LocalizationService.shared.string(
            for: key, swiftUIKey: swiftUIKey, tableName: nil, bundle: nil)
        guard InlineMarkdown.mightContainMarkup(template) else { return nil }
        let parsed = Text.markdownRuns(in: template, key: self)
        guard let runs = parsed.runs else { return nil }
        var text = Text(verbatim: parsed.content)
        text.runs = runs
        return (text, parsed.content)
    }
}

// MARK: - A template's parse, kept

/// A key template's Markdown as far as it goes without the key's values: the
/// spans, and each one's words, style and link.
///
/// The parse reads the template and one thing about the key — whether it has
/// values at all, since without them a `%` is a percent and not a placeholder.
/// It never reads a value: they go in after it (see
/// ``Text/markdownRuns(in:key:)``). So one parse serves every `Text` built
/// from the template, and ``parsed(_:for:)`` keeps it, filed under those two
/// inputs. The template is the RESOLVED one, not the key, so a language
/// switched at runtime is another template rather than a stale entry.
///
/// What is left for each `Text` is what its values decide: the words of a
/// span a placeholder stands in, whether that span is live, and a link whose
/// destination a placeholder completes — and so which neighbouring spans
/// merge into one run. Where no value can be live and no link waits on one,
/// that merge is the template's too, and is kept as well (`plan`).
@MainActor
struct MarkdownTemplate {
    /// One span of the parse, as far as it goes without values.
    struct Span {
        /// The words, each placeholder a piece of its own.
        let pieces: [MarkdownRunSource.Piece]
        /// The words themselves, when no placeholder stands in them — the
        /// same for every key.
        let text: String?
        /// What the span's traits draw as.
        let style: TextStyle
        /// Where the span links, when no placeholder stands in its
        /// destination.
        let link: URL?
        /// The destination's pieces, when a placeholder does: that link is
        /// each key's values' to finish.
        let linkPieces: [MarkdownRunSource.Piece]?
    }

    /// One run of a key with no live values, as far as it goes without them:
    /// neighbouring spans merged, their pieces laid end to end.
    struct PlannedRun {
        /// The merged spans' pieces, in order.
        let pieces: [MarkdownRunSource.Piece]
        /// The style they share.
        let style: TextStyle
        /// The link they share.
        let link: URL?
    }

    let spans: [Span]

    /// The text and runs, when no span holds a placeholder: then they are
    /// every key's alike, so they are made once, with the parse.
    private var finished: (content: String, runs: [Text.Run]?)?

    /// The runs, merged, for a key with no live values — when no placeholder
    /// stands in a link's destination; `nil` otherwise, and when `finished`
    /// answers.
    ///
    /// For such a key everything the merge in ``filledBySpans(by:)`` decides
    /// by is the template's: no span is live (liveness is a key's live
    /// VALUES), and every link is the parse's. So it is decided once, here,
    /// and a build only fills each merged run's words. Spans that merge
    /// become ONE run whose words are their pieces end to end — the same
    /// text, since a span's words are only its pieces joined.
    private var plan: [PlannedRun]?

    /// Whether `plan` makes no runs worth keeping: at most one, unstyled
    /// and unlinked — the guard at the end of ``filledBySpans(by:)``, with no
    /// run live.
    private var planIsPlain = false

    /// Whether ``filled(by:)`` answers a key with no live values from
    /// `plan`, for the tests.
    var fillsFromPlan: Bool { plan != nil }

    /// Parses `template` as `key` reads it.
    init(parsing template: String, for key: LocalizedStringKey) {
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
        spans = InlineMarkdown.parse(atoms).map { span in
            // Read through `key` as a `Text` would, which for words with no
            // placeholder in them reads nothing of the key at all.
            let words = MarkdownRunSource(
                pieces: MarkdownRunSource.pieces(of: span.atoms, placeholders: placeholders), key: key)
            let destination = span.link.map { link in
                MarkdownRunSource(pieces: MarkdownRunSource.pieces(of: link, placeholders: placeholders), key: key)
            }
            let linkIsFilled = destination?.hasPlaceholders == true
            return Span(
                pieces: words.pieces,
                text: words.hasPlaceholders ? nil : words.text,
                style: Self.style(of: span.traits),
                link: linkIsFilled ? nil : destination.flatMap { Text.linkURL($0.text) },
                linkPieces: linkIsFilled ? destination?.pieces : nil)
        }
        if spans.allSatisfy({ $0.text != nil && $0.linkPieces == nil }) {
            finished = filledBySpans(by: key)
        } else if spans.allSatisfy({ $0.linkPieces == nil }) {
            // `filledBySpans`' merge, with no run live: neighbours of one style
            // and link merge, and the merged run takes the later span's (equal)
            // style and link, as it does there.
            var planned: [PlannedRun] = []
            planned.reserveCapacity(spans.count)
            for span in spans {
                if let last = planned.last, last.style == span.style, last.link == span.link {
                    planned[planned.count - 1] = PlannedRun(
                        pieces: last.pieces + span.pieces, style: span.style, link: span.link)
                } else {
                    planned.append(PlannedRun(pieces: span.pieces, style: span.style, link: span.link))
                }
            }
            plan = planned
            planIsPlain = planned.count <= 1 && planned.allSatisfy { $0.style == TextStyle() && $0.link == nil }
        }
    }

    /// The text and runs `key`'s values make of this template.
    func filled(by key: LocalizedStringKey) -> (content: String, runs: [Text.Run]?) {
        if let finished { return finished }
        if let plan, key.liveArguments.isEmpty {
            // No value is live, so the spans merge as they did at parse time:
            // only the words are this key's. Each run's fields are read in
            // place, by index — a `for planned in plan` copies the whole
            // element out, pieces, style and the resilient `URL?` (through
            // its value witnesses) with it, which is the cost this saves.
            if planIsPlain {
                return (plan.isEmpty ? "" : MarkdownRunSource(pieces: plan[0].pieces, key: key).text, nil)
            }
            var runs: [Text.Run] = []
            runs.reserveCapacity(plan.count)
            var length = 0
            for index in plan.indices {
                let text = MarkdownRunSource(pieces: plan[index].pieces, key: key).text
                length += text.utf8.count
                runs.append(Text.Run(text: text, style: plan[index].style, link: plan[index].link))
            }
            // The runs' words joined, into a string reserved to their length.
            var content = ""
            content.reserveCapacity(length)
            for index in runs.indices { content += runs[index].text }
            return (content, runs)
        }
        return filledBySpans(by: key)
    }

    /// ``filled(by:)`` span by span: any key, live values and links a value
    /// completes included — and the reading the plan must agree with.
    func filledBySpans(by key: LocalizedStringKey) -> (content: String, runs: [Text.Run]?) {
        var content = ""
        var runs: [Text.Run] = []
        runs.reserveCapacity(spans.count)
        for span in spans {
            let link: URL? =
                if let pieces = span.linkPieces {
                    Text.linkURL(MarkdownRunSource(pieces: pieces, key: key).text)
                } else {
                    span.link
                }
            let run: Text.Run
            if let text = span.text {
                run = Text.Run(text: text, style: span.style, link: link)
            } else {
                let source = MarkdownRunSource(pieces: span.pieces, key: key)
                run = Text.Run(
                    text: source.text, style: span.style, live: source.isLive ? LiveTextBox(source) : nil, link: link)
            }
            // Every span's words, in order: what the runs below join to,
            // merged or not.
            content += run.text
            if let last = runs.last, last.live == nil, run.live == nil, last.style == run.style,
                last.link == run.link
            {
                runs[runs.count - 1] = Text.Run(text: last.text + run.text, style: run.style, link: run.link)
            } else {
                runs.append(run)
            }
        }
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

    // MARK: Keeping

    /// What a kept parse is filed under: everything the parse reads.
    private struct CacheKey: Hashable {
        let template: String
        let hasArguments: Bool
    }

    /// The most parses kept: a backstop against an app that makes keys at
    /// runtime, not a working-set estimate — an app's Markdown templates are
    /// a handful. A flat cap, emptied when full, as `TextWrapping`'s memos
    /// are: an entry is small, and tracking recency would cost more than the
    /// occasional re-parse.
    static let cacheLimit = 1024

    private static var cache: [CacheKey: Self] = [:]

    /// How many parses are kept, for the tests.
    static var keptCount: Int { cache.count }

    /// The parse of `template` as `key` reads it: the kept one, or one made
    /// now and kept.
    static func parsed(_ template: String, for key: LocalizedStringKey) -> Self {
        let cacheKey = CacheKey(template: template, hasArguments: !key.arguments.isEmpty)
        if let kept = cache[cacheKey] { return kept }
        let parsed = Self(parsing: template, for: key)
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[cacheKey] = parsed
        return parsed
    }
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

    /// Whether any piece is a placeholder: without one, the words are the
    /// same whatever the key's values.
    var hasPlaceholders: Bool {
        pieces.contains {
            if case .argument = $0 { true } else { false }
        }
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

    /// Each live argument's ladder, filled in rung by rung.
    func sizeVariants(at date: Date, in environment: LiveTextEnvironment) -> [String] {
        let ladders = Dictionary(
            uniqueKeysWithValues: key.liveArguments.map { ($0.key, $0.value.source.sizeVariants(at: date, in: environment)) })
        let count = ladders.values.map(\.count).max() ?? 1
        return (0..<count).map { rung in
            words { argument in
                if let ladder = ladders[argument], !ladder.isEmpty { return ladder[min(rung, ladder.count - 1)] }
                return key.arguments.indices.contains(argument) ? key.arguments[argument] : nil
            }
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
