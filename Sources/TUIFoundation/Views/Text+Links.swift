//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+Links.swift
//
//  A run of a `Text` that links somewhere — an attributed string's `link`, or a
//  Markdown link in a key: drawn as a link, carrying the destination to the
//  terminal as an OSC 8 hyperlink, and writing it out where `.linkDisplay`
//  asks.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

extension Text.Run {
    /// This run's own style with what being a link adds beneath it: the accent
    /// colour unless the run states one, and the underline ``Link`` draws
    /// unless the run states whether it is underlined.
    ///
    /// Beneath the run's own attributes and above the text's, which is where
    /// SwiftUI puts a link's colour (measured on macOS 15.8): a run's own
    /// `foregroundColor` wins, and `.foregroundStyle` on the text does not
    /// reach a link — `.tint` does, through the accent. The underline is
    /// TUI's, for the reason ``Link`` gives: a link in a terminal has no
    /// pointer affordance, so the line is what marks it.
    func styleStatingLink(in environment: EnvironmentValues) -> TextStyle {
        guard link != nil else { return style }
        var stated = style
        if stated.foregroundColor == nil {
            stated.foregroundColor = Color.palette.accent
        }
        if stated.isUnderlined == nil, environment.linkUnderline {
            stated.isUnderlined = true
        }
        return stated
    }
}

extension Text {
    /// The words this text shows and the runs they are drawn in: its own, or,
    /// under ``LinkDisplay/urlInParentheses`` and ``LinkDisplay/urlOnly``, with
    /// each link's destination written after its label or in its place, as
    /// ``Link`` writes its own (decisions B85).
    ///
    /// The destination joins the link's run, so it is drawn, underlined and
    /// hyperlinked as the label is; and since the measure and the render both
    /// read it from here, the measure counts it. And as they do from ``Link``,
    /// the URL modes take the link's control away: a text's link is a focus
    /// stop only under ``LinkDisplay/popover`` (`TextLinkStops`, B85). A text
    /// that has no runs, or no link, or shows links as
    /// ``LinkDisplay/popover`` (the default), pays a nil check and an
    /// environment read only where it has runs.
    func shownWords(in environment: EnvironmentValues) -> (content: String, runs: [Run]?) {
        guard let runs, runs.contains(where: { $0.link != nil }) else { return (content, runs) }
        let display = environment.linkDisplay
        guard display != .popover else { return (content, runs) }
        let shown = runs.map { run -> Run in
            guard let link = run.link else { return run }
            let destination = link.absoluteString
            let text = display == .urlOnly ? destination : "\(run.text) (\(destination))"
            return Run(text: text, style: run.style, link: link, attributes: run.attributes)
        }
        return (shown.map(\.text).joined(), shown)
    }

    /// For each run, the OSC 8 sequence that opens its link, or `nil` when it
    /// has none; or `nil` for them ALL when no run links or none may be
    /// emitted here — which is nearly every concatenation, and so pays for no
    /// array of `nil`s.
    ///
    /// Emitted under the same three conditions as ``Link``'s: the subtree
    /// allows it (``EnvironmentValues/terminalHyperlinks``), the text is
    /// enabled — a disabled text's destination must not open on the terminal's
    /// own gesture either — and the terminal is measured to honour OSC 8.
    ///
    /// A link over more than one line becomes one link per line, each line
    /// balanced on its own (see `TerminalHyperlinkModifier`), so where the text
    /// has more than one line every link gets an id: a host that implements the
    /// parameter treats the pieces as one link.
    static func hyperlinkOpenings(
        for runs: [Run], lineCount: Int, context: RenderContext
    ) -> [String?]? {
        guard runs.contains(where: { $0.link != nil }), context.environment.terminalHyperlinks,
            context.environment.isEnabled, TerminalHyperlink.isSupported
        else { return nil }
        return runs.enumerated().map { index, run in
            guard let link = run.link else { return nil }
            let id = lineCount > 1 ? "\(context.identity.path)#\(index)" : nil
            // `nil` too for a destination too long to send: that run draws
            // as a link and carries none.
            return TerminalHyperlink(
                destination: link.absoluteString, id: id,
                localHostName: TerminalClient.localHostName
            ).opening
        }
    }

    /// `styled` inside its run's hyperlink, when it has one: a balanced pair
    /// around one fragment of one line, so nothing after it joins the link.
    nonisolated static func hyperlinked(_ styled: String, opening: String?) -> String {
        guard let opening, !styled.isEmpty else { return styled }
        return opening + styled + TerminalHyperlink.closing
    }

    /// One line of a concatenation in its runs' styles: per fragment, its
    /// link's opening, its run's SGR introducer, the text, a reset, and the
    /// link's closing.
    ///
    /// Byte for byte what `hyperlinked(ANSIRenderer.render(text, with:),
    /// opening:)` per fragment, `joined()`, spells — a fragment is never empty
    /// (the attribution emits none), so `hyperlinked`'s empty guard never
    /// applies — but written into ONE string, reserved to its exact size first.
    /// The per-fragment spelling built an interpolated string per fragment,
    /// an array of them per line and the join, and re-derived the run's
    /// introducer for every fragment; a `String` grown by doubling instead of
    /// reserved would give back most of those allocations in reallocations
    /// (a two-run Markdown line is ~70 bytes).
    ///
    /// - Parameters:
    ///   - line: The line's fragments, each tagged with its run.
    ///   - sequences: Per run, its SGR introducer, or `nil` for an unstyled run
    ///     (drawn bare, as `render` draws it).
    ///   - openings: Per run, its link's opening, as
    ///     ``hyperlinkOpenings(for:lineCount:context:)`` answers.
    static func styledLine(
        _ line: [(text: String, run: Int)], sequences: [String?], openings: [String?]?
    ) -> String {
        let resetBytes = ANSIRenderer.reset.utf8.count
        let closingBytes = TerminalHyperlink.closing.utf8.count
        var bytes = 0
        for (text, run) in line {
            bytes += text.utf8.count
            if let sequence = sequences[run] { bytes += sequence.utf8.count + resetBytes }
            if let opening = openings.flatMap({ $0[run] }) { bytes += opening.utf8.count + closingBytes }
        }
        var styled = ""
        styled.reserveCapacity(bytes)
        for (text, run) in line {
            let opening = openings.flatMap { $0[run] }
            if let opening { styled += opening }
            if let sequence = sequences[run] {
                styled += sequence
                styled += text
                styled += ANSIRenderer.reset
            } else {
                styled += text
            }
            if opening != nil { styled += TerminalHyperlink.closing }
        }
        return styled
    }
}
