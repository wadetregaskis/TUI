//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+NoColorStates.swift
//
//  What a control says with an attribute where it can't say it with a colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// A control's states are mostly told apart by colour: an accent that breathes for the
/// focus, a recessive grey for disabled. At ``ColorDepth/noColor`` neither is drawn, so
/// a focused toggle and a disabled button looked like any other. This is what they
/// say instead, in the attributes such a terminal still draws, and in one place, so
/// that every control says it alike: the focus in reverse video, as a list's cursor
/// row, a menu's bar and a segmented picker already do, and disabled in the faint
/// `SelectionDisabledModifier` already uses for a row that can't be selected —
/// italic too where the host doesn't show faint (``TerminalClient/drawsFaint``).
///
/// At any other depth the colours keep the job, unless the person asked for cues that
/// don't rest on colour (``EnvironmentValues/accessibilityDifferentiateWithoutColor``):
/// then these are drawn over the colours too (``RenderContext/statesWithoutColor``).
extension FrameBuffer {
    /// This buffer drawn faint, if `isDisabled`, where a control says its state without
    /// colour (``RenderContext/statesWithoutColor``): italic too where faint doesn't
    /// show (``ANSIRenderer/applyPersistentDisabled(_:)``).
    @MainActor
    package func fadedWithoutColor(if isDisabled: Bool, context: RenderContext) -> FrameBuffer {
        guard isDisabled, context.statesWithoutColor else { return self }
        return drawnDisabled()
    }

    /// This buffer drawn disabled, if `isDisabled`, at every depth: for a control with
    /// no ink of its own to grey, as a `List` or a `Table` is, whose rows are the app's
    /// views. Its faint was kept for where states are said without colour, so at any
    /// colour depth a disabled one drew exactly as an enabled one without the focus.
    @MainActor
    package func drawnDisabled(if isDisabled: Bool) -> FrameBuffer {
        isDisabled ? drawnDisabled() : self
    }

    /// This buffer in the attributes that say "disabled", at any depth: faint, and
    /// italic where the host doesn't show faint. What a disabled control draws at
    /// no colour, and a row that can't be selected at every depth.
    @MainActor
    package func drawnDisabled() -> FrameBuffer {
        var faded = self
        faded.lines = lines.map(ANSIRenderer.applyPersistentDisabled)
        // Under the runs too, so that a replayed tick draws what the render did.
        faded.paintRunGrounds { _, ground in ANSIRenderer.applyPersistentDisabled(ground) }
        return faded
    }

    /// This whole buffer saying `state` without colour (``RenderContext/statesWithoutColor``),
    /// for a control with no part of it that means anything by being lit.
    @MainActor
    package func statingWithoutColor(focused: Bool, disabled: Bool, context: RenderContext) -> FrameBuffer {
        reversedWithoutColor(if: focused && !disabled, context: context)
            .fadedWithoutColor(if: disabled, context: context)
    }

    /// This buffer with `columns` of `rows` in reverse video, if `isFocused`, where a
    /// control says its state without colour (``RenderContext/statesWithoutColor``).
    ///
    /// At no colour the 7 alone; over colours, the palette's own pair restated with it
    /// after every reset, so the reversal exchanges the palette's colours rather than
    /// the terminal's (``ANSIRenderer/applyPersistentReverse(_:ink:field:bold:padding:)``).
    ///
    /// A column range rather than the whole buffer because a control's indicator can
    /// mean something by which part of it is lit, as a checkbox's mark and a slider's
    /// track do, and reversing it would say the opposite.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the control shows the focus.
    ///   - rows: The rows to reverse, or all of them.
    ///   - columns: The columns to reverse, or all of them.
    ///   - context: Where the control is drawn.
    package func reversedWithoutColor(
        if isFocused: Bool, rows: Range<Int>? = nil, columns: Range<Int>? = nil, context: RenderContext
    ) -> FrameBuffer {
        guard isFocused, context.statesWithoutColor else { return self }
        return reversed(rows: rows, columns: columns, context: context)
    }

    /// This buffer with `columns` of `rows` in reverse video, if `isFocused`, where the
    /// focus can be told neither by colour nor by its breath: wherever
    /// ``reversedWithoutColor(if:rows:columns:context:)`` reverses, and wherever the
    /// focus holds still (``RenderContext/focusHoldsStill``).
    ///
    /// For a control whose focus is its breath alone, and whose resting look is the
    /// breath's bright end: a checked checkbox's mark, a switch that is on, a link's
    /// label, a radio group's chosen option. A still focus sits at that end, so the
    /// focused control and the resting one were the same cells, and nothing said where
    /// the keys would go. A control whose still focus is a colour of its own, as a
    /// button's caps and a slider's arrows are, says it with that colour and keeps
    /// ``reversedWithoutColor(if:rows:columns:context:)``.
    package func reversedWithoutBreath(
        if isFocused: Bool, rows: Range<Int>? = nil, columns: Range<Int>? = nil, context: RenderContext
    ) -> FrameBuffer {
        guard isFocused, context.statesWithoutColor || context.focusHoldsStill else { return self }
        return reversed(rows: rows, columns: columns, context: context)
    }

    /// `columns` of `rows` in reverse video over the palette's pair: the reversal both
    /// of those draw.
    private func reversed(rows: Range<Int>?, columns: Range<Int>?, context: RenderContext) -> FrameBuffer {
        // At no colour the two colours spell nothing, and only the 7 is left.
        let palette = context.environment.palette
        let colored = ColorDepth.current != .noColor
        let ink: Color = colored ? palette.foreground : .default
        let field: Color = colored ? palette.background : .default
        func reversed(_ text: String) -> String {
            ANSIRenderer.applyPersistentReverse(text, ink: ink, field: field)
        }
        let rows = rows ?? 0..<lines.count
        var result = self
        for row in rows where lines.indices.contains(row) {
            let line = lines[row]
            let width = line.strippedLength
            let span = (columns ?? 0..<width).clamped(to: 0..<width)
            guard !span.isEmpty else { continue }
            // The reversed span ends in a reset, so the row's styling in force
            // past it is restated: a bold label after a reversed mark stays bold.
            result.lines[row] =
                line.ansiAwarePrefix(visibleCount: span.lowerBound)
                + reversed(line.ansiAwareSlice(visibleStart: span.lowerBound, visibleCount: span.count))
                + line.ansiStateBefore(visibleColumn: span.upperBound)
                + line.ansiAwareSuffix(droppingVisible: span.upperBound)
        }
        // A run wholly inside what was reversed replays reversed, as a faded buffer's
        // replays faded.
        result.paintRunGrounds { run, ground in
            let inside =
                rows.contains(run.offsetY)
                && (columns.map { $0.lowerBound <= run.offsetX && run.offsetX + run.width <= $0.upperBound } ?? true)
            return inside ? reversed(ground) : ground
        }
        return result
    }
}

extension _ButtonStyleBody {
    /// `buffer` saying in attributes what the colours would have said.
    ///
    /// A plain button already draws a ● for the focus, which needs no colour. A link's
    /// label only breathes, and a face only breathes its caps, so those reverse: all
    /// of the face but half-block caps, whose reversal would light the half facing
    /// away from the label and leave a gap beside it.
    ///
    /// A link's label rests at its breath's bright end, so it reverses too where the
    /// focus holds still (``RenderContext/focusHoldsStill``), at any depth.
    func statingStateWithoutColor(_ buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard context.statesWithoutColor || (configuration.isFocused && context.focusHoldsStill) else { return buffer }
        let edges = appearance.edges
        let hasCaps = !appearance.isPlain && edges.caps != nil && !edges.capsAreFace && !edges.isOutline
        return
            buffer
            .fadedWithoutColor(if: !configuration.isEnabled, context: context)
            .reversedWithoutColor(
                if: configuration.isFocused && !appearance.isPlain,
                columns: hasCaps ? 1..<max(1, buffer.width - 1) : nil, context: context)
            // A label that only breathes, as a link's does, rests at its breath's
            // bright end, so a still focus there is reversed too.
            .reversedWithoutBreath(
                if: configuration.isFocused && appearance.isPlain && appearance.indicatesFocusInLabel,
                context: context)
    }
}

extension RenderContext {
    /// Whether a control says its state in attributes and glyphs, not by colour alone:
    /// at ``ColorDepth/noColor``, where they are all it has, and wherever the person
    /// asked for cues that don't rest on colour
    /// (``EnvironmentValues/accessibilityDifferentiateWithoutColor``: macOS's
    /// Differentiate Without Colour where they're at this machine, or
    /// `TUI_DIFFERENTIATE_WITHOUT_COLOR`), over the colours. The one test every
    /// control's no-colour cues ask, so that they all turn on together.
    package var statesWithoutColor: Bool {
        ColorDepth.current == .noColor || environment.accessibilityDifferentiateWithoutColor
    }

    /// Whether a focused control's breath holds still here, at its bright end: the
    /// person turned it off (`TUI_BREATHING=0`, the View menu's Breathing Focus), the
    /// app did (`Scene.focusBreathing(false)`), or a view did for its subtree
    /// (`.selectionIndicatorStyle(.none)`).
    ///
    /// Not in a window that does not appear active: a focus there is held half-way
    /// between its breath's ends, which a resting control does not draw
    /// (``SelectionEmphasisClock/cycle(_:)``).
    package var focusHoldsStill: Bool {
        environment.selectionIndicatorStyle == .none && environment.appearsActive
    }
}
