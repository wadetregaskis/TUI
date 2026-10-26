//  🖥️ TUI — A Terminal UI framework for Swift
//  LegibilityWeight+Tiers.swift
//
//  The one rule `\.legibilityWeight` asks of every piece of text TUI draws:
//  under `.bold`, a tier heavier. One helper, so `Text` and every control that
//  draws its own text step the same way.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension Optional where Wrapped == LegibilityWeight {
    /// `bold` and `faint` as text drawn under this legibility weight has them:
    /// a tier heavier under ``LegibilityWeight/bold`` — faint draws plain,
    /// plain draws bold, bold stays bold — and as they are otherwise.
    ///
    /// SwiftUI's rule, measured on macOS (decisions B2): light → regular,
    /// regular → bold, bold stays bold. A terminal draws three weights, so the
    /// step is one of those. Pass only a WEIGHT here: a faint that means
    /// something else — a disabled control, ``View/dimmed()``, a stale figure —
    /// is not one, and a site applies it after.
    ///
    /// - Parameters:
    ///   - bold: Whether the text would be drawn bold.
    ///   - faint: Whether the text would be drawn faint.
    /// - Returns: The two as the text is to be drawn.
    @inlinable
    package func applied(bold: Bool, faint: Bool) -> (bold: Bool, faint: Bool) {
        guard self == .bold, !bold else { return (bold, faint) }
        return faint ? (false, false) : (true, false)
    }

    /// Whether text that is otherwise plain is drawn bold under this weight:
    /// ``applied(bold:faint:)`` for the commonest case, the one almost every
    /// control's own text is in.
    @inlinable
    package var drawsPlainBold: Bool { applied(bold: false, faint: false).bold }
}

extension AnimatedCellRun {
    /// This run with every frame drawn bold (``ANSIRenderer/applyPersistentBold(_:)``):
    /// the animated cells of text a legibility weight draws heavier — a field's
    /// caret, a date picker's breathing component — whose frames the run loop
    /// paints by itself, so the line's own bold never reaches them.
    package func drawnBold() -> AnimatedCellRun {
        AnimatedCellRun(
            offsetX: offsetX, offsetY: offsetY, width: width, frames: frames.map(ANSIRenderer.applyPersistentBold),
            frameTicks: frameTicks, clock: clock, alpha: alpha)
    }
}
