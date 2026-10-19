//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Overflow.swift
//
//  Content drawn past its region — a scroll view's under `scrollClipDisabled`,
//  a view a guide places outside its frame, a transition's overshoot — and the
//  one rule that places it in the stacking order: it draws over what came
//  before its view and under what comes after it, at the view's own z
//  position, as SwiftUI's does.
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

    /// This layer as the cells it paints (``FrameBuffer/paintedColumnsByLine(inRows:)``):
    /// on each line, from its first painted cell to its last, with the unstyled
    /// blank cells either side of them left out — and every payload that rides on
    /// the lines (hit regions, opacity regions, animated runs) cut to the cells
    /// kept, so a cell the layer does not draw is neither clicked nor faded
    /// through it. As parts: one for each run of lines that start at the same
    /// column, its lines ragged at their ends. A line that paints nothing is
    /// left out whole.
    ///
    /// For a layer drawn OVER other content, where compositing is opaque per
    /// cell: content past its region (``isOverflow``), whose short or
    /// indented lines must not erase, or take the clicks of, what is beside
    /// them.
    package func drawnParts() -> [OverlayLayer] {
        let painted = content.paintedColumnsByLine()
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
    /// The cells past each end are unstyled blanks no run repaints; the
    /// payloads are cut row by row, a region over several rows split where the
    /// ends differ.
    private func cut(toLineEnds ends: [Int]) -> OverlayLayer {
        var part = self
        var lines = content.lines
        for index in lines.indices where index < ends.count {
            let width = lines[index].strippedLength
            guard ends[index] < width else { continue }
            lines[index] = lines[index].ansiAwarePrefix(visibleCount: ends[index], knownVisibleWidth: width)
        }
        part.content.lines = lines
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
    /// it belong to another part — or, for a container that keeps overflow
    /// inside a box of its own (a list's row, a table's cell), to nothing.
    package func cropped(x: Int, y: Int, width: Int, height: Int) -> OverlayLayer? {
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
    /// Cuts the overflow this buffer carries (``OverlayLayer/isOverflow``)
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
    /// Under the cells it PAINTS (``paintedColumnsByLine(inRows:)``): on each line,
    /// from its first painted cell to its last. The unstyled blank space either
    /// side is not the later view drawing — it is a stack's alignment padding,
    /// an overlay's `Spacer`, an `.offset` view's footprint — and SwiftUI shows
    /// the overflow through it. Cut by its whole rect, a short `Text` padded to
    /// its stack's width hid every overflowing line it sat on.
    ///
    /// Costs a test of the hint ``overlaysAreFreeOfOverflow`` on every
    /// combining operation, a look at the layers when it does not know — after
    /// which it does — and nothing more unless something in the buffer draws
    /// past its region.
    package mutating func coverOverflow(under later: FrameBuffer, at position: (x: Int, y: Int)) {
        guard !overlays.isEmpty, !overlaysAreFreeOfOverflow else { return }
        guard overlays.contains(where: \.isOverflow) else {
            overlaysAreFreeOfOverflow = true
            return
        }
        overlays = Self.covering(overlays, under: later, at: position)
    }

    /// ``overlays`` with the overflow among them cut away where `later`,
    /// placed at `position`, paints — ``coverOverflow(under:at:)`` for a
    /// buffer that is not changed in place. ``overlays`` itself when there is
    /// none, which is almost always.
    package func overflowCovered(under later: FrameBuffer, at position: (x: Int, y: Int)) -> [OverlayLayer] {
        guard !overlays.isEmpty, !overlaysAreFreeOfOverflow, overlays.contains(where: \.isOverflow)
        else { return overlays }
        return Self.covering(overlays, under: later, at: position)
    }

    /// Whether ``overlays`` holds no overflow: the hint when it knows,
    /// a look otherwise.
    package var overlaysHoldNoOverflow: Bool {
        overlaysAreFreeOfOverflow || !overlays.contains(where: \.isOverflow)
    }

    /// Appends `other`'s layers, shifted by (`dx`, `dy`), saying what is known
    /// about overflow after: none, when there was none before and
    /// `other` has none. The combining operations' one way to lift layers, so
    /// the hint survives the append that would otherwise make it unknown.
    package mutating func appendOverlays(of other: FrameBuffer, shiftedByX dx: Int, y dy: Int) {
        guard !other.overlays.isEmpty else { return }
        let free = (overlays.isEmpty || overlaysAreFreeOfOverflow) && other.overlaysHoldNoOverflow
        overlays.append(contentsOf: other.shiftedOverlays(byX: dx, y: dy))
        overlaysAreFreeOfOverflow = free
    }

    /// Cuts the overflow this buffer carries (``OverlayLayer/isOverflow``)
    /// away beneath `rects` of it: chrome a container draws by hand around
    /// content it composed, rather than through a combining operation —
    /// a border's rules, a footer's divider. SwiftUI draws a border over what
    /// its content draws past its frame, and past the border the overflow is
    /// still drawn (measured; decisions-GUIDE3 B-GUIDE3-5).
    ///
    /// Nothing unless the buffer carries overflow, which is almost never.
    package mutating func coverOverflow(underRects rects: [(x: Int, y: Int, width: Int, height: Int)]) {
        guard !overlaysHoldNoOverflow else { return }
        var covered = overlays
        for rect in rects {
            covered = covered.flatMap { layer -> [OverlayLayer] in
                guard layer.isOverflow else { return [layer] }
                return layer.excluding(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            }
        }
        overlays = covered
    }

    /// Cuts the overflow this buffer carries under a border drawn by hand
    /// around its content (``coverOverflow(underRects:)``): its top `topRows`
    /// rows — a rule, or a strip of tabs that ends in one — its bottom row,
    /// the columns either side of an `innerWidth`-wide inside, and a divider
    /// across at `dividerRow` when it has one. Past them it is still drawn.
    ///
    /// Nothing unless the buffer carries overflow, which is almost never.
    package mutating func coverOverflowUnderBorder(innerWidth: Int, topRows: Int = 1, dividerRow: Int? = nil) {
        guard !overlaysHoldNoOverflow else { return }
        let rows = height
        var rules = [
            (x: 0, y: 0, width: width, height: topRows), (x: 0, y: rows - 1, width: width, height: 1),
            (x: 0, y: 0, width: 1, height: rows), (x: innerWidth + 1, y: 0, width: 1, height: rows),
        ]
        if let dividerRow { rules.append((x: 0, y: dividerRow, width: width, height: 1)) }
        coverOverflow(underRects: rules)
    }

    /// `layers` with the overflow among them cut away where `later`,
    /// placed at `position`, paints.
    ///
    /// Only `later`'s lines that some overflow reaches are read for what they
    /// paint (``overflowReach(of:over:at:)``): a line's painted cells are a
    /// scan of its text, and the view after an overflowing one is often a
    /// page of lines the overflow never reaches — an `.offset` view's cells
    /// drawn a column aside, over nothing below them, cost `geometry` a scan
    /// of the scroll view under it on every frame. The cut is the same: a
    /// block of lines outside the reach meets no overflow, and one cut to it
    /// meets every overflow cell it met whole, which is all a cut reads.
    private static func covering(
        _ layers: [OverlayLayer], under later: FrameBuffer, at position: (x: Int, y: Int)
    ) -> [OverlayLayer] {
        guard let reach = overflowReach(of: layers, over: later, at: position) else { return layers }
        var covered = layers
        for block in later.paintedBlocks(inRows: reach) {
            covered = covered.flatMap { layer -> [OverlayLayer] in
                guard layer.isOverflow else { return [layer] }
                return layer.excluding(
                    x: position.x + block.columns.lowerBound, y: position.y + block.rows.lowerBound,
                    width: block.columns.count, height: block.rows.count)
            }
        }
        return covered
    }

    /// The lines of `later`, placed at `position`, that the overflow among
    /// `layers` reaches — from the first line any of it covers to the last,
    /// in `later`'s own rows — or `nil` where none reaches `later` at all.
    ///
    /// Every line where an overflow layer has no cells: any cut drops such a
    /// layer (``OverlayLayer/excluding(x:y:width:height:)``), so whether it
    /// stays turns on whether `later` paints anything at all.
    private static func overflowReach(
        of layers: [OverlayLayer], over later: FrameBuffer, at position: (x: Int, y: Int)
    ) -> Range<Int>? {
        var reach: Range<Int>?
        for layer in layers where layer.isOverflow {
            guard layer.content.width > 0, layer.content.height > 0 else { return 0..<later.height }
            let top = max(0, layer.offsetY - position.y)
            let bottom = min(later.height, layer.offsetY + layer.content.height - position.y)
            guard top < bottom else { continue }
            reach = reach.map { min($0.lowerBound, top)..<max($0.upperBound, bottom) } ?? top..<bottom
        }
        return reach
    }

    /// Each line's painted columns (``String/paintedColumns()``), widened to
    /// the cells an animated run repaints on it — a caret blinking on a blank
    /// cell is drawn there, whatever the line holds under it. Only the lines
    /// in `rows` are read; every other is `nil`, as a line that paints
    /// nothing is.
    func paintedColumnsByLine(inRows rows: Range<Int>? = nil) -> [Range<Int>?] {
        let read = (rows ?? lines.indices).clamped(to: lines.indices)
        var painted = [Range<Int>?](repeating: nil, count: lines.count)
        for row in read { painted[row] = lines[row].paintedColumns() }
        for run in animatedCells where read.contains(run.offsetY) && run.width > 0 {
            let cells = run.offsetX..<(run.offsetX + run.width)
            painted[run.offsetY] =
                painted[run.offsetY].map {
                    min($0.lowerBound, cells.lowerBound)..<max($0.upperBound, cells.upperBound)
                } ?? cells
        }
        return painted
    }

    /// The cells this buffer paints (``paintedColumnsByLine(inRows:)``), as
    /// blocks of consecutive lines whose painted columns agree — one rect for
    /// a block of text the same width, one a line for ragged text — of the
    /// lines in `rows`, or all of them.
    func paintedBlocks(inRows rows: Range<Int>? = nil) -> [(rows: Range<Int>, columns: Range<Int>)] {
        var blocks: [(rows: Range<Int>, columns: Range<Int>)] = []
        for (row, painted) in paintedColumnsByLine(inRows: rows).enumerated() {
            guard let columns = painted else { continue }
            if let last = blocks.last, last.rows.upperBound == row, last.columns == columns {
                blocks[blocks.count - 1].rows = last.rows.lowerBound..<(row + 1)
            } else {
                blocks.append((rows: row..<(row + 1), columns: columns))
            }
        }
        return blocks
    }
}

// MARK: - Placing a view past its region

/// A view's drawing placed in a region it does not fit: what the region holds,
/// and what is drawn past it — ``FrameBuffer/splitPlacing(at:inWidth:height:)``.
package struct OverflowingPlacement {
    /// The part of the view inside the region, cut to it, to be drawn in flow
    /// at ``insideOrigin``. Every payload is cut with its cells, except the
    /// geometry markers, which every clip keeps whole; the view's own floating
    /// layers ride on it, moved so that they land where they would have.
    package var inside: FrameBuffer

    /// Where ``inside`` goes in the region: the view's position, held to the
    /// region's top-leading corner.
    package var insideOrigin: (x: Int, y: Int)

    /// The cells past the region, in the region's coordinates, as the cells
    /// they paint (``OverlayLayer/drawnParts()``) and marked
    /// ``OverlayLayer/isOverflow``: drawn over what came before the view and
    /// under what comes after it, with their hit regions, runs and opacity
    /// regions travelling with them.
    package var overflow: [OverlayLayer]

    /// ``inside`` carrying ``overflow`` among its floating layers, in its own
    /// coordinates, so the overflow lands where it was drawn wherever the
    /// caller places ``inside`` (at ``insideOrigin``).
    ///
    /// Ahead of the view's own floating layers, which draw over it: the
    /// overflow is the view's cells, and what the view floats — an `.offset`
    /// decoration, a deeper view's overflow — is drawn over its cells, past
    /// the region as in it. Appended after them, a badge's own `.offset`
    /// mark vanished under the badge's overflow, both at the same level and
    /// z index.
    package var insideCarryingOverflow: FrameBuffer {
        guard !overflow.isEmpty else { return inside }
        var carrier = inside
        carrier.overlays =
            overflow.map { $0.shifted(byX: -insideOrigin.x, y: -insideOrigin.y) } + inside.overlays
        return carrier
    }
}

extension FrameBuffer {
    /// Whether this buffer, placed at `position`, lies wholly inside a
    /// `width` × `height` region — the question a placement asks before it
    /// pays for ``splitPlacing(at:inWidth:height:)``.
    package func fits(at position: (x: Int, y: Int), inWidth width: Int, height: Int) -> Bool {
        position.x >= 0 && position.y >= 0 && position.x + self.width <= width
            && position.y + self.height <= height
    }

    /// This buffer placed at `position` in a `width` × `height` region it does
    /// not fit, as SwiftUI places a view: wherever the placement puts it, with
    /// no clip (Apple's documentation of `clipped(antialiased:)`: "By default,
    /// a view's bounding frame is used only for layout, so any content that
    /// extends beyond the edges of the frame is still visible").
    ///
    /// The part the region holds is drawn in flow; the rest becomes layers
    /// that draw past the region at the view's own place in the stacking order
    /// (``OverlayLayer/isOverflow``), as a scroll view's unclipped content
    /// does. Only the cells the view paints are drawn there, so a view's
    /// leading or trailing blanks erase nothing beside the region and take no
    /// clicks; its interior blanks are drawn, since a cell has no transparency.
    ///
    /// The caller asks ``fits(at:inWidth:height:)`` first: a view that fits
    /// takes the placement it always had, and pays nothing for this.
    package func splitPlacing(at position: (x: Int, y: Int), inWidth width: Int, height: Int)
        -> OverflowingPlacement
    {
        // The view's own floating layers travel whole, not cut with its cells:
        // they float free of the flow already.
        var bare = self
        bare.overlays = []
        var whole = OverlayLayer(
            offsetX: position.x, offsetY: position.y, content: bare, level: .popover,
            zIndex: OverlayLayer.displacedDrawingZIndex, clampsToScreen: false, isOpaque: false)
        whole.isOverflow = true
        let regionWidth = max(0, width)
        let regionHeight = max(0, height)
        let overflow = whole.excluding(x: 0, y: 0, width: regionWidth, height: regionHeight)
            .flatMap { $0.drawnParts() }

        var inside: FrameBuffer
        let origin: (x: Int, y: Int)
        if let part = whole.cropped(x: 0, y: 0, width: regionWidth, height: regionHeight) {
            inside = part.content
            origin = (x: part.offsetX, y: part.offsetY)
        } else {
            // Nothing of it is inside: the markers, which say where the view
            // begins, still ride in flow (the overflow's are never read).
            inside = FrameBuffer()
            inside.hitTestRegions = hitTestRegions.filter(\.isGeometryMarker)
            origin = (x: min(max(0, position.x), regionWidth), y: min(max(0, position.y), regionHeight))
            inside.hitTestRegions = inside.hitTestRegions.map {
                $0.shifted(byX: position.x - origin.x, y: position.y - origin.y)
            }
        }
        if !overlays.isEmpty {
            inside.overlays = shiftedOverlays(byX: position.x - origin.x, y: position.y - origin.y)
        }
        return OverflowingPlacement(inside: inside, insideOrigin: origin, overflow: overflow)
    }
}

// MARK: - Drawing a view past its slot

extension FrameBuffer {
    /// An empty footprint `width` × `height` — the slot the layout gave a view
    /// — with this buffer drawn `(offsetX, offsetY)` from its top-leading
    /// corner, past it: what a view hands back when what it draws stands
    /// outside the place it is laid out in. A spring transition's overshoot
    /// (`TransitionPicture.slotBuffer()`) and a matched geometry effect's view
    /// drawn at another view's frame both are.
    ///
    /// The picture is drawn as content past its region is
    /// (``splitPlacing(at:inWidth:height:)``): at the view's own place in the
    /// stacking order, over the views before it and under the views after it,
    /// as SwiftUI draws a view past its frame (measured for a frame, an
    /// overlay and a scale effect, decisions B-GUIDE-3). A terminal has no
    /// transparency, so the view paints nothing where it came from, as
    /// `View.offset(x:y:)` does.
    ///
    /// - **Only the cells it paints are drawn**, with the unstyled blanks at
    ///   either end of each line left out (`OverlayLayer.drawnParts()`), so a
    ///   slot-width row of padding erases none of a neighbour's cells as it
    ///   passes over them. Interior blanks still paint: a `Spacer` between two
    ///   labels covers what is under the gap for as long as the bounce lasts,
    ///   since a cell holds one glyph.
    /// - **Its hit regions travel with it**, cut with its cells: a click lands
    ///   on what is drawn where it lands. A later sibling cuts the picture
    ///   away beneath the cells it paints, its regions with it, so a peer
    ///   drawn over the bounce keeps its clicks — the reason these regions used
    ///   to stay in the slot, when the picture floated over every sibling.
    ///   The geometry markers stay in the slot, where the view is laid out.
    /// - **It does not slide back on screen.** `clampsToScreen` is the pop-over
    ///   policy: keep the whole layer visible by moving it. A view bouncing at
    ///   the right edge that jumped left instead is not the animation anyone
    ///   asked for, so this takes the pointer-anchored policy — stay put, lose
    ///   what falls off the edge.
    ///
    /// - Parameters:
    ///   - width: The slot's width, which the footprint declares.
    ///   - height: The slot's height, in rows the footprint reserves.
    ///   - offsetX: How far right of the slot's leading edge the picture
    ///     starts.
    ///   - offsetY: How far below the slot's top the picture starts.
    /// - Returns: The footprint, carrying the picture as layers drawn past it.
    package func drawnPastSlot(width: Int, height: Int, offsetX: Int, offsetY: Int) -> FrameBuffer {
        let placement = splitPlacing(at: (x: offsetX, y: offsetY), inWidth: 0, height: 0)
        var footprint = FrameBuffer(footprintWidth: width, height: height)
        footprint.hitTestRegions = hitTestRegions.filter(\.isGeometryMarker)
        // The picture first, then what it carries floating, which draws over it.
        footprint.overlays = placement.overflow + placement.inside.overlays
        return footprint
    }
}

// MARK: - Drawing parts of a view past its slot

extension FrameBuffer {
    /// A rect of a buffer, and how far it is drawn from where it is
    /// (``drawnPastSlot(moving:)``).
    package struct MovedPart: Equatable {
        package var x: Int
        package var y: Int
        package var width: Int
        package var height: Int
        package var dx: Int
        package var dy: Int

        package init(x: Int, y: Int, width: Int, height: Int, dx: Int, dy: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.dx = dx
            self.dy = dy
        }
    }

    /// An empty footprint the size of this buffer, with the buffer drawn past
    /// it: each of `parts` cut out and drawn its `(dx, dy)` from where it was,
    /// and the rest where it was — ``drawnPastSlot(width:height:offsetX:offsetY:)``
    /// for a picture of which only some views move, as a matched view leaving
    /// moves with the one arriving and what was drawn round it does not
    /// (`DepartureStore.carrying(_:leftFrom:)`).
    ///
    /// Drawn as that is, as content past its region: only the cells each
    /// piece paints, the moved parts over the rest. The buffer's own layers
    /// stay where they are, and its geometry markers stay in the footprint.
    package func drawnPastSlot(moving parts: [MovedPart]) -> FrameBuffer {
        var bare = self
        bare.overlays = []
        var whole = OverlayLayer(
            offsetX: 0, offsetY: 0, content: bare, level: .popover,
            zIndex: OverlayLayer.displacedDrawingZIndex, clampsToScreen: false, isOpaque: false)
        whole.isOverflow = true
        var staying = [whole]
        var moving: [OverlayLayer] = []
        for part in parts where part.width > 0 && part.height > 0 {
            if let cut = whole.cropped(x: part.x, y: part.y, width: part.width, height: part.height) {
                moving.append(cut.shifted(byX: part.dx, y: part.dy))
            }
            staying = staying.flatMap { $0.excluding(x: part.x, y: part.y, width: part.width, height: part.height) }
        }
        var footprint = FrameBuffer(footprintWidth: width, height: lines.count)
        footprint.hitTestRegions = hitTestRegions.filter(\.isGeometryMarker)
        footprint.overlays = (staying + moving).flatMap { $0.drawnParts() } + overlays
        return footprint
    }
}

// MARK: - Drawing a view displaced

extension FrameBuffer {
    /// This buffer drawn `offset` away from where it is laid out — `.offset`,
    /// `.position` — at its view's place in the stacking order: a footprint
    /// that draws nothing in flow (`footprintWidth` × `footprintHeight`, this
    /// buffer's own size where they are `nil`), with every cell this buffer
    /// paints drawn past it as overflow (``splitPlacing(at:inWidth:height:)``
    /// over a region of nothing), over the views before it and under the views
    /// after it, its hit regions travelling with the cells.
    ///
    /// Nothing is painted where the view was laid out, and only the cells it
    /// paints where it lands — the unstyled blanks at either end of each line
    /// are left out — since a cell has no transparency. Its geometry markers
    /// ride in the footprint, moved by `offset`, so a reader inside is
    /// answered where the view is drawn, as SwiftUI's offset moves a view's
    /// frame in every space; the overflow's own are never read. Its floating
    /// layers travel, moved by `offset`, drawn over its cells.
    package func drawnDisplaced(
        by offset: (x: Int, y: Int), footprintWidth: Int? = nil, footprintHeight: Int? = nil
    ) -> FrameBuffer {
        let placement = splitPlacing(at: offset, inWidth: 0, height: 0)
        var footprint = FrameBuffer(footprintWidth: footprintWidth ?? width, height: footprintHeight ?? height)
        footprint.hitTestRegions = placement.inside.hitTestRegions
        footprint.overlays = placement.overflow + placement.inside.overlays
        return footprint
    }
}
