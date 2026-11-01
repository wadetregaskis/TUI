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
/// `SelectionDisabledModifier` already uses for a row that can't be selected.
///
/// Both are no-ops at any other depth, so the colours keep the job there.
extension FrameBuffer {
    /// This buffer drawn faint, if `isDisabled`, at ``ColorDepth/noColor``.
    package func fadedWithoutColor(if isDisabled: Bool) -> FrameBuffer {
        guard isDisabled, ColorDepth.current == .noColor else { return self }
        var faded = self
        faded.lines = lines.map(ANSIRenderer.applyPersistentDim)
        // Under the runs too, as `SelectionDisabledModifier` does, so that a replayed
        // tick draws what the render did.
        faded.paintRunGrounds { _, ground in ANSIRenderer.applyPersistentDim(ground) }
        return faded
    }

    /// This whole buffer saying `state`, at ``ColorDepth/noColor``, for a control with no
    /// part of it that means anything by being lit.
    package func statingWithoutColor(focused: Bool, disabled: Bool) -> FrameBuffer {
        reversedWithoutColor(if: focused && !disabled).fadedWithoutColor(if: disabled)
    }

    /// This buffer with `columns` of `rows` in reverse video, if `isFocused`, at
    /// ``ColorDepth/noColor``.
    ///
    /// A column range rather than the whole buffer because a control's indicator can
    /// mean something by which part of it is lit, as a checkbox's mark and a slider's
    /// track do, and reversing it would say the opposite.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the control shows the focus.
    ///   - rows: The rows to reverse, or all of them.
    ///   - columns: The columns to reverse, or all of them.
    package func reversedWithoutColor(
        if isFocused: Bool, rows: Range<Int>? = nil, columns: Range<Int>? = nil
    ) -> FrameBuffer {
        guard isFocused, ColorDepth.current == .noColor else { return self }
        func reversed(_ text: String) -> String {
            // At this depth the two colours spell nothing, and only the 7 is left.
            ANSIRenderer.applyPersistentReverse(text, ink: .default, field: .default)
        }
        let rows = rows ?? 0..<lines.count
        var result = self
        for row in rows where lines.indices.contains(row) {
            let line = lines[row]
            let width = line.strippedLength
            let span = (columns ?? 0..<width).clamped(to: 0..<width)
            guard !span.isEmpty else { continue }
            result.lines[row] =
                line.ansiAwarePrefix(visibleCount: span.lowerBound)
                + reversed(line.ansiAwareSlice(visibleStart: span.lowerBound, visibleCount: span.count))
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
    func statingStateWithoutColor(_ buffer: FrameBuffer) -> FrameBuffer {
        guard ColorDepth.current == .noColor else { return buffer }
        let edges = appearance.edges
        let hasCaps = !appearance.isPlain && edges.caps != nil && !edges.capsAreFace && !edges.isOutline
        return
            buffer
            .fadedWithoutColor(if: !configuration.isEnabled)
            .reversedWithoutColor(
                if: configuration.isFocused && (!appearance.isPlain || appearance.indicatesFocusInLabel),
                columns: hasCaps ? 1..<max(1, buffer.width - 1) : nil)
    }
}
