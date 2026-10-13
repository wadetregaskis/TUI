//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerViewCore+Borderless.swift
//
//  A box drawn without border chrome: moved out of ContainerViewCore.swift,
//  which had reached the length the project's lint allows.
//
//  Created by LAYERED.work
//  License: MIT

extension _ContainerViewCore {
    /// Renders without any border chrome: the title (if any), body, optional
    /// footer separator, and footer are emitted at full width with no top/bottom
    /// border rows and no side walls. Used by ``ContainerConfig/hasBorder`` ==
    /// `false` (e.g. `.listStyle(.plain)`), so a plain list reads as flush
    /// content with no box around it.
    ///
    /// Body and footer content already sit at column 0, so their overlays and
    /// hit-test regions shift only vertically (by the rows above them) — there is
    /// no left wall to step past.
    func renderBorderless(
        bodyBuffer: FrameBuffer,
        footerBuffer: FrameBuffer?,
        innerWidth: Int,
        borderColor: Color,
        context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        var lines: [String] = []

        // Pads a content line to the full inner width (no side walls).
        func padded(_ line: String) -> String {
            let used = line.strippedLength
            guard used < innerWidth else { return line }
            return line + asciiSpaces(innerWidth - used)
        }

        // Optional title line, rendered plainly (no border decoration) since
        // there is no top border to host it. Through `ClaimingRow`, like the
        // separator below, so a faded colour — the title's defaults to the accent,
        // which a faded tint fades — states its opaque spelling and claims its
        // alpha (§65).
        var titleRows = 0
        var chromeClaims: [OpacityRegion] = []
        if let titleText = title {
            var drawn = ClaimingRow()
            drawn.append(
                titleText, cells: titleText.strippedLength,
                ink: titleColor?.resolve(with: palette) ?? palette.accent)
            lines.append(padded(drawn.text))
            chromeClaims += drawn.claims
            titleRows = 1
        }

        // Body lines at full width.
        for line in bodyBuffer.lines { lines.append(padded(line)) }

        // Footer section (separator + footer lines), if present.
        var footerSeparatorRows = 0
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            if style.showFooterSeparator {
                var rule = ClaimingRow()
                rule.append(
                    String(repeating: "─", count: max(0, innerWidth)), cells: max(0, innerWidth),
                    ink: borderColor)
                chromeClaims += rule.claims.map { $0.shifted(byX: 0, y: lines.count) }
                lines.append(rule.text)
                footerSeparatorRows = 1
            }
            for line in footerBuf.lines { lines.append(padded(line)) }
        }

        var result = FrameBuffer(lines: lines, width: innerWidth, uniformWidth: true)
        // Content sits at column 0 (no wall), shifted down by the title rows.
        // The title comes before the body, and is drawn under its overflow;
        // the divider and the footer come after it, and are drawn over it.
        var carriedOverlays = carriedBodyOverlays(
            bodyBuffer, footer: footerBuffer, separatorRows: footerSeparatorRows, shiftedByX: 0, y: titleRows)
        var carriedRuns = bodyBuffer.shiftedAnimatedCells(byX: 0, y: titleRows)
        var carriedRegions = bodyBuffer.shiftedHitTestRegions(byX: 0, y: titleRows)
        var carriedOpacity = bodyBuffer.shiftedOpacityRegions(byX: 0, y: titleRows)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            let footerRow = titleRows + bodyBuffer.lines.count + footerSeparatorRows
            carriedOverlays += footerBuf.shiftedOverlays(byX: 0, y: footerRow)
            carriedRegions += footerBuf.shiftedHitTestRegions(byX: 0, y: footerRow)
            carriedRuns += footerBuf.shiftedAnimatedCells(byX: 0, y: footerRow)
            carriedOpacity += footerBuf.shiftedOpacityRegions(byX: 0, y: footerRow)
        }
        result.overlays = carriedOverlays
        // The divider is drawn over what the body above it and the footer
        // below it draw past their regions, as the bordered box's is.
        if footerSeparatorRows > 0 {
            result.coverOverflow(underRects: [(x: 0, y: titleRows + bodyBuffer.lines.count, width: innerWidth, height: 1)])
        }
        result.hitTestRegions = carriedRegions
        result.animatedCells = carriedRuns
        // The fourth payload. This rebuilds with a bare `FrameBuffer(lines:)`,
        // so anything not re-attached here is simply gone — and the title and the
        // separator, drawn here, add their own.
        result.opacityRegions = carriedOpacity + chromeClaims
        return result
    }
}
