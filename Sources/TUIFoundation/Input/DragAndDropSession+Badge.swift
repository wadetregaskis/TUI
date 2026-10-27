//  🖥️ TUI — A Terminal UI framework for Swift
//  DragAndDropSession+Badge.swift
//
//  The badge a drag's preview wears to name the operation the destination
//  under it proposes — macOS's pointer badge, drawn in one cell (B10).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - The glyphs

extension DropOperation {
    /// The one-cell badge naming this operation on a drag's preview, or `nil`
    /// for none: `+` for a copy, as Finder draws it, `↗` for a link and `⊘`
    /// for a drop that is not allowed. A move is the plain drag, so it wears
    /// nothing, and a cancel proposes no drop at all. A delete wears nothing
    /// either: its glyph was not among those the owner confirmed (B10,
    /// 2026-10-12; the candidates are in decisions B-BITEMS1-1).
    ///
    /// Single-width glyphs rather than emoji (➕), whose width varies between
    /// terminals and would knock the preview out of line. `+` is Narrow and
    /// `⊘` (U+2298) Neutral, one cell everywhere; `↗` (U+2197) is East Asian
    /// Ambiguous, measured one cell on the hosts in Terminal compatibility
    /// survey.md, "The drop-operation badge".
    package var badgeGlyph: String? {
        switch self {
        case .copy: "+"
        case .alias: "\u{2197}"
        case .forbidden: "\u{2298}"
        case .move, .delete, .cancel: nil
        }
    }

    /// The badge's ink: the error colour for a drop that is not allowed, the
    /// accent for the rest.
    package func badgeColor(in palette: any Palette) -> Color {
        self == .forbidden ? palette.error : palette.accent
    }
}

// MARK: - The badge on the preview

extension DragAndDropSession {
    /// The operation a drop where the drag is now would be
    /// (``effectiveOperation(for:)``), or `nil` while it is over no
    /// destination.
    package var proposedOperation: DropOperation? {
        active?.targeted.flatMap(effectiveOperation(for:))
    }

    /// The operation a drop on `target` would be, macOS's three-party model
    /// (owner ruling B-BITEMS1-1): the destination proposes one — its own, or
    /// else a move into the container the drag came from and a copy anywhere
    /// else; the one pointer modifier the terminal delivers (or Option, where
    /// the terminal reports keys held alone) flips a copy to a move and back;
    /// and the source's allowed operations narrow it — the other of the two
    /// where only that is allowed, `.forbidden` where neither is, which refuses
    /// the drop. An alias, a delete, a cancel or a forbidden proposal is the
    /// destination's own and stands.
    package func effectiveOperation(for target: Target) -> DropOperation? {
        guard let drag = active else { return nil }
        let proposal =
            target.proposedOperation?()
            ?? (target.identity.map { isDragSource(within: $0) } == true ? .move : .copy)
        guard proposal == .copy || proposal == .move else { return proposal }
        let flipped = (lastAbsoluteEvent?.meta == true) != keyboardFlipsOperation
        let wanted: DropOperation = flipped ? (proposal == .copy ? .move : .copy) : proposal
        let other: DropOperation = wanted == .copy ? .move : .copy
        // A copy or a move, as the source's set spells it.
        func allows(_ operation: DropOperation) -> Bool {
            drag.allowedOperations.contains(operation == .copy ? .copy : .move)
        }
        if allows(wanted) { return wanted }
        return allows(other) ? other : .forbidden
    }

    /// `preview` with `operation`'s badge on the last cell of its top row, or
    /// `preview` unchanged where the operation wears none or there is no cell
    /// to put it in.
    ///
    /// On the preview, not beside it: the preview's frame is what a drop
    /// reports through ``DropInfo``, and a badge outside it would make the
    /// picture the pointer carries wider than that frame. The badge names no
    /// background, so it is drawn on whatever the corner cell stood on.
    ///
    /// Where the top row ENDS, which is the top-right corner of every
    /// rectangular preview, and with every row kept to its own width: a row
    /// shorter than the widest lets the page show through the cells after it,
    /// and compositing the badge padded every row to the widest with blanks
    /// that covered the page there. A top row of one cell wears the badge
    /// beside it instead, since covering that cell hid the whole picture of a
    /// one-glyph drag; a blank top row starts with it.
    ///
    /// - Parameters:
    ///   - preview: The picture the pointer carries, as it is lifted.
    ///   - operation: The proposed operation.
    ///   - palette: The palette the badge's ink comes from.
    /// - Returns: The preview, badged.
    package static func badged(
        _ preview: FrameBuffer, operation: DropOperation?, palette: any Palette
    ) -> FrameBuffer {
        guard let operation, let glyph = operation.badgeGlyph, preview.width > 0, preview.height > 0 else {
            return preview
        }
        var widths = preview.lines.indices.map { row in
            preview.linesAreUniformWidth ? preview.width : preview.lineWidths?[row] ?? preview.lines[row].strippedLength
        }
        let column = widths[0] > 1 ? widths[0] - 1 : widths[0]
        widths[0] = max(widths[0], column + 1)
        let badge = FrameBuffer(text: glyph.styled(foreground: operation.badgeColor(in: palette)))
        // Composited for its payloads — whatever ran or was hit under the
        // badge's cell punched, as under any overlay — then each row given back
        // its own width, which compositing padded to the widest.
        let composited = preview.composited(with: badge, at: (x: column, y: 0))
        var lines = preview.lines
        lines[0] = composited.lines[0].ansiAwarePrefix(visibleCount: widths[0])
        return composited.replacingLines(
            lines, width: composited.width, uniformWidth: widths.allSatisfy { $0 == composited.width },
            lineWidths: widths)
    }
}
