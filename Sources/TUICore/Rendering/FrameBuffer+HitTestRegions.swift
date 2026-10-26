//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+HitTestRegions.swift
//
//  Carrying ``FrameBuffer/hitTestRegions`` through composition without
//  allocating where nothing needs to change.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {
    /// Appends `other`'s ``hitTestRegions``, each moved by `(dx, dy)`, to this
    /// buffer's — the step every combining operation takes for the regions of
    /// a child it places.
    ///
    /// What `hitTestRegions.append(contentsOf: other.shiftedHitTestRegions(byX:y:))`
    /// does, without its two allocations. That spelling built the shifted
    /// regions as an array of their own, then copied them into a second one
    /// grown to hold them — two buffers for every child with a region, at
    /// every level of composition, which is what one region a bordered box
    /// (its selection interior) cost every stack around it. Here:
    ///
    /// - this buffer carrying none — the first child of a stack, almost every
    ///   time — ADOPTS `other`'s array: shared storage and no allocation when
    ///   the shift is zero, one exactly-sized array when it is not;
    /// - otherwise the shifted regions are appended in place, one at a time
    ///   rather than through a temporary array, so the only allocation is this
    ///   buffer's own growth, amortised as any append's is.
    ///
    /// Order is unchanged — this buffer's regions first, then `other`'s in
    /// theirs — and so is what hit testing finds innermost.
    package mutating func appendHitTestRegions(of other: FrameBuffer, shiftedByX dx: Int, y dy: Int) {
        hitTestRegions.appendShifted(other.hitTestRegions, byX: dx, y: dy)
    }
}

extension [HitTestRegion] {
    /// Appends `regions`, each moved by `(dx, dy)`: the in-place, no-temporary
    /// append ``FrameBuffer/appendHitTestRegions(of:shiftedByX:y:)`` describes,
    /// for a composer that gathers its children's regions in an array of its
    /// own before building the buffer that carries them.
    package mutating func appendShifted(_ regions: [HitTestRegion], byX dx: Int, y dy: Int) {
        guard !regions.isEmpty else { return }
        if isEmpty {
            self = dx == 0 && dy == 0 ? regions : regions.map { $0.shifted(byX: dx, y: dy) }
        } else if dx == 0 && dy == 0 {
            append(contentsOf: regions)
        } else {
            // A plain loop, not `append(contentsOf: regions.lazy.map { … })`,
            // which is NOT the same cost: it goes through the generic
            // `Sequence._copyContents(initializing:)`, and a profile of Stress
            // `modifiers` (a column of 400 boxed rows) put this function at
            // 288 ms that way against 92 ms as this loop. Grown geometrically
            // by hand first, since `reserveCapacity` sizes to exactly what is
            // asked, and asking for that on every child would reallocate on
            // every child.
            let needed = count + regions.count
            if capacity < needed { reserveCapacity(Swift.max(needed, 2 * capacity)) }
            for region in regions { append(region.shifted(byX: dx, y: dy)) }
        }
    }
}
