//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TooltipPopover.swift
//
//  The tooltip as a panel attached to the control, rather than a row of chrome.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling

// MARK: - TooltipPopover

/// Builds and attaches the ``TooltipStyle/popover`` presentation.
///
/// ## Why this is not modelled on `.popover`
///
/// `PopoverPresentationModifier` registers a focus section, activates it, marks
/// it modal and calls `grabInput` — every one of which a tooltip must not do. It
/// is not in the focus ring at all, which is simply a matter of registering
/// nothing; and it claims no keys, so Escape and the arrows keep meaning what
/// they meant.
///
/// The model is `TextFieldSuggestions.attach` instead: an overlay anchored under
/// a focused control that steals nothing. What is shared with the drop-down menu
/// is only the geometry — `OverlayLayer.placed(maxWidth:maxHeight:)` clamps to
/// the screen and flips above the anchor when the panel would overflow the
/// bottom, given `anchorHeight`. That is rules 1–3 of
/// `Documentation/Controls and presentation/Tooltips and help in a terminal.md` §5, already built and already tested.
///
/// ## What is deliberately not implemented yet
///
/// §5's rules 4 and 5 — prefer a placement not under the pointer, and re-wrap
/// to a narrower box before rejecting a placement. Neither exists in
/// `placed(maxWidth:maxHeight:)`, both are new constraints on it rather than
/// uses of it, and rule 4 is explicitly ranked below 1–3 by the design. The
/// panel wraps to a fixed sensible width and takes the placement the shared rule
/// gives it. A tooltip in the way is dismissed by moving the pointer, or by the
/// help key if it was revealed by one.
///
/// ## Many panels at once
///
/// Under `.tooltips(.always)` every `help(_:)` attaches a panel, and the shared
/// rule places each as if it were alone, so a `Button`'s covered a `Text`'s.
/// Those panels carry a ``OverlayLayer/peerPlacement`` and the screen root
/// places them together (`OverlayLayer.arrangingPeers`): rules 1–3 for each,
/// plus no panel over another and as little as possible over the other views
/// with help, in reading order, dropping what does not fit.
@MainActor
enum TooltipPopover {

    /// The widest a tooltip panel may be, in cells of text.
    ///
    /// A fixed cap rather than the terminal's width: help text set across 200
    /// columns is one long line the eye has to track back along, and the panel
    /// floats over content the reader is trying to keep in view.
    static let maxTextWidth = 44

    /// Attaches the panel to `buffer`, anchored beneath it.
    ///
    /// - Parameters:
    ///   - text: The help text.
    ///   - buffer: The control's own buffer — the anchor.
    ///   - context: The render context, for the palette and the available width.
    ///   - peerRank: For a panel drawn as one of a set (`.tooltips(.always)`),
    ///     its ``OverlayLayer/PeerPlacement/rank``: the root then places it
    ///     among the others rather than where it would go alone. `nil` for the
    ///     one tooltip a frame shows.
    static func attach(
        text: String, to buffer: inout FrameBuffer, context: RenderContext, peerRank: Int? = nil
    ) {
        let panel = panel(text: text, maxWidth: context.availableWidth, context: context)
        guard !panel.lines.isEmpty else { return }
        var layer = OverlayLayer(
            // Directly beneath the control, left-aligned to it — §5's rule 1.
            // `anchorHeight` is what lets `placed(maxWidth:maxHeight:)` flip
            // it ABOVE rather than off the bottom of the screen, and the
            // anchor is the whole control so a flipped panel clears it.
            offsetX: 0, offsetY: buffer.height, content: panel,
            level: .popover, anchorHeight: buffer.height)
        if let peerRank {
            layer.peerPlacement = OverlayLayer.PeerPlacement(anchorWidth: buffer.width, rank: peerRank)
        }
        buffer.overlays.append(layer)
    }

    /// The bordered panel: the text wrapped, boxed, and opaque.
    ///
    /// Opaque matters — a tooltip floats over content, and a transparent one
    /// would leave the page's own glyphs showing through its box.
    static func panel(text: String, maxWidth: Int, context: RenderContext) -> FrameBuffer {
        let chrome = BorderRenderer.borderWidthOverhead + 2  // walls + a space each side
        let textWidth = max(1, min(maxTextWidth, maxWidth - chrome))
        let wrapped = TextWrapping.wrap(text, width: textWidth)
        guard !wrapped.isEmpty else { return FrameBuffer() }

        // Boxed at the WIDEST line rather than at `textWidth`, so a short
        // tooltip is a short box. Measured with `strippedLength` because the
        // help text may carry escape codes of its own.
        let innerWidth = (wrapped.map(\.strippedLength).max() ?? 0) + 2
        let border = context.environment.appearance.borderStyle
        let palette = context.environment.palette
        // The help text is text: a tier heavier under a bold legibility weight.
        let bold = context.environment.legibilityWeight.drawsPlainBold
        let lines =
            [
                BorderRenderer.standardTopBorder(
                    style: border, innerWidth: innerWidth, color: palette.border)
            ]
            + wrapped.map { line in
                BorderRenderer.standardContentLine(
                    content: " "
                        + ANSIRenderer.colorize(
                            line.padToVisibleWidth(innerWidth - 2),
                            foreground: palette.foreground.opaqueSpelling,
                            background: palette.background.opaqueSpelling, bold: bold) + " ",
                    innerWidth: innerWidth, style: border, color: palette.border)
            }
            + [
                BorderRenderer.standardBottomBorder(
                    style: border, innerWidth: innerWidth, color: palette.border)
            ]
        var panel = FrameBuffer(lines: lines)
        // A `Palette` is a public protocol of plain `var …: Color` members and
        // nothing normalises what a conformance returns, so a theme's own
        // translucency arrives here. The frame and the text inside it are two
        // claims because they are two paints: `standardContentLine` puts the wall
        // at each end and the tooltip's own text between.
        panel.opacityRegions = BorderRenderer.opacityClaims(
            outerWidth: innerWidth + 2, height: lines.count, style: border,
            color: palette.border)
        if let text = OpacityRegion.claim(
            offsetX: 1, offsetY: 1, width: innerWidth, height: wrapped.count,
            ink: palette.foreground, field: palette.background)
        {
            panel.opacityRegions.append(text)
        }
        return panel
    }
}
