//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineStyleSupport.swift
//
//  Which underline shapes and line colours a terminal draws as asked
//  (W11b), so that text asks only for those and falls back to a plain line
//  where it would otherwise be misdrawn.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Which of SGR's line styles a terminal draws as asked: the underline's
/// shapes (`4:2` to `4:5`) and colour (SGR 58), and whether that colour
/// reaches a strikethrough.
///
/// Each is all or nothing for a terminal, and what a terminal does not draw
/// it must not be sent, because the failure is not a plain line but
/// something else entirely (measured by the owner, 2026-10-18, with
/// `line_style_card.py`): Apple Terminal paints `4:2` to `4:5` as the
/// backgrounds 42 to 45, and Warp draws no curly, dotted or dashed line.
/// What text asks for is reduced to what the terminal draws before it is
/// spelled: a shape it lacks becomes the plain line of SGR 4, and a colour it
/// lacks the text's own. See *Terminal compatibility survey*, "Underline
/// shapes and colours".
package struct LineStyleSupport: Equatable, Sendable {
    /// Whether SGR `4:2` draws a double underline.
    package var doubleUnderline: Bool

    /// Whether SGR `4:3`, `4:4` and `4:5` draw curly, dotted and dashed
    /// underlines.
    package var patternedUnderlines: Bool

    /// Whether SGR 58 colours an underline.
    package var underlineColour: Bool

    /// Whether SGR 58 colours a strikethrough as well — iTerm2's reading of
    /// it, and nobody else's measured. No SGR states a strikethrough's colour.
    package var strikethroughColour: Bool

    package init(doubleUnderline: Bool, patternedUnderlines: Bool, underlineColour: Bool, strikethroughColour: Bool) {
        self.doubleUnderline = doubleUnderline
        self.patternedUnderlines = patternedUnderlines
        self.underlineColour = underlineColour
        self.strikethroughColour = strikethroughColour
    }

    /// Every underline shape and colour; a strikethrough in the text's own
    /// colour. Ghostty, and what a render says nothing about (headless, tests).
    package static let underlines = Self(
        doubleUnderline: true, patternedUnderlines: true, underlineColour: true, strikethroughColour: false)

    /// Everything, the strikethrough's colour too: iTerm2.
    package static let all = Self(
        doubleUnderline: true, patternedUnderlines: true, underlineColour: true, strikethroughColour: true)

    /// The plain single underline and nothing else.
    package static let plain = Self(
        doubleUnderline: false, patternedUnderlines: false, underlineColour: false, strikethroughColour: false)
}

extension TerminalHost {
    /// The line styles this process's terminal draws as asked.
    ///
    /// Measured hosts as the owner read them (2026-10-18): iTerm2 draws every
    /// one, its strikethrough coloured by SGR 58 as well; Ghostty every
    /// underline, its strikethrough in the text's colour; Warp a double line
    /// and no other shape or colour; Apple Terminal only the plain line.
    ///
    /// Under tmux, every underline: tmux reads the shapes and the colour
    /// itself and re-spells them for each client from that client's own
    /// capabilities (`Smulx`, `Setulc`), falling back to a plain line, so it
    /// never passes on what a client cannot draw.
    ///
    /// A terminal not measured gets the plain line. Unlike a glyph drawn a
    /// little short, a shape it does not know can come out as a background or
    /// a blink (Apple Terminal's), and the owner would rather have a plain
    /// line than that.
    package static var lineStyles: LineStyleSupport {
        if isTmux { return .underlines }
        if isITerm2 { return .all }
        if isGhostty { return .underlines }
        if isWarp {
            return LineStyleSupport(
                doubleUnderline: true, patternedUnderlines: false, underlineColour: false, strikethroughColour: false)
        }
        return .plain
    }
}
