//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+VerticalAlignment.swift
//
//  Created by LAYERED.work
//  License: MIT

extension FrameBuffer {
    /// Returns a copy padded with blank rows up to `height`, placing the
    /// existing content within that height according to `alignment`.
    ///
    /// Buffers already at least `height` tall are returned unchanged. Overlay
    /// layers and hit-test regions shift down with the content by the amount of
    /// top padding, so a click on a non-top-aligned child still lands on it.
    ///
    /// Shared by `HStack` and `LazyHStack`: both lay children out on the
    /// horizontal axis and must position each child within the row's height
    /// (`appendHorizontally` itself only ever top-aligns).
    func verticallyAligned(toHeight height: Int, alignment: VerticalAlignment) -> FrameBuffer {
        guard self.height < height else { return self }
        return placedVertically(
            inHeight: height,
            topPadding: alignment.childOffset(childHeight: self.height, in: height))
    }

    /// Returns a copy placed at an explicit vertical offset within `height`.
    ///
    /// The arithmetic ``verticallyAligned(toHeight:alignment:)`` performs, split
    /// out so a container that resolved the offset from an explicit
    /// ``View/alignmentGuide(_:computeValue:)-(VerticalAlignment,_)`` reuses the same padding
    /// and the same overlay/hit-region carry.
    package func placedVertically(inHeight height: Int, topPadding: Int) -> FrameBuffer {
        guard topPadding > 0 || self.height < height else { return self }
        let bottomPadding = max(0, height - self.height - topPadding)
        let emptyLine = String(repeating: " ", count: width)
        var lines = Array(repeating: emptyLine, count: topPadding)
        lines += self.lines
        lines += Array(repeating: emptyLine, count: bottomPadding)
        return replacingLines(lines, overlayShiftY: topPadding)
    }

    /// The vertical twin of
    /// ``placedHorizontallyDrawingOverhang(inWidth:offset:isMeasuring:)``: this
    /// buffer `topPadding` rows down a row `height` tall, what lies below the
    /// row's bottom edge drawn past it rather than left for a clamp to cut —
    /// and on a measure pass cut there, without first padding the column with
    /// as many blank rows as the push.
    func placedVerticallyDrawingOverhang(inHeight height: Int, topPadding: Int, isMeasuring: Bool) -> FrameBuffer {
        guard topPadding + self.height > height else {
            return placedVertically(inHeight: height, topPadding: topPadding)
        }
        guard !isMeasuring else {
            let height = max(0, height)
            return clamped(toWidth: width, height: max(0, height - topPadding))
                .placedVertically(inHeight: height, topPadding: min(topPadding, height))
        }
        let placement = splitPlacing(at: (x: 0, y: topPadding), inWidth: width, height: height)
        var inside = placement.insideCarryingOverflow
        if topPadding >= height {
            // Wholly past the edge: its column still stands in the row, blank.
            var blank = FrameBuffer(emptyWithWidth: width, height: 0)
            blank.hitTestRegions = inside.hitTestRegions
            blank.overlays = inside.overlays
            inside = blank
        }
        let placed = inside.placedVertically(inHeight: height, topPadding: placement.insideOrigin.y)
        // A row lays its columns out by their widths, and a cut keeps only the
        // width its lines draw: a column that declares more than it draws (a
        // footprint) would narrow and pull the columns after it left. Such a
        // column keeps the cut it always had.
        guard placed.width == width else { return placedVertically(inHeight: height, topPadding: topPadding) }
        return placed
    }
}
