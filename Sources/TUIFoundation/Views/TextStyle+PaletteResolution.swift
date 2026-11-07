//  🖥️ TUI — A Terminal UI framework for Swift
//  TextStyle+PaletteResolution.swift
//
//  A text style's colours and lines resolved for where they are drawn.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

extension TextStyle {
    /// Resolves any semantic colors in this style against the given palette.
    ///
    /// Non-semantic colors are left unchanged. Call this before passing
    /// the style to `ANSIRenderer`.
    ///
    /// - Parameter palette: The palette to resolve semantic colors against.
    /// - Returns: A copy with all colors resolved to concrete values.
    package func resolved(with palette: any Palette) -> TextStyle {
        var copy = self
        copy.foregroundColor = foregroundColor?.resolve(with: palette)
        copy.backgroundColor = backgroundColor?.resolve(with: palette)
        copy.underline = underline.map { $0?.resolved(with: palette) }
        copy.strikethrough = strikethrough.map { $0?.resolved(with: palette) }
        return copy
    }

    /// This style with its lines reduced to what a terminal that draws
    /// `support` draws: each shape it lacks a single line, each colour it lacks
    /// the text's own (``Text/LineStyle/fittingUnderline(to:)``).
    ///
    /// SGR 58 is ONE colour, the underline's, which iTerm2 lends the
    /// strikethrough too; so where both lines state colours, the underline's
    /// is the one drawn.
    package func fittingLines(to support: LineStyleSupport) -> TextStyle {
        guard underline != nil || strikethrough != nil else { return self }
        var copy = self
        copy.underline = underline.map { $0?.fittingUnderline(to: support) }
        copy.strikethrough = strikethrough.map { $0?.fittingStrikethrough(to: support) }
        if case .some(.some(let line)) = copy.underline, line.color != nil,
            case .some(.some(let struck)) = copy.strikethrough, struck.color != nil
        {
            copy.strikethrough = .some(Text.LineStyle(pattern: .solid))
        }
        return copy
    }
}
