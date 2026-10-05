//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollOverflow.swift
//
//  A scroll view's content drawn past its bounds (`scrollClipDisabled`), and
//  the one rule that places it in the stacking order: it draws over what came
//  before the scroll view and under what comes after it, at the scroll view's
//  own z position, as SwiftUI's does.
//
//  Created by Wade Tregaskis
//  License: MIT

extension OverlayLayer {
    /// What is left of this layer once the rect `x`, `y`, `width` × `height` of
    /// its carrier is covered: the parts of it outside the rect, as up to four
    /// layers — above it, below it, and beside it either way.
    ///
    /// Each part is cut with everything that rides on its cells — hit regions,
    /// animated runs, opacity regions — so a covered cell is neither drawn nor
    /// clicked. A layer that the rect misses comes back whole; a layer with no
    /// cells at all comes back as nothing, since whatever rides on it names
    /// cells it does not draw.
    package func excluding(x: Int, y: Int, width: Int, height: Int) -> [OverlayLayer] {
        guard content.width > 0, content.height > 0 else { return [] }
        let right = offsetX + content.width
        let bottom = offsetY + content.height
        guard width > 0, height > 0, x < right, x + width > offsetX, y < bottom, y + height > offsetY
        else { return [self] }
        var parts: [OverlayLayer] = []
        func keep(_ partX: Int, _ partY: Int, _ partWidth: Int, _ partHeight: Int) {
            guard partWidth > 0, partHeight > 0 else { return }
            if let part = cropped(x: partX, y: partY, width: partWidth, height: partHeight) {
                parts.append(part)
            }
        }
        let bandTop = max(offsetY, y)
        let bandBottom = min(bottom, y + height)
        keep(offsetX, offsetY, content.width, y - offsetY)
        keep(offsetX, y + height, content.width, bottom - (y + height))
        keep(offsetX, bandTop, x - offsetX, bandBottom - bandTop)
        keep(x + width, bandTop, right - (x + width), bandBottom - bandTop)
        return parts
    }

    /// This layer as the cells it paints (``String/paintedColumns()``): on each
    /// line, from its first painted cell to its last, with the unstyled blank
    /// cells either side of them left out — and every payload that rides on
    /// the lines (hit regions, opacity regions, animated runs) cut to the cells
    /// kept, so a cell the layer does not draw is neither clicked nor faded
    /// through it. As parts: one for each run of lines that start at the same
    /// column, its lines ragged at their ends. A line that paints nothing is
    /// left out whole.
    ///
    /// For a layer drawn OVER other content, where compositing is opaque per
    /// cell: a scroll view's content past its bounds
    /// (``isScrollOverflow``), whose short or indented lines must not erase,
    /// or take the clicks of, what is beside them.
    package func drawnParts() -> [OverlayLayer] {
        let painted = content.lines.map { $0.paintedColumns() }
        var parts: [OverlayLayer] = []
        var row = 0
        while row < painted.count {
            guard let lead = painted[row]?.lowerBound else {
                row += 1
                continue
            }
            var ends: [Int] = []
            var next = row
            while next < painted.count, let columns = painted[next], columns.lowerBound == lead {
                ends.append(columns.upperBound - lead)
                next += 1
            }
            let part = cropped(
                x: offsetX + lead, y: offsetY + row, width: ends.max() ?? 0, height: next - row)
            if let part { parts.append(part.cut(toLineEnds: ends)) }
            row = next
        }
        return parts
    }

    /// This layer with each line `index` cut to its first `ends[index]`
    /// columns, and every payload with it — ``drawnParts()``'s ragged edge.
    /// The lines past each end are unstyled blanks, so the cut is the trailing
    /// trim; the payloads are cut row by row, a region over several rows split
    /// where the ends differ.
    private func cut(toLineEnds ends: [Int]) -> OverlayLayer {
        var part = self
        part.content = content.trimmingTrailingBlankCells()
        part.content.hitTestRegions = Self.cut(
            content.hitTestRegions, toLineEnds: ends,
            rows: { $0.offsetY..<($0.offsetY + $0.height) },
            clip: { $0.clipped(toColumns: $1, rows: $2) })
        part.content.opacityRegions = Self.cut(
            content.opacityRegions, toLineEnds: ends,
            rows: { $0.offsetY..<($0.offsetY + $0.height) },
            clip: { $0.clipped(toColumns: $1, rows: $2) })
        part.content.animatedCells = content.animatedCells.compactMap { run in
            guard ends.indices.contains(run.offsetY) else { return nil }
            return run.clipped(toColumns: 0..<ends[run.offsetY])
        }
        return part
    }

    /// `regions` cut to the first `ends[row]` columns of each row they cover:
    /// one piece for each run of rows whose ends agree.
    private static func cut<Region>(
        _ regions: [Region], toLineEnds ends: [Int], rows: (Region) -> Range<Int>,
        clip: (Region, Range<Int>, Range<Int>) -> Region?
    ) -> [Region] {
        var pieces: [Region] = []
        for region in regions {
            let covered = rows(region).clamped(to: 0..<ends.count)
            var row = covered.lowerBound
            while row < covered.upperBound {
                var next = row + 1
                while next < covered.upperBound, ends[next] == ends[row] { next += 1 }
                if let piece = clip(region, 0..<ends[row], row..<next) { pieces.append(piece) }
                row = next
            }
        }
        return pieces
    }

    /// This layer cut to the rect `x`, `y`, `width` × `height` of its carrier,
    /// or `nil` when nothing of it is there. The cut is ``clipped(toWidth:height:)``'s
    /// in the rect's own coordinates, with every payload trimmed to the cells
    /// that survive: that clip keeps the regions past a trailing edge, which
    /// is right for a container's clamp and wrong here, where the cells past
    /// it belong to another part.
    private func cropped(x: Int, y: Int, width: Int, height: Int) -> OverlayLayer? {
        guard var part = shifted(byX: -x, y: -y).clipped(toWidth: width, height: height) else {
            return nil
        }
        let columns = 0..<part.content.width
        let rows = 0..<part.content.height
        part.content.hitTestRegions = part.content.hitTestRegions.compactMap {
            $0.clipped(toColumns: columns, rows: rows)
        }
        part.content.opacityRegions = part.content.opacityRegions.compactMap {
            $0.clipped(toColumns: columns, rows: rows)
        }
        part.content.animatedCells = part.content.animatedCells.compactMap { run in
            guard rows.contains(run.offsetY) else { return nil }
            return run.clipped(toColumns: columns)
        }
        return part.shifted(byX: x, y: y)
    }
}

extension FrameBuffer {
    /// Cuts the scroll overflow this buffer carries (``OverlayLayer/isScrollOverflow``)
    /// away beneath content composed AFTER it — `later`, placed at `position`
    /// — where that content paints.
    ///
    /// SwiftUI draws a scroll view's unclipped content at the scroll view's own
    /// z position: over what came before it, under what comes after it
    /// (measured on macOS 15: a sibling below the scroll view in a `VStack`
    /// hides the content that runs down into it, while the content that runs
    /// up over the sibling above is drawn over it). Here every layer is
    /// composited at the screen root, over all the in-flow content, so the
    /// first half comes for free and the second is this: the combining
    /// operations that place later content — a stack's next child, a
    /// composited overlay — cut the earlier overflow out from under it.
    ///
    /// Under the cells it PAINTS (``String/paintedColumns()``): on each line,
    /// from its first painted cell to its last. The unstyled blank space either
    /// side is not the later view drawing — it is a stack's alignment padding,
    /// an overlay's `Spacer`, an `.offset` view's footprint — and SwiftUI shows
    /// the overflow through it. Cut by its whole rect, a short `Text` padded to
    /// its stack's width hid every overflowing line it sat on.
    ///
    /// Costs one test of ``overlays`` on every combining operation, and
    /// nothing more unless a scroll view has disabled its clip.
    package mutating func coverScrollOverflow(under later: FrameBuffer, at position: (x: Int, y: Int)) {
        guard !overlays.isEmpty else { return }
        overlays = Self.coveringScrollOverflow(overlays, under: later, at: position)
    }

    /// `layers` with the scroll overflow among them cut away where `later`,
    /// placed at `position`, paints — see
    /// ``coverScrollOverflow(under:at:)``. `layers` itself when there is
    /// none, which is almost always.
    package static func coveringScrollOverflow(
        _ layers: [OverlayLayer], under later: FrameBuffer, at position: (x: Int, y: Int)
    ) -> [OverlayLayer] {
        guard !layers.isEmpty, layers.contains(where: \.isScrollOverflow) else { return layers }
        var covered = layers
        for block in later.paintedBlocks() {
            covered = covered.flatMap { layer -> [OverlayLayer] in
                guard layer.isScrollOverflow else { return [layer] }
                return layer.excluding(
                    x: position.x + block.columns.lowerBound, y: position.y + block.rows.lowerBound,
                    width: block.columns.count, height: block.rows.count)
            }
        }
        return covered
    }

    /// The cells this buffer paints (``String/paintedColumns()``), as blocks
    /// of consecutive lines whose painted columns agree — one rect for a block
    /// of text the same width, one a line for ragged text.
    func paintedBlocks() -> [(rows: Range<Int>, columns: Range<Int>)] {
        var blocks: [(rows: Range<Int>, columns: Range<Int>)] = []
        for (row, line) in lines.enumerated() {
            guard let columns = line.paintedColumns() else { continue }
            if let last = blocks.last, last.rows.upperBound == row, last.columns == columns {
                blocks[blocks.count - 1].rows = last.rows.lowerBound..<(row + 1)
            } else {
                blocks.append((rows: row..<(row + 1), columns: columns))
            }
        }
        return blocks
    }
}
