//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+Placeholder.swift
//
//  What an image draws while it has no picture to: its placeholder, or the
//  error its load ended in, centred in its box.
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation
import TUIImage

// MARK: - Placeholder Rendering

extension _ImageCore {
    /// Renders the placeholder, centred: a spinner above the text when the spinner
    /// is shown, and otherwise the text alone, or "Loading..." when there is none.
    func renderPlaceholder(
        width: Int,
        height: Int,
        text: String?,
        spinner: ImagePlaceholderSpinner,
        context: RenderContext
    ) -> FrameBuffer {
        if spinner.isShown {
            // A real `Spinner`, composed, the way `RefreshableModifier` draws its
            // indicator. So it animates with a run of its own at the speed set for
            // spinners, takes `.foregroundStyle`, and claims its own cell, which the
            // frame's offset carries to wherever the centring puts it. It used to be a
            // still "⠋" in the accent. The text keeps the secondary foreground whatever
            // `.foregroundStyle` says, as it always has.
            //
            // At a child identity, so nothing the composition keys by identity (the
            // spinner's fallback wake token, for one) shares this core's.
            let placeholder = VStack(spacing: 0) {
                Spinner(style: spinner.style, color: spinner.color)
                if let text {
                    Text(verbatim: text).foregroundStyle(Color.palette.foregroundSecondary)
                }
            }
            // `.center` said out loud: TUI's `frame(width:height:)` defaults to
            // `.topLeading`, where SwiftUI's centres.
            .frame(width: width, height: height, alignment: .center)
            return TUIView.renderToBuffer(
                placeholder,
                context: context.withAvailableSize(width: width, height: height)
                    .withChildIdentity(type: type(of: placeholder)))
        }

        let palette = context.environment.palette

        // Build placeholder content lines, each with the colour it is to be drawn
        // in rather than already drawn in it: `centerContent` is the only thing that
        // knows where a centred line lands, so it is the only thing that can claim
        // the cells (§68.3).
        var contentLines: [(text: String, ink: Color)] = []

        if let text {
            contentLines.append((text: context.spelled(text), ink: palette.foregroundSecondary))
        }

        if contentLines.isEmpty {
            contentLines.append((text: "Loading...", ink: palette.foregroundSecondary))
        }

        return centerContent(contentLines, width: width, height: height)
    }

    /// Renders an error message centered in the frame.
    func renderError(
        _ message: String,
        width: Int,
        height: Int,
        context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        return centerContent(
            [(text: "Error: \(context.spelled(message))", ink: palette.error)], width: width, height: height)
    }

    /// Centers content lines vertically and horizontally within the given
    /// dimensions, cutting any line wider than `width` to it (and closing the
    /// styling the cut interrupts).
    ///
    /// The returned buffer's declared `width` is therefore an upper bound on
    /// every row it carries — which the general clamp assumes and cannot check
    /// here (see the clip below). Rows may be NARROWER than `width` (the
    /// centring pads on the left only), so the buffer stays non-uniform: do not
    /// pass `uniformWidth: true`, or `appendHorizontally` skips the pad for a
    /// centred row and lands the next sibling mid-box.
    func centerContent(
        _ contentLines: [(text: String, ink: Color)], width: Int, height: Int
    ) -> FrameBuffer {
        let emptyLine = String.spaces(width)
        var lines = [String](repeating: emptyLine, count: height)
        var claims: [OpacityRegion] = []

        let startY = max(0, (height - contentLines.count) / 2)

        for (i, content) in contentLines.enumerated() {
            let y = startY + i
            guard y < height else { break }

            // Drawn here, in the opaque spelling, with the alpha claimed below once
            // the pad and any cut have decided which cells it covers. A placeholder's
            // accent and an error's `palette.error` both reached the emitter with a
            // faded palette's alpha on them before this (§68.3).
            var line = ANSIRenderer.colorize(
                content.text, foreground: content.ink.opaqueSpelling)
            var visibleWidth = line.strippedLength

            // Cut it, rather than merely failing to pad it. "Loading..." is 10
            // cells and an "Error: <path>" far more, while this buffer declares
            // only `width` columns — and that is a lie the general net cannot
            // catch: every ancestor clamps with `clamped(toWidth:height:)`,
            // whose `self.width <= maxWidth` fast path TRUSTS the declaration,
            // and `width` here IS that clamp target (`availableWidth`). The
            // over-wide row then reaches `appendHorizontally`, which measures
            // the row's REAL width and starts the next `HStack` sibling past
            // it — shearing that one row from the rest of the same box. Same
            // clip primitive as `clamped` and `_ListCore.fitted`: counts cells,
            // never splits a wide glyph, keeps the styling in force.
            if visibleWidth > width {
                let (cut, cutWidth) = line.ansiAwarePrefixWithWidth(
                    visibleCount: width, knownVisibleWidth: visibleWidth)
                // Closed, because the cut lands mid-run and drops the reset
                // `colorize` had put at the end — the clip primitive closes an
                // open hyperlink but never SGR. Without this the placeholder's
                // colour stays in force and paints whatever the row holds next:
                // the very `HStack` sibling this clip just pulled back to the
                // box edge. `BorderRenderer.contentLine` closes its clip the
                // same way; `_ListCore.fitted` gets away without it only
                // because it pads with plain spaces, where a leaked foreground
                // cannot be seen. The reset is stripped by every width scan, so
                // it costs no columns.
                line = cut + ANSIRenderer.reset
                visibleWidth = cutWidth
            }

            // Still `max(0,)`: the clip above makes this non-negative, and
            // `String(repeating:count:)` traps if it ever stops being.
            let padding = max(0, (width - visibleWidth) / 2)
            let padded = String.spaces(padding) + line
            lines[y] = padded
            // The cells the glyphs actually took: past the pad, and `visibleWidth`
            // wide, which the clip above has already reduced if it cut the line. The
            // pad itself is a bare space and claims nothing — an ink claim over one
            // lets what is behind show through where this drew blank.
            if let claim = OpacityRegion.claim(
                offsetX: padding, offsetY: y, width: visibleWidth, height: 1,
                ink: content.ink)
            {
                claims.append(claim)
            }
        }

        var buffer = FrameBuffer(lines: lines, width: width)
        buffer.opacityRegions = claims
        return buffer
    }
}
