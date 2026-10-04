//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Links.swift
//
//  A run of a `Text` that links somewhere — an attributed string's `link`, or a
//  Markdown link in a key: drawn as a link, and carrying the destination to the
//  terminal as an OSC 8 hyperlink.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

extension Text.Run {
    /// This run's own style with what being a link adds beneath it: the accent
    /// colour unless the run states one, and the underline ``Link`` draws
    /// unless the run states whether it is underlined.
    ///
    /// Beneath the run's own attributes and above the text's, which is where
    /// SwiftUI puts a link's colour (measured on macOS 15.8): a run's own
    /// `foregroundColor` wins, and `.foregroundStyle` on the text does not
    /// reach a link — `.tint` does, through the accent. The underline is
    /// TUIkit's, for the reason ``Link`` gives: a link in a terminal has no
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
    /// For each run, the OSC 8 sequence that opens its link, or `nil` when it
    /// has none or none may be emitted here.
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
    ) -> [String?] {
        guard runs.contains(where: { $0.link != nil }), context.environment.terminalHyperlinks,
            context.environment.isEnabled, TerminalHyperlink.isSupported
        else { return Array(repeating: nil, count: runs.count) }
        return runs.enumerated().map { index, run in
            guard let link = run.link else { return nil }
            let id = lineCount > 1 ? "\(context.identity.path)#\(index)" : nil
            return TerminalHyperlink(destination: link.absoluteString, id: id).opening
        }
    }

    /// `styled` inside its run's hyperlink, when it has one: a balanced pair
    /// around one fragment of one line, so nothing after it joins the link.
    nonisolated static func hyperlinked(_ styled: String, opening: String?) -> String {
        guard let opening, !styled.isEmpty else { return styled }
        return opening + styled + TerminalHyperlink.closing
    }
}
