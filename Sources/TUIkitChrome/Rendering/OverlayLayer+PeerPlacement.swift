//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayLayer+PeerPlacement.swift
//
//  Panels drawn together, each beside the view it describes, placed so that
//  none covers another: the tooltips of `.tooltips(.always)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

extension OverlayLayer {
    /// `layers` with every peer panel (a layer with a
    /// ``OverlayLayer/peerPlacement``) moved to a place of its own, or removed
    /// when there is none. Every other layer comes back as it was, in its
    /// order.
    ///
    /// The panels are placed one at a time, in rank order and then in reading
    /// order of the views they describe (top to bottom, then left to right),
    /// so a page draws the same panels in the same places whatever order its
    /// views were emitted in. Each takes a place that:
    ///
    /// - is wholly inside the `maxWidth` × `maxHeight` area;
    /// - is beside its view: below or above it sharing at least one column, or
    ///   to its right or left sharing at least one row and no further from it
    ///   than the panel is wide, so it reads as that view's;
    /// - covers neither its own view (`Tooltips and help in a terminal.md` §5,
    ///   rule 3) nor a panel already placed;
    ///
    /// and of those, the one covering the fewest cells of the OTHER panels'
    /// views, then the fewest of the places the panels still to come would
    /// take first (directly below their views), then the first in §5's order:
    /// below, above, right, left, each nearest the spot aligned with the view.
    /// The look-ahead is what lets a column of one-row views keep every panel:
    /// without it the first panel took the right-hand side of the rows the
    /// second needed, and the second had nowhere left.
    ///
    /// A panel with no such place is dropped rather than drawn over another:
    /// the panels exist to be read, and two half-covered ones read worse than
    /// one whole. What decides which one goes is the order, which is why the
    /// caller ranks the view under the pointer and the focused one first: on a
    /// page too dense for every panel, pointing at a view, or focusing it,
    /// brings its own panel up.
    ///
    /// Not rule 4 (avoid the pointer) or rule 5 (re-wrap narrower before
    /// giving up): a panel arrives here drawn, and its text is not.
    ///
    /// A panel inside a view's displaced drawing — a layer at
    /// ``OverlayLayer/displacedDrawingZIndex``: `.offset`, `.position`, a
    /// transition on its way — is one of these too, and is placed with them,
    /// where its host will put it, and written back in the host's
    /// coordinates. Such a layer is the view's own cells drawn elsewhere, not
    /// a window over the page, and its panel rides in it until it composites:
    /// placed then, in a batch of its own, it knew nothing of the page's
    /// panels and the page's nothing of its view, so each could cover the
    /// other's. A presentation's panels are still placed among themselves,
    /// in the batch its content is lifted in.
    package static func arrangingPeers(
        _ layers: [OverlayLayer], maxWidth: Int, maxHeight: Int
    ) -> [OverlayLayer] {
        guard layers.contains(where: \.carriesPeers) else { return layers }
        var gathered: [Peer] = []
        Peer.gather(layers, path: [], originX: 0, originY: 0, maxWidth: maxWidth, maxHeight: maxHeight, into: &gathered)
        let peers = gathered.sorted(by: Peer.placedBefore)
        let area = CellRect(x: 0, y: 0, width: maxWidth, height: maxHeight)
        let views = peers.map(\.anchor)
        let wanted = peers.map { $0.firstChoice(in: area) }
        var arranged = layers
        var taken: [CellRect] = []
        var dropped = Set<[Int]>()
        for (position, peer) in peers.enumerated() {
            guard
                let spot = peer.bestSpot(
                    in: area, avoiding: taken, sparing: views,
                    thenSparing: wanted[(position + 1)...].compactMap { $0 })
            else {
                dropped.insert(peer.path)
                continue
            }
            taken.append(spot)
            Self.update(&arranged, at: peer.path[...]) { layer in
                // In the coordinates its offsets are in: its host's content,
                // for a panel carried in displaced drawing.
                layer.offsetX = spot.x - peer.originX
                layer.offsetY = spot.y - peer.originY
                // Placed where it fits, so the compositor has nothing to flip
                // it around; and placed, so a later batch does not place it
                // again.
                layer.anchorHeight = 0
                layer.peerPlacement = nil
            }
        }
        guard !dropped.isEmpty else { return arranged }
        return Self.removing(dropped, from: arranged, under: [])
    }

    /// Whether this layer is a panel of the set, or displaced drawing that
    /// carries one: what ``arrangingPeers(_:maxWidth:maxHeight:)`` looks
    /// for, so a frame with neither pays one scan of its layers.
    fileprivate var carriesPeers: Bool {
        peerPlacement != nil || (isDisplacedDrawing && content.overlays.contains(where: \.carriesPeers))
    }

    /// Whether this layer is a view's own drawing moved elsewhere rather than
    /// a surface presented over the page; see ``displacedDrawingZIndex``.
    fileprivate var isDisplacedDrawing: Bool {
        zIndex == Self.displacedDrawingZIndex
    }

    /// Where this layer's content will have its top-left cell once
    /// composited into a `maxWidth` × `maxHeight` area — the origin of the
    /// coordinates the layers it carries are in. A layer that clips at the
    /// screen's edge rather than moving back onto it keeps its offset there,
    /// since the cut moves what it carries by the cells it cuts
    /// (``placed(maxWidth:maxHeight:)``).
    fileprivate func contentOrigin(maxWidth: Int, maxHeight: Int) -> (x: Int, y: Int) {
        guard centered || clampsToScreen else { return (offsetX, offsetY) }
        let placed = placed(maxWidth: maxWidth, maxHeight: maxHeight)
        return (placed.x, placed.y)
    }

    /// Applies `change` to the layer at `path`: an index into `layers`, then
    /// into each displaced host's own layers.
    private static func update(
        _ layers: inout [OverlayLayer], at path: ArraySlice<Int>, _ change: (inout OverlayLayer) -> Void
    ) {
        guard let index = path.first else { return }
        if path.count == 1 {
            change(&layers[index])
        } else {
            update(&layers[index].content.overlays, at: path.dropFirst(), change)
        }
    }

    /// `layers`, at `prefix`, without the ones at the paths in `dropped`.
    private static func removing(_ dropped: Set<[Int]>, from layers: [OverlayLayer], under prefix: [Int])
        -> [OverlayLayer]
    {
        var kept: [OverlayLayer] = []
        for (index, layer) in layers.enumerated() {
            let path = prefix + [index]
            if dropped.contains(path) { continue }
            var layer = layer
            if layer.isDisplacedDrawing, dropped.contains(where: { $0.count > path.count && $0.starts(with: path) }) {
                layer.content.overlays = removing(dropped, from: layer.content.overlays, under: path)
            }
            kept.append(layer)
        }
        return kept
    }
}

/// One panel to place: where its view is, and how big it is.
private struct Peer {
    /// Where it is: its index in the caller's list, then in each displaced
    /// host's own layers.
    let path: [Int]
    /// ``OverlayLayer/PeerPlacement/rank``.
    let rank: Int
    /// The view it describes, in the area's coordinates.
    let anchor: CellRect
    let width: Int
    let height: Int
    /// Where the origin of its offsets is in the area: zero for a panel of
    /// the caller's list, its host's content origin for one carried.
    let originX: Int
    let originY: Int

    /// Rank, then reading order, then the caller's order.
    static func placedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if (lhs.rank, lhs.anchor.y, lhs.anchor.x) != (rhs.rank, rhs.anchor.y, rhs.anchor.x) {
            return (lhs.rank, lhs.anchor.y, lhs.anchor.x) < (rhs.rank, rhs.anchor.y, rhs.anchor.x)
        }
        return lhs.path.lexicographicallyPrecedes(rhs.path)
    }

    /// Appends the panels among `layers` to `peers`, and those carried in
    /// the displaced drawing among them, at any depth. `originX`/`originY`
    /// are where `layers`' offsets are measured from in the area.
    static func gather(
        _ layers: [OverlayLayer], path: [Int], originX: Int, originY: Int, maxWidth: Int, maxHeight: Int,
        into peers: inout [Self]
    ) {
        for (index, layer) in layers.enumerated() where layer.carriesPeers {
            if let placement = layer.peerPlacement {
                peers.append(
                    Self(
                        path: path + [index], rank: placement.rank,
                        anchor: CellRect(
                            x: originX + layer.offsetX, y: originY + layer.offsetY - layer.anchorHeight,
                            width: max(0, placement.anchorWidth), height: max(0, layer.anchorHeight)),
                        // As `placed(maxWidth:maxHeight:)` will clamp the content.
                        width: min(layer.content.width, maxWidth), height: min(layer.content.height, maxHeight),
                        originX: originX, originY: originY))
                continue
            }
            // Displaced drawing carrying panels: placed where its host's
            // composite will lift it, which is its own offset from there.
            var lifted = layer
            lifted.offsetX += originX
            lifted.offsetY += originY
            let origin = lifted.contentOrigin(maxWidth: maxWidth, maxHeight: maxHeight)
            gather(
                layer.content.overlays, path: path + [index], originX: origin.x, originY: origin.y,
                maxWidth: maxWidth, maxHeight: maxHeight, into: &peers)
        }
    }

    /// The place this panel would take with nothing else on the page: what a
    /// panel placed before it should leave free if it can.
    func firstChoice(in area: CellRect) -> CellRect? {
        candidates(in: area).first { !$0.overlaps(anchor) }
    }

    /// The place, of those clear of the view and of `taken`, covering the
    /// fewest cells of `views`, then of `later`, then first in preference
    /// order; `nil` when every place is blocked.
    func bestSpot(
        in area: CellRect, avoiding taken: [CellRect], sparing views: [CellRect],
        thenSparing later: [CellRect]
    ) -> CellRect? {
        guard width > 0, height > 0 else { return nil }
        var best: (spot: CellRect, cost: (Int, Int))?
        for spot in candidates(in: area) {
            guard !spot.overlaps(anchor), !taken.contains(where: spot.overlaps) else { continue }
            // Its own view counts nothing: a spot that overlaps it was refused.
            let covered = views.reduce(0) { $0 + spot.overlapArea(with: $1) }
            if let best, covered > best.cost.0 { continue }
            let cost = (covered, later.reduce(0) { $0 + spot.overlapArea(with: $1) })
            if cost == (0, 0) { return spot }
            if best.map({ cost < $0.cost }) ?? true { best = (spot, cost) }
        }
        return best?.spot
    }

    /// Every place to try that lies inside `area`, in preference order: below,
    /// above, right, left. Below and above, nearest the spot aligned with the
    /// view's leading edge first, sliding right before left; to a side,
    /// nearest the view first, then nearest the spot aligned with its top,
    /// sliding down before up.
    private func candidates(in area: CellRect) -> [CellRect] {
        var spots: [CellRect] = []
        let columns = Self.slides(
            from: anchor.x, lowest: max(0, anchor.x - width + 1),
            highest: min(area.maxX - width, max(anchor.x, anchor.maxX - 1)))
        for y in [anchor.maxY, anchor.y - height] where y >= 0 && y + height <= area.maxY {
            spots += columns.map { CellRect(x: $0, y: y, width: width, height: height) }
        }
        let rows = Self.slides(
            from: anchor.y, lowest: max(0, anchor.y - height + 1),
            highest: min(area.maxY - height, max(anchor.y, anchor.maxY - 1)))
        // At most a panel's width from the view: further out, it no longer
        // reads as the view's.
        let right = anchor.maxX...max(anchor.maxX, min(area.maxX - width, anchor.maxX + width))
        let left = stride(from: anchor.x - width, through: max(0, anchor.x - 2 * width), by: -1)
        for x in Array(right) + Array(left) where x >= 0 && x + width <= area.maxX {
            spots += rows.map { CellRect(x: x, y: $0, width: width, height: height) }
        }
        return spots
    }

    /// `start` clamped into `lowest...highest`, then alternately one further
    /// up and one further down the range, until both ends are reached: the
    /// positions along a side, nearest first.
    static func slides(from start: Int, lowest: Int, highest: Int) -> [Int] {
        guard lowest <= highest else { return [] }
        let origin = min(max(start, lowest), highest)
        var positions = [origin]
        var step = 1
        while origin + step <= highest || origin - step >= lowest {
            if origin + step <= highest { positions.append(origin + step) }
            if origin - step >= lowest { positions.append(origin - step) }
            step += 1
        }
        return positions
    }
}

extension CellRect {
    /// Whether the two share a cell.
    fileprivate func overlaps(_ other: CellRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    /// How many cells the two share.
    fileprivate func overlapArea(with other: CellRect) -> Int {
        max(0, min(maxX, other.maxX) - max(x, other.x)) * max(0, min(maxY, other.maxY) - max(y, other.y))
    }
}
