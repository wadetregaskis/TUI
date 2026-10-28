//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+Interpolation.swift
//
//  An interpolated `Text` keeps its styling: the key carries its runs beside
//  its words, and a `Text` made from the key splices them in where its
//  placeholder stands.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - A styled argument

/// An interpolated `Text`'s runs, kept on its key beside its words
/// (``LocalizedStringKey/styledArguments``): each run with the text's own
/// style folded in, so the runs carry everything the fragment said about
/// itself.
struct StyledArgument: Hashable, Sendable {
    let runs: [Text.Run]

    /// `text`'s runs, or `nil` for a text that says nothing about its looks
    /// — no style, no styled or linked run — whose words are all a key needs.
    init?(_ text: Text) {
        let runs = text.runs?.map { $0.rebased(on: text.style) } ?? [Text.Run(text: text.content, style: text.style)]
        guard runs.contains(where: { $0.style != TextStyle() || $0.link != nil || $0.attributes != nil }) else {
            return nil
        }
        self.runs = runs
    }

    /// Runs that already say something about their looks: an attributed
    /// string's (`Text.styledRuns(of:)`), interpolated with no `Text` around
    /// them, whose own style is the plain one they would be rebased on.
    init(runs: [Text.Run]) {
        self.runs = runs
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.runs == rhs.runs }

    /// Nothing: the words are hashed in the key's `arguments`, and two keys
    /// that differ only in a fragment's looks still compare unequal. As
    /// `LiveTextBox` hashes.
    func hash(into hasher: inout Hasher) {}
}

// MARK: - Splicing

extension MarkdownTemplate {
    /// ``filled(by:)`` for a key with styled arguments: the spans' words, with
    /// each styled argument's runs spliced in where its placeholder stands.
    ///
    /// A spliced run keeps its own attributes and takes what it leaves unset
    /// from the span around it (`TextStyle.merged(over:)`), and its own link
    /// over the span's — SwiftUI's order (measured 2026-10-18 on macOS 15: an
    /// italic `Text` inside `**…**` draws bold and italic, a `.bold(false)`
    /// one plain). Neighbouring runs of one style and link merge, as in
    /// ``filledBySpans(by:)``; a live run stays one of its own.
    func filledSplicing(by key: LocalizedStringKey) -> (content: String, runs: [Text.Run]?) {
        var runs: [Text.Run] = []
        func append(_ run: Text.Run) {
            guard !run.text.isEmpty || run.live != nil else { return }
            if let last = runs.last, last.live == nil, run.live == nil, last.style == run.style,
                last.link == run.link, last.attributes == run.attributes
            {
                runs[runs.count - 1] = Text.Run(
                    text: last.text + run.text, style: run.style, link: run.link, attributes: run.attributes)
            } else {
                runs.append(run)
            }
        }
        for span in spans {
            let link: URL? =
                if let pieces = span.linkPieces {
                    Text.linkURL(MarkdownRunSource(pieces: pieces, key: key).text)
                } else {
                    span.link
                }
            // The span's words between styled arguments, a run of the span's
            // own style each, live where a live argument is among them.
            var plain: [MarkdownRunSource.Piece] = []
            func flush() {
                guard !plain.isEmpty else { return }
                let source = MarkdownRunSource(pieces: plain, key: key)
                append(
                    Text.Run(
                        text: source.text, style: span.style, live: source.isLive ? LiveTextBox(source) : nil,
                        link: link))
                plain.removeAll()
            }
            for piece in span.pieces {
                guard case .argument(let placeholder) = piece, let styled = key.styledArguments[placeholder.argument]
                else {
                    plain.append(piece)
                    continue
                }
                flush()
                for run in styled.runs {
                    append(
                        Text.Run(
                            text: run.text, style: run.style.merged(over: span.style), live: run.live,
                            link: run.link ?? link, attributes: run.attributes))
                }
            }
            flush()
        }
        var content = ""
        for run in runs { content += run.text }
        guard
            runs.count > 1
                || runs.first.map({
                    $0.style != TextStyle() || $0.link != nil || $0.live != nil || $0.attributes != nil
                }) == true
        else { return (content, nil) }
        return (content, runs)
    }
}
