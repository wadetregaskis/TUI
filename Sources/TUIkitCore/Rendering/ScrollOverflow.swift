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
    /// clicked. A layer that the rect misses comes back whole.
    package func excluding(x: Int, y: Int, width: Int, height: Int) -> [OverlayLayer] {
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
    /// away where content composed AFTER it lands — the rect `x`, `y`,
    /// `width` × `height`.
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
    /// Costs one test of ``overlays`` on every combining operation, and
    /// nothing more unless a scroll view has disabled its clip.
    package mutating func coverScrollOverflow(x: Int, y: Int, width: Int, height: Int) {
        guard !overlays.isEmpty else { return }
        overlays = Self.coveringScrollOverflow(overlays, x: x, y: y, width: width, height: height)
    }

    /// ``coverScrollOverflow(x:y:width:height:)`` for `later`, placed at
    /// `position`: the rect it covers is its own.
    package mutating func coverScrollOverflow(under later: FrameBuffer, at position: (x: Int, y: Int)) {
        guard !overlays.isEmpty else { return }
        coverScrollOverflow(x: position.x, y: position.y, width: later.width, height: later.lines.count)
    }

    /// `layers` with the scroll overflow among them cut away under `later`,
    /// placed at `position` — see ``coverScrollOverflow(x:y:width:height:)``.
    package static func coveringScrollOverflow(
        _ layers: [OverlayLayer], under later: FrameBuffer, at position: (x: Int, y: Int)
    ) -> [OverlayLayer] {
        coveringScrollOverflow(
            layers, x: position.x, y: position.y, width: later.width, height: later.lines.count)
    }

    /// `layers` with the scroll overflow among them cut away where the rect
    /// `x`, `y`, `width` × `height` is covered — see
    /// ``coverScrollOverflow(x:y:width:height:)``. `layers` itself when there is
    /// none, which is almost always.
    package static func coveringScrollOverflow(
        _ layers: [OverlayLayer], x: Int, y: Int, width: Int, height: Int
    ) -> [OverlayLayer] {
        guard !layers.isEmpty, width > 0, height > 0, layers.contains(where: \.isScrollOverflow)
        else { return layers }
        return layers.flatMap {
            $0.isScrollOverflow ? $0.excluding(x: x, y: y, width: width, height: height) : [$0]
        }
    }
}
