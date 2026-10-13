//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+HorizontalAlignment.swift
//
//  Placing a child across a column: moved here from `_VStackCore`, so that a
//  view laying out a column of its own aligns its children by the same
//  arithmetic the stacks do.
//
//  Created by LAYERED.work
//  License: MIT

extension FrameBuffer {
    /// Returns a copy padded with blank columns up to `width`, placing the
    /// existing content within that width according to `alignment`.
    ///
    /// Buffers already at least `width` wide are returned unchanged. The column
    /// counterpart of ``verticallyAligned(toHeight:alignment:)``: how `VStack`
    /// and `LazyVStack` place each child across the column.
    func horizontallyAligned(toWidth width: Int, alignment: HorizontalAlignment) -> FrameBuffer {
        guard self.width < width else { return self }
        return placedHorizontally(
            inWidth: width, offset: alignment.childOffset(childWidth: self.width, in: width))
    }

    /// Places a buffer at an explicit horizontal offset within the given width.
    ///
    /// The arithmetic ``horizontallyAligned(toWidth:alignment:)`` performs, split out
    /// so a container that resolved the offset from an explicit
    /// ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)`` can reuse the same padding
    /// (and the same overlay/hit-region carry) instead of a second copy of it.
    func placedHorizontally(inWidth width: Int, offset: Int) -> FrameBuffer {
        let buffer = self
        guard offset > 0 || buffer.width < width else { return buffer }

        var alignedLines: [String] = []

        let bufferOffset = offset
        // A guide can push a child past the nominal width; the buffer must
        // still describe its own true extent, or `replacingLines`' uniform-width
        // promise below would be a lie the whole pipeline then trusts.
        let width = max(width, offset + buffer.width)

        let leftCount = bufferOffset
        let rightCount = max(0, width - bufferOffset - buffer.width)

        // When the input is already uniform every line is exactly `buffer.width`,
        // so the inner pad is empty — skip the per-line measure entirely. For a
        // ragged input (e.g. a column of word-wrapped `Text`) reuse the carried
        // per-line widths when present, falling back to `strippedLength` only when
        // they are unknown. This is the hot path for a `VStack` of wrapped text.
        //
        // Each aligned line is built in place: reserve `width` cells then append
        // the leading spaces, the line, the (ragged-only) inner pad, and the
        // trailing spaces — all borrowed from the shared spaces run, with no
        // `String(repeating:)` temporaries and no `+`-chain intermediates. The
        // byte sequence is identical to `leftPadding + paddedLine + rightPadding`.
        let inputIsUniform = buffer.linesAreUniformWidth
        let carriedWidths = buffer.lineWidths
        alignedLines.reserveCapacity(buffer.lines.count)
        for (index, line) in buffer.lines.enumerated() {
            let innerPad = inputIsUniform ? 0 : max(0, buffer.width - (carriedWidths?[index] ?? line.strippedLength))
            var aligned = ""
            aligned.reserveCapacity(line.utf8.count + leftCount + innerPad + rightCount)
            aligned += asciiSpaces(leftCount)
            aligned += line
            if innerPad > 0 { aligned += asciiSpaces(innerPad) }
            aligned += asciiSpaces(rightCount)
            alignedLines.append(aligned)
        }

        // Each aligned line is exactly `width` wide (leftPad + buffer.width +
        // rightPad), so hand that known width through — and flag it uniform — to
        // skip re-measuring every line in `replacingLines`. That re-measure was
        // ~32% of the AnyView-storm frame (a VStack aligning 500 rows), redundant
        // with the widths just used above. The content shifted right by
        // `bufferOffset`; carry overlay layers by the same amount so they stay
        // anchored.
        return buffer.replacingLines(
            alignedLines, width: width, uniformWidth: true,
            overlayShiftX: bufferOffset, overlayShiftY: 0)
    }

    /// This buffer placed `offset` columns along a column `width` wide, as
    /// ``placedHorizontally(inWidth:offset:)`` places it — except that what
    /// lies past the column's trailing edge is not left on the line for a
    /// clamp to cut, but drawn past the edge, at this view's place in the
    /// stacking order (``splitPlacing(at:inWidth:height:)``).
    ///
    /// For a run of explicit guides wider than the column that holds it: every
    /// guide stays on one line and the overhang is drawn past the edge, off
    /// the screen where the edge is the screen's, as SwiftUI's is past its
    /// window (decisions B-GUIDE-1). A buffer that fits takes
    /// ``placedHorizontally(inWidth:offset:)`` unchanged. A measure pass draws
    /// nothing past the edge: it keeps the part inside, as the clamp after it
    /// would cut the line, without first padding the line out to the push,
    /// which may be 2^20 cells (decisions B-GUIDE-2).
    func placedHorizontallyDrawingOverhang(inWidth width: Int, offset: Int, isMeasuring: Bool) -> FrameBuffer {
        guard offset + self.width > width else {
            return placedHorizontally(inWidth: width, offset: offset)
        }
        guard !isMeasuring else {
            let width = max(0, width)
            return clamped(toWidth: max(0, width - offset), height: height)
                .placedHorizontally(inWidth: width, offset: min(offset, width))
        }
        let placement = splitPlacing(at: (x: offset, y: 0), inWidth: width, height: height)
        var inside = placement.inside
        if offset >= width {
            // Wholly past the edge: its rows still stand in the column, blank.
            var blank = FrameBuffer(emptyWithWidth: 0, height: height)
            blank.hitTestRegions = inside.hitTestRegions
            blank.overlays = inside.overlays
            inside = blank
        }
        var placed = inside.placedHorizontally(inWidth: width, offset: placement.insideOrigin.x)
        // A column stacks its rows by their heights; a cut that lost a row
        // would pull the rows after it up. Such a row keeps the cut it always
        // had.
        guard placed.height == height else { return placedHorizontally(inWidth: width, offset: offset) }
        placed.overlays.append(contentsOf: placement.overflow)
        return placed
    }
}
