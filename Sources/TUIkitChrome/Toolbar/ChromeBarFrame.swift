//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeBarFrame.swift
//
//  The frame a window bar draws round its content: a box, a rule on the
//  page's side, or nothing, in the scene's chrome style.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - Bar Frame

/// One of the window's bars, framed: its already-rendered content inside the
/// chrome style's drawing.
///
/// An internal view the window's chrome host (`_WindowChromeHost`) frames
/// each toolbar with. It began as the app header's frame, which is why its
/// payload rules (below) are written in the header's terms.
///
/// ## Layout
///
/// ```
/// ┌──────────────────────────────────────────────────────────────────┐
/// │ My App Title                                       TUIkit v0.1.0 │
/// └──────────────────────────────────────────────────────────────────┘
/// ```
struct _ChromeBarFrame: View {
    /// The bar's content, already rendered.
    let contentBuffer: FrameBuffer

    /// How the bar frames itself against the page.
    let style: ChromeStyle

    /// Whether a `.rule` style draws its rule above the content rather than
    /// below it: the page's side of a bar drawn BELOW the page.
    var ruleAbove = false

    var body: Never {
        fatalError("_ChromeBarFrame renders via Renderable")
    }
}

// MARK: - Renderable

extension _ChromeBarFrame: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = context.availableWidth
        let palette = context.environment.palette
        var lines: [String] = []
        /// The row a `.rule` style's rule landed on, for its opacity claim.
        var ruleRow: Int?

        // The box's walls eat two columns, so its content is laid out narrower;
        // the other two styles get the full width. Same figure the modifier
        // proposed to the content, from the same place.
        let contentWidth = max(0, width - style.contentWidthInset)
        for line in contentBuffer.lines {
            lines.append(line.padToVisibleWidth(contentWidth))
        }

        switch style {
        case .rule:
            // A thin rule on the page's side of the content, drawn from the
            // same place the status bar draws its own — that shared source is
            // what keeps the two ends of the frame looking like a pair, and it
            // follows the current appearance so a custom border restyles both
            // at once. Claimed after `replacingLines` below, where the
            // content's own claims are already in these coordinates.
            if ruleAbove {
                lines.insert(ChromeStyle.ruleRow(width: width, context: context), at: 0)
                ruleRow = 0
            } else {
                lines.append(ChromeStyle.ruleRow(width: width, context: context))
                ruleRow = lines.count - 1
            }
        case .bordered:
            let border = context.environment.appearance.borderStyle
            let innerWidth = max(0, width - BorderRenderer.borderWidthOverhead)
            lines = lines.map {
                BorderRenderer.standardContentLine(
                    content: $0, innerWidth: innerWidth, style: border, color: palette.border)
            }
            lines.insert(
                BorderRenderer.standardTopBorder(
                    style: border, innerWidth: innerWidth, color: palette.border),
                at: 0)
            lines.append(
                BorderRenderer.standardBottomBorder(
                    style: border, innerWidth: innerWidth, color: palette.border))
        case .compact:
            break  // content alone; the background colour is the only boundary
        }

        // `FrameBuffer(lines:)` builds a fresh buffer, so every side payload the
        // header content emitted has to be carried over ONE BY ONE — and each
        // one that was not is a feature that silently does nothing inside
        // `.appHeader { … }`. That is the bare-`FrameBuffer(lines:)` tell: hit
        // regions went first (`e5382a77`, a Button in the header that could not
        // be clicked), opacity followed, and the two below were still missing.
        //
        // `replacingLines` does all four at once, with the shift a box needs —
        // right by its wall, down by its top rule — applied to each. Written as
        // four assignments it was four chances to forget one, which is what
        // happened twice.
        var framed = contentBuffer.replacingLines(
            lines,
            // Animated runs: a `Spinner` or any `.animatedCells` in the header
            // was frozen at frame 0, because a dropped run does not look like a
            // dropped animation — it looks like a still one.
            //
            // Overlays: a `Menu`, `.popover` or `.alert` declared in the header
            // OPENED (its state flipped, its hit region was live) and then drew
            // nothing at all, because the layer carrying its picture was thrown
            // away before anything could composite it.
            overlayShiftX: style == .bordered ? 1 : 0,
            overlayShiftY: style == .bordered || (style == .rule && ruleAbove) ? 1 : 0)
        // The chrome's own cells, when the theme's `border` is faded. Appended
        // AFTER `replacingLines` has shifted the content's own claims inward, so
        // the two sets are in the same coordinates.
        if style == .bordered {
            framed.opacityRegions += BorderRenderer.opacityClaims(
                outerWidth: width, height: lines.count,
                style: context.environment.appearance.borderStyle, color: palette.border)
        }
        if let ruleRow,
            let claim = ChromeStyle.ruleClaim(width: width, offsetY: ruleRow, context: context)
        {
            framed.opacityRegions.append(claim)
        }
        // The rule, or the box's rules, are drawn over what the content draws
        // past its region, as a box's border is; past them it is still drawn
        // (decisions-GUIDE3 B-GUIDE3-5).
        if style == .bordered {
            framed.coverOverflowUnderBorder(innerWidth: max(0, width - BorderRenderer.borderWidthOverhead))
        } else if let ruleRow {
            framed.coverOverflow(underRects: [(x: 0, y: ruleRow, width: width, height: 1)])
        }
        return framed
    }
}

// MARK: - Lifting a bar's layers onto the page

extension FrameBuffer {
    /// This buffer with its overlay layers moved onto `buffer` and shifted
    /// `rows` down, and nothing else changed.
    ///
    /// A `Menu`, `.popover`, `.sheet` or `.alert` declared inside a toolbar
    /// item emits a layer like any other, and `_ChromeBarFrame` carries it
    /// through the rebuild above. That was a prerequisite and not the fix: the
    /// chrome host composites layers inside the content area, and a layer left
    /// on a bar's buffer would never be composited at all. A drop-down opened
    /// from a top-bar button took the focus and drew nothing.
    ///
    /// Moved to the page rather than composited into the bar, because a
    /// drop-down anchored on the bottom row of a three-row top bar is taller
    /// than the bar it hangs out of: compositing it there would clip it to the
    /// chrome it escaped. The page is where it belongs and where the page's own
    /// drop-downs already are.
    ///
    /// Both bars lift theirs. `rows` is where the bar's first row sits relative
    /// to the content area's: minus the top bar's rows for the top bar, so its
    /// row `h` is content row `h - rows`, which is negative for a layer still
    /// inside the bar — fine, the compositor cuts a layer overhanging the top
    /// edge exactly as it cuts one overhanging the left — and the content
    /// area's height for the bottom bar, below it. Anything can be placed in
    /// the bottom bar (a `Menu` beside the line of key hints), so it can
    /// present as the top bar can, and its layers go to the page the same way.
    ///
    /// A CENTRED layer is the exception, and it divides on the same line
    /// `.zIndex` and `.alignmentGuide` do: an anchored layer's offset is a
    /// POSITION, which means something different in a different coordinate
    /// space, while a centred one's is a post-centre DELTA — zero until the
    /// user drags the dialog — which means the same thing in both. Shifting it
    /// would slide a dialog presented from the top bar up by the bar's height.
    func liftingOverlays(shiftingBy rows: Int, onto buffer: inout FrameBuffer) -> FrameBuffer {
        guard !overlays.isEmpty else { return self }
        var lifted = self
        for layer in overlays {
            var moved = layer
            if !moved.centered { moved.offsetY += rows }
            buffer.overlays.append(moved)
        }
        lifted.overlays = []
        return lifted
    }
}
