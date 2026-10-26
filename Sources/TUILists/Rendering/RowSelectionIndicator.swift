//  🖥️ TUI — A Terminal UI framework for Swift
//  RowSelectionIndicator.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - What a selectable row's line owes

/// The claims one line of a selectable row owes for the translucent colours it
/// painted.
///
/// Here beside ``RowBackground`` and ``RowSelectionIndicator`` for exactly the reason
/// those are: a `List` and a `Table` run the same rules about focus, selection and
/// visibility, they have drifted apart before, and "which cells of a row owe a blend"
/// is one more rule that must not be written out twice.
///
/// `@usableFromInline`: ``claims(line:width:cells:ink:mark:fill:)`` is
/// `@inlinable` (module split, step C2).
@usableFromInline
package enum SelectableRowClaims {
    /// - Parameters:
    ///   - line: Which of the row's lines this is, in the row's own coordinates.
    ///   - width: The row's full width — what a background fill covers.
    ///   - cells: The columns the row's TEXT occupies, which start past the mark and
    ///     its gap. Empty where the caller draws no text of its own (a `List` row's
    ///     content is a child buffer that claims for itself).
    ///   - ink: The colour every cell of that text was drawn in.
    ///   - mark: The colour the selection ● was drawn in, or `nil` on a continuation
    ///     line and wherever no mark is drawn.
    ///   - fill: The row's background, or `nil` for a row that paints none and for a
    ///     PULSING one (see ``RowBackground/claimableFill``).
    /// - Returns: Between zero and three regions, in the row's own coordinates.
    ///
    /// Three rectangles rather than one, and they must not be merged. The mark and the
    /// text are different colours: a merged INK rectangle would resolve the ● at the
    /// text's alpha, which is §23.2's mistake in a different shape. The fill is a
    /// different CHANNEL, so its rectangle overlaps both and that is correct — an
    /// ink-only region carries `fieldOpacity: 1` and a field-only one carries
    /// `inkOpacity: 1`, and the resolver multiplies across every region covering a
    /// cell (§27). This is `.foregroundStyle(…).background(…)` in row form.
    ///
    /// The gap cell between the mark and the text is deliberately covered by the FILL
    /// claim only. It is a bare space, which draws no glyph: no ink of its own in a
    /// `List` row, and in a `Table` row the mark's ink run on across it (`TableRowInk`),
    /// which a blank does not show and the resolution reads as the cell's field
    /// (`OpacityBlend.displayedInk(of:defaultForeground:)`). An ink claim on such a
    /// cell lets what is behind it through where the row drew a pad.
    ///
    /// `@inlinable`, and only the opaque test (module split, step C2): a table
    /// in TUITables asks this for every row it composes, and nearly every
    /// row is opaque, so its caller answers that in place, as it did while
    /// one module compiled both; a translucent row calls
    /// ``translucentClaims(line:width:cells:ink:mark:fill:)``.
    @inlinable
    package static func claims(
        line: Int, width: Int, cells: Range<Int>, ink: Color?, mark: Color?, fill: Color?
    ) -> [OpacityRegion] {
        // Asked first, so an opaque row — every row of nearly every table — pays three
        // alpha compares and allocates nothing.
        guard ink?.isOpaque == false || mark?.isOpaque == false || fill?.isOpaque == false
        else { return [] }
        return translucentClaims(line: line, width: width, cells: cells, ink: ink, mark: mark, fill: fill)
    }

    /// The claims of a row that painted at least one translucent colour: the
    /// rest of ``claims(line:width:cells:ink:mark:fill:)``, out of line.
    @usableFromInline
    static func translucentClaims(
        line: Int, width: Int, cells: Range<Int>, ink: Color?, mark: Color?, fill: Color?
    ) -> [OpacityRegion] {
        var claims: [OpacityRegion] = []
        if let mark, let claim = OpacityRegion.claim(
            offsetX: 0, offsetY: line, width: 1, height: 1, ink: mark)
        {
            claims.append(claim)
        }
        if let claim = OpacityRegion.claim(
            offsetX: cells.lowerBound, offsetY: line, width: cells.count, height: 1, ink: ink)
        {
            claims.append(claim)
        }
        if let claim = OpacityRegion.claim(
            offsetX: 0, offsetY: line, width: width, height: 1, field: fill)
        {
            claims.append(claim)
        }
        return claims
    }
}

// MARK: - Selection Indicator

/// The glyph a selectable row shows in its indicator gutter, and its colour.
///
/// Here, beside ``RowBackground``, for exactly the reason that type gives: the
/// two views are twins running the same rules about focus, selection and the
/// unfocused-selection visibility, and this is a place they HAD already
/// drifted. `Table` drew a bullet in its gutter; `_ListCore` reserved a gutter
/// of identical purpose on every row and never drew anything in it. Same state,
/// same palette, same pulse — one showed the mark and the other did not.
///
/// **It marks SELECTION, not focus.** Which row the cursor is on is said by the
/// background, which breathes while the control has the keys; a row merely
/// under the cursor has not been chosen, and says so with no glyph, and with the
/// neutral focus wash behind it rather than the accent, breathing whether or not
/// the control draws a mark at all (``RowBackground/focused(in:palette:)``).
/// So a control with no selection at all draws no glyph on any row, which is
/// what a plain `List` looked like before this existed and still looks like now.
package struct RowSelectionIndicator: Equatable {
    /// Exactly one cell wide, always — the gutter is reserved whether or not
    /// there is anything to put in it, so a blank is a space rather than an
    /// empty string. A row whose glyph changed width would move its content.
    package let glyph: String

    /// The colour to draw ``glyph`` in. Meaningless for a blank, and set to the
    /// same tertiary the `Table` has always used there rather than to `nil`, so
    /// callers need no optional they would only ever pass through.
    package let color: Color

    /// Whether anything is actually drawn — for a caller that can skip work
    /// when the answer is a space.
    var isBlank: Bool { glyph == " " }

    /// `context` with a `Table`'s answer for an ``EnvironmentValues/rowSelectionIndicator``
    /// left `.automatic`: no mark where colour can show the selection — the
    /// highlight says which rows are selected, and the mark's two cells go
    /// back to the columns — and the mark where it cannot, a terminal with no
    /// colour at all, where nothing else tells a selected row from the rest.
    /// A `List`'s mark costs it no cells, so a list keeps it.
    package static func resolvingForTable(_ context: RenderContext) -> RenderContext {
        guard context.environment.rowSelectionIndicator == .automatic else { return context }
        var context = context
        context.environment.rowSelectionIndicator = ColorDepth.current == .noColor ? .visible : .hidden
        return context
    }

    /// Whether a control should set cells aside for the mark at all.
    ///
    /// A control with no selection binding has nothing to mark, and one told
    /// ``View/rowSelectionIndicator(_:)`` `.hidden` has been told not to mark
    /// it. Either way ``forRow(isFocused:isSelected:context:palette:)`` answers
    /// a blank for every row for the control's whole life, so cells kept for it
    /// are an indent nobody asked for — which is what a `Table` with no
    /// selection was: three cells of air before every value, two of them
    /// unreachable.
    ///
    /// Only ``forRow(isFocused:isSelected:context:palette:)``'s *structural*
    /// conditions are here. The per-row ones are not: whether THIS row is
    /// selected, and whether an unfocused selection is shown, both change as
    /// the app runs, and a column that appeared when you clicked a row would
    /// shift every value in the table sideways.
    ///
    /// `Table` reserves two cells — the glyph and the gap to the first column —
    /// and gives both back here. `_ListCore` reserves none: it draws its mark
    /// in the one pad cell its rows already had, so it has nothing to hand
    /// back, and asks this only so the two twins keep answering one question in
    /// one place.
    ///
    /// - Parameters:
    ///   - hasSelection: Whether the control has a selection binding at all.
    ///   - environment: For ``EnvironmentValues/rowSelectionIndicator``.
    package static func isReserved(hasSelection: Bool, environment: EnvironmentValues) -> Bool {
        hasSelection && environment.rowSelectionIndicator != .hidden
    }

    /// The indicator for a row in the state given.
    ///
    /// - Parameters:
    ///   - isFocused: Whether this is the cursor row AND the control has focus.
    ///   - isSelected: Whether the row is in the selection.
    ///   - context: For ``EnvironmentValues/unfocusedSelectionVisibility``.
    ///   - palette: The colours to draw from.
    @MainActor
    package static func forRow(
        isFocused: Bool, isSelected: Bool, context: RenderContext, palette: any Palette
    ) -> Self {
        let blank = Self(glyph: " ", color: palette.foregroundTertiary)
        guard isSelected else { return blank }
        // The caller asked for the highlight alone. Checked before anything
        // else, because it is a statement about this control rather than about
        // this row's state.
        guard context.environment.rowSelectionIndicator != .hidden else { return blank }
        // The cursor row of a focused control — in a window that has lost the
        // terminal's focus too. Its background quietens there to the tint an
        // unfocused selection shows (``RowBackground/focusedSelection(in:palette:)``);
        // the mark staying at full strength is what still tells it from one.
        if isFocused { return Self(glyph: "●", color: palette.accent) }
        // Selected while the control itself does not have focus. `.hidden`
        // collapses the row's whole visual state into an unselected one — the
        // background does the same — so the mark goes with it.
        guard context.environment.unfocusedSelectionVisibility != .hidden else { return blank }
        return Self(
            glyph: "●",
            color: palette.accent.opacity(ViewConstants.selectionIndicator, over: palette.background)
        )
    }
}
