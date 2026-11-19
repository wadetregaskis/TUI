//  🖥️ TUI — A Terminal UI framework for Swift
//  LayerCompositeKeep.swift
//
//  The composites of an `.overlay`'s or a `.background`'s two layers, kept
//  from one frame to the next while a `TimelineView` is live, so that an entry
//  of a timeline drawn in one does not composite the view it is drawn with
//  again when neither layer changed.
//
//  No buffer above a live timeline can be kept (its render asks for the wake of
//  its next entry, which no memo replays), so the layer modifier the timeline
//  is drawn in is walked at every entry. Its base is served from its own memo
//  and its layer, the timeline, draws its content; and then the two were
//  composited again: under a `Color.clear` the board's every cell was settled
//  against the clear layer's claim and resolved, 75% of each frame of Stress's
//  `timeline-beside`, for the picture the last entry made.
//
//  A composite is a function of what it composites: the two buffers, where the
//  layer lands, and what the environment says about spending claims (the
//  palette, linear light, the image store). The process-wide inputs it reads
//  besides (the colour depth, the terminal's reported colours, the graphics
//  protocols) clear the render cache when they move, and this with it. So a
//  composite is kept with all of its inputs, and served only when every one
//  compares equal: no clear ever has to find it, and none could make it stale.
//
//  Not kept: a composite that asked for a wake (a run of one layer that shows
//  through the other turns), which a serve would not ask again; and one that
//  may have touched the image store (a claim that frosts, a picture under a
//  claim, with a store to draw its faded copy into), whose registrations a
//  serve would not make.
//
//  Only while a timeline asked for a wake this pass or the last, and only while
//  `FrameBodyKeep` is on: `TUI_KEEP_TIMELINE_ANCESTORS=0` turns this off with
//  it. A page with no live timeline composites as it did, beyond one load.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// The layer composites kept across frames while a timeline is live.
/// Main-actor only, as the cache's tables are.
package final class LayerCompositeKeep {
    /// What it has done: what the tests read.
    package struct Counts: Equatable {
        /// Composites made while a timeline was live, kept or not.
        package var composited = 0
        /// Composites kept.
        package var kept = 0
        /// Composites served.
        package var served = 0
    }

    package var counts = Counts()

    /// Which way the layer goes: over the base or under it.
    package enum Direction {
        case over
        case under
    }

    /// Everything a composite is made from.
    package struct Inputs {
        package let direction: Direction
        /// The layer, inside the base's frame at `offset`.
        package let layer: FrameBuffer
        package let offset: (x: Int, y: Int)
        package let base: FrameBuffer
        package let palette: any Palette
        package let linearLight: Bool
        /// The image store, compared by identity.
        package let images: AnyObject?

        package init(
            _ direction: Direction, layer: FrameBuffer, at offset: (x: Int, y: Int), base: FrameBuffer,
            palette: any Palette, linearLight: Bool, images: AnyObject?
        ) {
            self.direction = direction
            self.layer = layer
            self.offset = offset
            self.base = base
            self.palette = palette
            self.linearLight = linearLight
            self.images = images
        }

        /// Whether these make the composite `other` makes.
        func makesTheSameComposite(as other: Self) -> Bool {
            direction == other.direction && offset == other.offset && linearLight == other.linearLight
                && images === other.images && LayerCompositeKeep.same(base, other.base)
                && LayerCompositeKeep.same(layer, other.layer) && palette.isSamePalette(as: other.palette)
        }
    }

    /// One composite and what it was made from.
    private struct Kept {
        let inputs: Inputs
        let result: FrameBuffer
        /// The pass it was last kept or served in: one neither in a pass is gone.
        var pass: Int
    }

    private var table: [Int: Kept] = [:]

    private var pass = 0

    /// How many composites are kept, for a census of the caches.
    package var count: Int { table.count }

    package init() {}

    /// Starts a pass: what the pass before neither kept nor served is no
    /// longer drawn, or no longer drawn beside a live timeline.
    func beginPass() {
        pass &+= 1
        if !table.isEmpty { table = table.filter { $0.value.pass >= pass - 1 } }
    }

    /// Drops everything kept.
    func dropAll() {
        table.removeAll()
    }

    /// The composite kept at `slot` of exactly these inputs, or `nil`.
    package func served(at slot: Int, _ inputs: Inputs) -> FrameBuffer? {
        guard let kept = table[slot], kept.inputs.makesTheSameComposite(as: inputs) else { return nil }
        table[slot]?.pass = pass
        counts.served += 1
        return kept.result
    }

    /// Keeps `result`, the composite of `inputs`, at `slot`.
    package func keep(_ result: FrameBuffer, at slot: Int, _ inputs: Inputs) {
        counts.kept += 1
        table[slot] = Kept(inputs: inputs, result: result, pass: pass)
    }

    /// Whether two buffers are one input to a composite: equal as buffers are
    /// (their lines, layers, hit regions, runs and claims), and equal in the
    /// hints a composite takes a path by too, which `==` leaves out.
    fileprivate static func same(_ lhs: FrameBuffer, _ rhs: FrameBuffer) -> Bool {
        lhs.width == rhs.width && lhs.linesAreUniformWidth == rhs.linesAreUniformWidth
            && lhs.overlaysAreFreeOfOverflow == rhs.overlaysAreFreeOfOverflow && lhs.lineWidths == rhs.lineWidths
            && lhs == rhs
    }
}
