//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityBlend+BlendModes.swift
//
//  What a blend mode decides about one cell beyond its colours: over nothing,
//  and the three operators (`Opacity as composition.md` §110). The colours of
//  an arithmetic mode are `blendLayer`'s, through `Color.blending(_:at:over:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension FrameBuffer {
    /// What a blend mode makes of one cell before its colours are mixed.
    enum ModeOutcome {
        /// The cell, decided: an operator's answer, or nothing at all.
        case decided(RowCell)
        /// Mix the colours with this mode: the arithmetic one over something, else
        /// `.normal`.
        case colours(BlendMode)
    }

    /// `alpha.mode` (not `.normal`) applied to one cell, as far as it decides
    /// anything beyond the colours.
    ///
    /// Over nothing — no cell behind, or one that paints neither a glyph nor a
    /// field — an arithmetic mode is the source as it is, as SwiftUI draws one over
    /// a clear backdrop; ``BlendMode/sourceAtop`` and ``BlendMode/destinationOut``
    /// leave nothing; ``BlendMode/destinationOver`` leaves the source. Over
    /// something, `sourceAtop` paints the source onto what is behind and nowhere
    /// else (``paintingAtop(_:with:alpha:defaultForeground:)``), `destinationOver`
    /// is what is behind over the source, and `destinationOut` erases what is
    /// behind where the source paints.
    static func blendingByMode(
        source: RowCell, destination: RowCell?, alpha: CellAlpha, surface: Color, defaultForeground: Color
    ) -> ModeOutcome {
        let blank = RowCell(character: " ", style: SGRState())
        let behind = destination.flatMap { Self.paintsAnything($0) ? $0 : nil }
        switch alpha.mode {
        case .sourceAtop:
            guard let behind else { return .decided(destination ?? blank) }
            return .decided(paintingAtop(behind, with: source, alpha: alpha, defaultForeground: defaultForeground))
        case .destinationOver:
            guard let behind else { return .colours(.normal) }
            var under = alpha
            under.mode = .normal
            // The source's own cell, as it would land on the page, is what the cell
            // behind is drawn over.
            let source = blendLayer(
                source: source, destination: nil, alpha: under, surface: surface,
                defaultForeground: defaultForeground)
            return .decided(
                blendLayer(
                    source: behind, destination: source, alpha: CellAlpha(layer: 1), surface: surface,
                    defaultForeground: defaultForeground))
        case .destinationOut:
            guard let behind else { return .decided(destination ?? blank) }
            return .decided(erasing(behind, where: source, by: alpha.layer, surface: surface))
        default:
            return .colours(behind == nil ? .normal : alpha.mode)
        }
    }

    /// A cell's ink under an arithmetic blend `mode`, or `nil` where the source
    /// has none for the channel.
    ///
    /// A blank pane over a glyph: the glyph's ink lies under the pane's field, so
    /// the field is the source there. A glyph on a field of its layer's own: its
    /// pixels are the ink over that field, and those are blended. A glyph with no
    /// field: the ink, at its own alpha, is the source.
    static func inkBlended(
        by mode: BlendMode, source: RowCell, sourceInk: Color?, alpha: CellAlpha, over destinationInk: Color,
        sourcePaintsInk: Bool, destinationPaintsInk: Bool
    ) -> Color? {
        if !sourcePaintsInk, destinationPaintsInk, let field = source.background {
            return field.blending(mode, at: alpha.layer * alpha.field, over: destinationInk)
        }
        guard let ink = sourceInk else { return nil }
        guard let field = source.background else {
            return ink.blending(mode, at: alpha.layer * alpha.ink, over: destinationInk)
        }
        return ink.opacity(alpha.ink, over: field).blending(mode, at: alpha.layer, over: destinationInk)
    }

    /// `behind` painted with `source`'s colours where it paints, and nowhere else: a
    /// ``BlendMode/sourceAtop``.
    ///
    /// A field only where `behind` has one. A glyph `behind` draws keeps its place
    /// and takes the source's colour — its ink where the source draws a glyph,
    /// its field where it does not — so `Text(…).overlay(gradient.blendMode(.sourceAtop))`
    /// draws the letters in the gradient, as SwiftUI's idiom does. Where both
    /// draw a glyph, the source's is drawn at or above half opacity, as under
    /// ``View/opacity(_:)``.
    static func paintingAtop(
        _ behind: RowCell, with source: RowCell, alpha: CellAlpha, defaultForeground: Color
    ) -> RowCell {
        var result = behind
        let sourcePaintsInk = source.character != " " || source.style.paintsInkOnBlankCell
        let behindPaintsInk = behind.character != " " || behind.style.paintsInkOnBlankCell
        if let field = behind.background, let paint = source.background {
            result.background = paint.opacity(alpha.layer * alpha.field, over: field)
        }
        if behindPaintsInk {
            let ink = behind.foreground ?? defaultForeground
            if sourcePaintsInk, let sourceInk = displayedInk(of: source, defaultForeground: defaultForeground) {
                if alpha.layer >= 0.5 {
                    let field = result.background
                    result = source
                    result.background = field
                }
                result.foreground = sourceInk.opacity(alpha.layer * alpha.ink, over: ink)
            } else if let paint = source.background {
                result.foreground = paint.opacity(alpha.layer * alpha.field, over: ink)
            }
        }
        result.style = result.style.settingForeground(result.foreground).settingBackground(result.background)
        return result
    }

    /// Whether `cell` paints anything: a glyph, or a field of its own.
    static func paintsAnything(_ cell: RowCell) -> Bool {
        cell.background != nil || cell.character != " " || cell.style.paintsInkOnBlankCell
    }

    /// `behind` with what `source` paints taken out of it, by `amount`: a
    /// ``BlendMode/destinationOut``.
    ///
    /// Erased toward nothing, and nothing is the page here, the colour a cell with
    /// no field shows. A source field takes both channels; a glyph alone takes the
    /// glyph and leaves the field around it. The glyph goes at half or more, as a
    /// glyph contest does; below that it fades with the field.
    static func erasing(_ behind: RowCell, where source: RowCell, by amount: Double, surface: Color)
        -> RowCell
    {
        let paintsField = source.background != nil
        guard paintsField || source.character != " " || source.style.paintsInkOnBlankCell else { return behind }
        var result = behind
        if paintsField, let field = behind.background {
            result.background = surface.opacity(amount, over: field)
        }
        if amount >= 0.5 {
            result.character = " "
            result.foreground = nil
            result.style = result.style.settingForeground(nil)
            result.style.apply("\u{1B}[24;25;29m")
        } else if let ink = behind.foreground {
            result.foreground = surface.opacity(amount, over: ink)
        }
        result.style = result.style.settingForeground(result.foreground).settingBackground(result.background)
        return result
    }
}
