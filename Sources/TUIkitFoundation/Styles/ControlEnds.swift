//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlEnds.swift
//
//  The ends of a one-row control that is not a button — a segmented picker,
//  a tab chip, a control group — read from the button's cap table, so that
//  every control of a family ends as a button of it does.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// How a one-row control's face ends, in the family in force: a segmented
/// picker's, a compact tab strip's chips', a control group's.
///
/// Read from the bordered button's cap table (`ButtonFaceEdges`, through
/// `_ButtonAppearance.sized(_:shape:family:blockElementsFillTheLine:)`) at the
/// ``ControlStyle``, ``Appearance``, ``ButtonBorderShape`` and ``ControlSize``
/// in force — on one row, whatever the size — so that these controls end
/// exactly as a button beside them does, and a family is one look (owner,
/// FB3-OTHERCAPS (2), 2026-10-23):
///
/// | family | capsule (the default) | rounded rectangle | `.mini` |
/// |---|---|---|---|
/// | filled | `▐ S │ M ▌`, half blocks in the face's colour | the face's own cells | the face, no caps |
/// | lines | `( S │ M )` on no field, in the lines' ink | `│ S │ M │` | the labels alone |
/// | Braille | the shape's dotted ends, on no field | the same | the labels alone |
/// | blank | no caps, no field | the same | the same |
package struct ControlEnds: Equatable, Sendable {
    /// How the two caps are drawn.
    package enum Kind: Equatable, Sendable {
        /// Glyphs in the face's colour with nothing behind them: the half
        /// blocks that round a filled face's ends, `▐ … ▌`.
        case filled
        /// Cells of the face itself: a filled rectangle's square ends.
        case face
        /// Glyphs in the lines' ink (``lineInk(palette:surface:hovered:disabled:)``):
        /// a lines face's `(` `)`, `│` `│` or `[` `]`, or a Braille face's dots.
        case lines
        /// No caps: a `.mini` control, or any under ``ControlStyle/blank``.
        case none
    }

    /// How the caps are drawn.
    package let kind: Kind

    /// The cap before the label, and the cap after it — spaces where
    /// ``kind`` is ``Kind/face``, and unused where it is ``Kind/none``.
    package let open: Character
    package let close: Character

    /// Whether the face has a field under its labels. Only a filled face
    /// does: a face of lines or dots is drawn on the surface, as a button's
    /// is, and so is a blank one.
    package let hasField: Bool

    /// The cells the two caps take together.
    package var width: Int { kind == .none ? 0 : 2 }

    /// The ends a one-row control takes in `environment`.
    ///
    /// - Parameter size: The size to read the table at, where the control
    ///   does not follow the ``ControlSize`` in force (a tab strip's chips),
    ///   or `nil` for the size in force. Any size is read on one row.
    package init(in environment: EnvironmentValues, size: ControlSize? = nil) {
        // One row whatever the size: only whether it draws caps matters here.
        let size: ControlSize = (size ?? environment.controlSize).drawsEndCaps ? .regular : .mini
        let edges = _ButtonAppearance.default.sized(
            size, shape: environment.buttonBorderShape, family: ButtonFaceFamily(environment),
            blockElementsFillTheLine: environment.blockElementsFillTheLine
        ).edges
        hasField = !edges.isOutline
        guard let caps = edges.caps else {
            (kind, open, close) = (.none, " ", " ")
            return
        }
        (open, close) = caps
        kind = edges.isOutline ? .lines : edges.capsAreFace ? .face : .filled
    }

    /// The ink a face's lines rest in on `surface`: a lines button's
    /// (`_ButtonStyleBody.outlineInk`) — the border's, held visible against
    /// the surface, lifted under the pointer and faded while disabled.
    @MainActor
    package static func lineInk(palette: any Palette, surface: Color, hovered: Bool, disabled: Bool) -> Color {
        _ButtonStyleBody.outlineInk(palette: palette, surface: surface, hovered: hovered, disabled: disabled)
    }

    /// Appends `glyph`, one of the two caps, to `row`, as ``kind`` draws it.
    ///
    /// - Parameters:
    ///   - face: The face's colour: a filled cap's ink, a face cap's field.
    ///   - lines: A lines cap's ink.
    ///   - field: What a lines cap is drawn on, or `nil` for nothing (the
    ///     surface shows through).
    package func appendCap(
        _ glyph: Character, to row: inout ClaimingRow, face: Color, lines: Color, field: Color? = nil
    ) {
        switch kind {
        case .filled: row.append(String(glyph), cells: 1, ink: face)
        case .face: row.append(" ", cells: 1, ink: nil, field: face)
        case .lines: row.append(String(glyph), cells: 1, ink: lines, field: field)
        case .none: break
        }
    }
}
