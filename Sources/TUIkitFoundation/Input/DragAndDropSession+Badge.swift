//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragAndDropSession+Badge.swift
//
//  The badge a drag's preview wears to name the operation the destination
//  under it proposes — macOS's pointer badge, drawn in one cell (B10).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
    /// The operation the destination under the drag proposes now, or `nil`
    /// while the drag is over nothing that proposes one.
    package var proposedOperation: DropOperation? {
        active?.targeted?.proposedOperation?()
    }

    /// `preview` with `operation`'s badge in its top-right cell, or `preview`
    /// unchanged where the operation wears none or there is no cell to put it in.
    ///
    /// On the preview, not beside it: the preview's frame is what a drop
    /// reports through ``DropInfo``, and a badge outside it would make the
    /// picture the pointer carries wider than that frame. The badge names no
    /// background, so it is drawn on whatever the corner cell stood on.
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
        let badge = FrameBuffer(text: glyph.styled(foreground: operation.badgeColor(in: palette)))
        return preview.composited(with: badge, at: (x: preview.width - 1, y: 0))
    }
}
