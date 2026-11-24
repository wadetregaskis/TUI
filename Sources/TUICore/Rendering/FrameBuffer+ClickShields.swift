//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+ClickShields.swift
//
//  A layer drawn over a control takes the control's clicks where it draws. In
//  SwiftUI a later layer of a `ZStack` — a "busy" scrim, a label, a badge — is
//  what a click on it hits, so the button under it never hears the click, and
//  `.allowsHitTesting(false)` on the layer is how to let it through; a layer
//  that draws nothing there (`Color.clear`, `.opacity(0)`, a frame's empty
//  padding) lets it through as well (measured:
//  `Tools/SwiftUIProbes/Layers over a control (H-68)/covered.out`; owner
//  ruling O-10 (a), 2026-11-21). So a compositor inside the tree files a CLICK
//  SHIELD over each control of its base, under the cells the layer draws, and
//  the mouse dispatcher keeps a press there from the control. The control's
//  own region is left whole: hover, the wheel and a drop still reach it, and
//  the keyboard is untouched.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What compositing a layer over a buffer does to the clicks of the buffer's
/// controls (``FrameBuffer/clickShielding(under:at:)``), worked out before the
/// composite and filed on it after (``FrameBuffer/fileClickShielding(_:)``).
package struct ClickShielding {
    /// The shields the layer files over the base's controls, in the base's
    /// coordinates.
    let shields: [HitTestRegion]

    /// Every click passage the composite carries, re-cut, or `nil` when
    /// neither side carried one.
    let passages: [HitTestRegion]?
}

extension FrameBuffer {
    /// For each of the first ``width`` columns of row `row`, whether a click
    /// there is this buffer's — something drawn in it that a hit lands on.
    ///
    /// A cell that shows something of its own (a glyph, a field, reverse
    /// video, an underline: not ``String/columnsShowingNothing(width:)``), and
    /// every cell of a `Text`'s frame, spaces included, where its frame is
    /// filed (`HitTestRegion.HandlerID.textFrame`), as SwiftUI hits a text
    /// anywhere in its bounds. Less what is drawn at no opacity at all: a
    /// cell under a fade to zero (`.opacity(0)`), and a blank cell whose
    /// field is a colour of no alpha (`Color.clear`, which is drawn as a
    /// field claimed at zero); and less a cell drawn by a view that takes no
    /// clicks (``HitTestRegion/HandlerID/clickPassage``).
    ///
    /// - Parameter row: The row, in this buffer's coordinates.
    /// - Returns: One entry per column, `true` where a click is this buffer's.
    package func columnsTakingClicks(onRow row: Int) -> [Bool] {
        guard lines.indices.contains(row), width > 0 else { return [] }
        var mask = lines[row].columnsShowingNothing(width: width).map { !$0 }
        func set(_ value: Bool, from start: Int, width span: Int, unless keep: [Bool]? = nil) {
            let lower = Swift.max(0, start)
            let upper = Swift.min(mask.count, start + span)
            guard lower < upper else { return }
            for column in lower..<upper where keep.map({ !$0[column] }) ?? true { mask[column] = value }
        }
        let claims = opacityRegions.filter { $0.spans(row: row) }
        // A field of no alpha shows nothing where no glyph is drawn on it.
        if claims.contains(where: \.hasInvisibleField) {
            let glyphs = lines[row].columnsDrawingNoGlyph(width: width).map { !$0 }
            for claim in claims where claim.hasInvisibleField {
                set(false, from: claim.offsetX, width: claim.width, unless: glyphs)
            }
        }
        for region in hitTestRegions where region.isTextFrame && region.spans(row: row) {
            set(true, from: region.offsetX, width: region.width)
        }
        for claim in claims where claim.isInvisible {
            set(false, from: claim.offsetX, width: claim.width)
        }
        for region in hitTestRegions where region.isClickPassage && region.spans(row: row) {
            set(false, from: region.offsetX, width: region.width)
        }
        return mask
    }

    /// What compositing `layer` over this buffer at `position` does to the
    /// clicks of this buffer's controls: a shield over each control under the
    /// cells the layer takes clicks on (``columnsTakingClicks(onRow:)``), and
    /// the click passages of both sides, each cut where the other takes
    /// clicks — a passage says nothing here takes a click, which a layer
    /// drawn over it, or a base drawn under it, can make untrue. `nil` when
    /// it does nothing, which is a base with no control under the layer and
    /// no passage on either side: nearly every composite.
    ///
    /// - Parameters:
    ///   - layer: The layer about to be composited, as it was drawn.
    ///   - position: Where it lands, in this buffer's cells.
    /// - Returns: What to file on the composite, or `nil`.
    package func clickShielding(under layer: Self, at position: (x: Int, y: Int)) -> ClickShielding? {
        guard !layer.isEmpty, !hitTestRegions.isEmpty || !layer.hitTestRegions.isEmpty else { return nil }
        let rows = position.y..<(position.y + layer.lines.count)
        let columns = position.x..<(position.x + layer.width)
        var layerMasks: [Int: [Bool]] = [:]
        // Whether the layer takes a click at a cell of this buffer.
        func layerTakes(_ row: Int, _ column: Int) -> Bool {
            guard rows.contains(row), columns.contains(column) else { return false }
            let mask: [Bool]
            if let known = layerMasks[row] {
                mask = known
            } else {
                mask = layer.columnsTakingClicks(onRow: row - position.y)
                layerMasks[row] = mask
            }
            let index = column - position.x
            return index < mask.count && mask[index]
        }
        var shields: [HitTestRegion] = []
        for target in hitTestRegions where target.takesClicks {
            let rect = (
                x: Swift.max(target.offsetX, columns.lowerBound), y: Swift.max(target.offsetY, rows.lowerBound),
                right: Swift.min(target.offsetX + target.width, columns.upperBound),
                bottom: Swift.min(target.offsetY + target.height, rows.upperBound))
            guard rect.x < rect.right, rect.y < rect.bottom else { continue }
            for piece in Self.rectangles(
                columns: rect.x..<rect.right, rows: rect.y..<rect.bottom, where: layerTakes)
            {
                shields.append(
                    HitTestRegion(
                        offsetX: piece.x, offsetY: piece.y, width: piece.width, height: piece.height,
                        handlerID: .clickShield(over: target.handlerID)))
            }
        }
        guard hitTestRegions.contains(where: \.isClickPassage) || layer.hitTestRegions.contains(where: \.isClickPassage)
        else { return shields.isEmpty ? nil : ClickShielding(shields: shields, passages: nil) }
        var baseMasks: [Int: [Bool]] = [:]
        // Whether this buffer takes a click at one of its cells.
        func baseTakes(_ row: Int, _ column: Int) -> Bool {
            let mask: [Bool]
            if let known = baseMasks[row] {
                mask = known
            } else {
                mask = columnsTakingClicks(onRow: row)
                baseMasks[row] = mask
            }
            return column >= 0 && column < mask.count && mask[column]
        }
        var passages: [HitTestRegion] = []
        func cut(_ passage: HitTestRegion, keeping keep: (Int, Int) -> Bool) {
            for piece in Self.rectangles(
                columns: passage.offsetX..<(passage.offsetX + passage.width),
                rows: passage.offsetY..<(passage.offsetY + passage.height), where: keep)
            {
                passages.append(.clickPassage(x: piece.x, y: piece.y, width: piece.width, height: piece.height))
            }
        }
        for passage in hitTestRegions where passage.isClickPassage { cut(passage) { !layerTakes($0, $1) } }
        for passage in layer.hitTestRegions where passage.isClickPassage {
            cut(passage.shifted(byX: position.x, y: position.y)) { !baseTakes($0, $1) }
        }
        return ClickShielding(shields: shields, passages: passages)
    }

    /// Files `shielding` (``clickShielding(under:at:)``) on this buffer, the
    /// composite it was worked out for: its shields added, and its passages
    /// in place of the ones the composite carried.
    package mutating func fileClickShielding(_ shielding: ClickShielding?) {
        guard let shielding else { return }
        if let passages = shielding.passages {
            hitTestRegions.removeAll(where: \.isClickPassage)
            hitTestRegions.append(contentsOf: passages)
        }
        hitTestRegions.append(contentsOf: shielding.shields)
    }

    /// The cells of `columns` × `rows` where `included(row, column)`, as
    /// rectangles: each row's runs, a run joined to the one above it where
    /// the two span the same columns.
    package static func rectangles(
        columns: Range<Int>, rows: Range<Int>, where included: (Int, Int) -> Bool
    ) -> [(x: Int, y: Int, width: Int, height: Int)] {
        var done: [(x: Int, y: Int, width: Int, height: Int)] = []
        // The runs still open, by their columns: where each began.
        var open: [Range<Int>: Int] = [:]
        for row in rows {
            var runs: [Range<Int>] = []
            var start: Int?
            for column in columns {
                if included(row, column) {
                    if start == nil { start = column }
                } else if let begun = start {
                    runs.append(begun..<column)
                    start = nil
                }
            }
            if let begun = start { runs.append(begun..<columns.upperBound) }
            for (run, top) in open where !runs.contains(run) {
                done.append((run.lowerBound, top, run.count, row - top))
                open[run] = nil
            }
            for run in runs where open[run] == nil { open[run] = row }
        }
        for (run, top) in open { done.append((run.lowerBound, top, run.count, rows.upperBound - top)) }
        // In reading order: the open runs are a dictionary's, and a buffer's
        // regions are compared whole (the memo verifier, a kept composite).
        return done.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }
}

extension HitTestRegion {
    /// A click passage (``HandlerID/clickPassage``) over the given cells.
    package static func clickPassage(x: Int, y: Int, width: Int, height: Int) -> Self {
        Self(offsetX: x, offsetY: y, width: width, height: height, handlerID: .clickPassage)
    }

    /// Whether this region covers any cell of row `row`.
    func spans(row: Int) -> Bool {
        row >= offsetY && row < offsetY + height
    }
}

extension OpacityRegion {
    /// Whether this claim leaves its cells showing nothing at all: no
    /// opacity, so the cells are not drawn, on a fade that is not repeating
    /// (whose other phases are).
    var isInvisible: Bool { cycle == nil && (opacity == 0 || (fieldOpacity == 0 && inkOpacity == 0)) }

    /// Whether this claim leaves the field of its cells showing nothing: a
    /// colour of no alpha painted as a field (`Color.clear`), on a fade that
    /// is not repeating.
    var hasInvisibleField: Bool { cycle == nil && fieldOpacity == 0 }
}
