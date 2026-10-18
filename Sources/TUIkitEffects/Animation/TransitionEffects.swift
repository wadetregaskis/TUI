//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionEffects.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling
import TUIkitView

/// What a transition draws on one frame, and where it stands relative to the
/// slot the view will end up in.
///
/// The displacement is zero for every phase from 0 to 1: the view is arriving,
/// part of it is outside its slot, and the slot is what clips it. Past 1 a
/// spring has carried it BEYOND its home, which is a picture the slot cannot
/// hold — see ``TransitionPicture/slotBuffer()``.
struct TransitionPicture {
    /// The cells, in the slot's own coordinates.
    var buffer: FrameBuffer
    /// How far right of the slot the picture stands.
    var dx: Int = 0
    /// How far below the slot the picture stands.
    var dy: Int = 0
}

extension AnyTransition.Effect {
    /// The buffer as it looks when the view is `phase` present — `1` fully
    /// there, `0` gone, and (for a spring) more than `1` while it is past its
    /// target on the way back.
    ///
    /// Every effect keeps the buffer's SHAPE. A transition that changed its
    /// size would reflow the page on each frame, which is both expensive and
    /// the wrong picture: the slot is already the size it will end up, and what
    /// moves is what is drawn in it.
    ///
    /// ## Which clamps are real
    ///
    /// `0` is a floor for every effect: below it there is nothing to draw less
    /// of.
    ///
    /// `1` is a ceiling for two of them, and for reasons that are properties of
    /// the effect rather than of the transition. ``AnyTransition/opacity`` has
    /// nowhere to go past fully opaque. ``AnyTransition/scale`` uncovers the
    /// buffer from an anchor, and the buffer IS the slot: a factor above 1
    /// computes a negative origin for a reveal wider than the thing it is
    /// revealing.
    ///
    /// For ``AnyTransition/move(edge:)`` and ``AnyTransition/offset(x:y:)`` the
    /// ceiling was arbitrary — `away = 1 - phase` goes negative on its own and
    /// produces exactly the overshoot the spring asked for — so those two let
    /// the curve through and report the displacement instead of drawing it,
    /// which is what lets the caller float it clear of the slot.
    @MainActor
    func apply(to buffer: FrameBuffer, phase: Double, context: RenderContext)
        -> TransitionPicture
    {
        let present = max(0, phase)
        switch self {
        case .identity:
            return TransitionPicture(buffer: buffer)
        case .opacity:
            let opaque = min(1, present)
            guard opaque < 1 else { return TransitionPicture(buffer: buffer) }
            return TransitionPicture(buffer: Self.faded(buffer, by: opaque, context: context))
        case .move(let edge):
            let away = 1 - present
            switch edge {
            case .leading:
                return Self.moved(buffer, dx: -Self.scaled(buffer.width, away), dy: 0, away: away)
            case .trailing:
                return Self.moved(buffer, dx: Self.scaled(buffer.width, away), dy: 0, away: away)
            case .top:
                return Self.moved(buffer, dx: 0, dy: -Self.scaled(buffer.height, away), away: away)
            case .bottom:
                return Self.moved(buffer, dx: 0, dy: Self.scaled(buffer.height, away), away: away)
            }
        case .offset(let x, let y):
            let away = 1 - present
            return Self.moved(
                buffer, dx: Self.scaled(x, away), dy: Self.scaled(y, away), away: away)
        case .scale(let factor, let anchor):
            // From `factor` of the view at no presence to all of it at full;
            // never more than all of it — see `AnyTransition.scale(scale:anchor:)`.
            let grown = min(1, max(0, factor + (1 - factor) * present))
            guard grown < 1 else { return TransitionPicture(buffer: buffer) }
            return TransitionPicture(buffer: Self.revealed(buffer, by: grown, anchor: anchor))
        case .combined(let first, let second):
            let inner = first.apply(to: buffer, phase: phase, context: context)
            var outer = second.apply(to: inner.buffer, phase: phase, context: context)
            // Displacements ADD, and each effect applies its own cells to the
            // picture as it comes: `.move.combined(with: .opacity)` past phase 1
            // has to fade the buffer the move is standing beside, not the empty
            // slot it left. That is the whole reason this returns a picture and
            // a displacement rather than a buffer with the move already drawn.
            outer.dx += inner.dx
            outer.dy += inner.dy
            return outer
        }
    }

    /// The view moved by `(dx, dy)`: WITHIN its slot while it is arriving, and
    /// standing outside the slot once the spring has carried it past home.
    ///
    /// The two are the same gesture and cannot be the same drawing. Arriving,
    /// the slot is a window the view slides into and what is still outside is
    /// clipped — the view has no claim on a neighbour's cells until it gets
    /// there. Overshooting, EVERY cell is outside: `away` is small, so the
    /// picture is a cell or two clear of a slot it entirely fills, and clipping
    /// it to the slot would erase exactly the cells the unclamped curve added.
    /// Measured from `Animation.spring(duration:bounce:)`: bounce 0.3 (which is
    /// `.bouncy`) peaks at 1.046, one cell of twenty — but bounce 0.9 peaks at
    /// 1.729, fifteen of twenty, which drawn in the slot is a wipe.
    private static func moved(_ buffer: FrameBuffer, dx: Int, dy: Int, away: Double)
        -> TransitionPicture
    {
        guard away < 0 else {
            return TransitionPicture(buffer: translated(buffer, dx: dx, dy: dy))
        }
        return TransitionPicture(buffer: buffer, dx: dx, dy: dy)
    }

    private static func scaled(_ extent: Int, _ fraction: Double) -> Int {
        Int((Double(extent) * fraction).rounded())
    }
}

// MARK: - Standing outside the slot

extension TransitionPicture {
    /// The buffer to hand back to the layout: the picture itself while it sits
    /// in its slot, or an empty footprint with the picture drawn past it once
    /// it does not.
    ///
    /// Past the slot, the picture is drawn as content past its region is
    /// (`FrameBuffer.splitPlacing(at:inWidth:height:)`): at the view's own
    /// place in the stacking order, over the views before it and under the
    /// views after it, as SwiftUI draws a view past its frame (measured for a
    /// frame, an overlay and a scale effect, decisions B-GUIDE-3). A terminal
    /// has no transparency, so the view paints nothing where it came from, as
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
    @MainActor
    func slotBuffer() -> FrameBuffer {
        guard dx != 0 || dy != 0 else { return buffer }
        let placement = buffer.splitPlacing(at: (x: dx, y: dy), inWidth: 0, height: 0)
        var footprint = FrameBuffer(footprintWidth: buffer.width, height: buffer.height)
        footprint.hitTestRegions = buffer.hitTestRegions.filter(\.isGeometryMarker)
        // The picture first, then what it carries floating, which draws over it.
        footprint.overlays = placement.overflow + placement.inside.overlays
        return footprint
    }
}

// MARK: - The effects themselves

extension AnyTransition.Effect {
    /// Blends every colour the buffer names toward the background — the same
    /// fade ``View/opacity(_:)`` performs, and for the same reason: a terminal
    /// cell has no alpha, so the only thing that can dissolve is the colour.
    /// Over the terminal's page before it has reported it, that is a cut at ½
    /// in the glyphs as well, as it is there (`OpacityFade`).
    ///
    /// The buffer's runs are faded by the same rewrite: every frame, and what the
    /// containers inside the transition painted beneath them
    /// (`FrameBuffer.restyleRuns`). A transition renders on the view-animation
    /// lattice, every 2 ticks, and a run's tick that falls between two renders is
    /// replayed onto the frame the last one left, so the frames have to be what
    /// that render faded. A `.dots` spinner steps every 7 ticks, and four of its
    /// steps in a one-second transition were replayed at full strength, on its
    /// unfaded field, in a view half faded out.
    @MainActor
    private static func faded(
        _ buffer: FrameBuffer, by factor: Double, context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let defaultForeground = palette.foreground.resolve(with: palette)
        func fading(_ line: String) -> String {
            OpacityFade.fading(line, by: factor, over: surface, defaultForeground: defaultForeground)
        }
        var faded = buffer.replacingLines(buffer.lines.map(fading))
        faded.restyleRuns(fading)
        return faded
    }

    /// The buffer moved by whole cells within its own frame, with whatever
    /// slides past the edge clipped and the vacated cells blank.
    private static func translated(_ buffer: FrameBuffer, dx: Int, dy: Int) -> FrameBuffer {
        guard dx != 0 || dy != 0 else { return buffer }
        let width = buffer.width
        let blank = String.spaces(max(0, width))
        var moved: [String] = []
        moved.reserveCapacity(buffer.lines.count)

        for row in buffer.lines.indices {
            let source = row - dy
            guard source >= 0, source < buffer.lines.count else {
                moved.append(blank)
                continue
            }
            let line = buffer.lines[source].padToVisibleWidth(width)
            moved.append(shifted(line, by: dx, within: width, blank: blank))
        }
        return buffer.replacingLines(moved)
    }

    /// One line moved sideways within `width`.
    private static func shifted(
        _ line: String, by dx: Int, within width: Int, blank: String
    ) -> String {
        guard dx != 0 else { return line }
        guard abs(dx) < width else { return blank }
        if dx > 0 {
            let kept = line.ansiAwareSlice(visibleStart: 0, visibleCount: width - dx)
            return (String.spaces(dx) + kept).padToVisibleWidth(width)
        }
        let dropped = -dx
        return line.ansiAwareSlice(visibleStart: dropped, visibleCount: width - dropped)
            .padToVisibleWidth(width)
    }

    /// The buffer revealed from `anchor`, a whole cell at a time.
    ///
    /// SwiftUI scales; a terminal cannot. There is no sub-cell rendering to
    /// shrink, so what this does instead is uncover the view from its anchor —
    /// which reads as the same gesture and is exact rather than approximate.
    private static func revealed(
        _ buffer: FrameBuffer, by factor: Double, anchor: UnitPoint
    ) -> FrameBuffer {
        let width = buffer.width
        let height = buffer.lines.count
        let shownWidth = Int((Double(width) * factor).rounded())
        let shownHeight = Int((Double(height) * factor).rounded())
        let originX = Int((Double(width - shownWidth) * anchor.x).rounded())
        let originY = Int((Double(height - shownHeight) * anchor.y).rounded())
        let blank = String.spaces(max(0, width))

        var revealed: [String] = []
        revealed.reserveCapacity(height)
        for row in 0..<height {
            guard row >= originY, row < originY + shownHeight, shownWidth > 0 else {
                revealed.append(blank)
                continue
            }
            let line = buffer.lines[row].padToVisibleWidth(width)
            let kept = line.ansiAwareSlice(visibleStart: originX, visibleCount: shownWidth)
            revealed.append(
                (String.spaces(originX) + kept).padToVisibleWidth(width))
        }
        return buffer.replacingLines(revealed)
    }
}
