//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+Layering.swift
//
//  Children drawn over one another on one canvas, each at a place of its own:
//  a `ZStack`'s layers, and a stack's children while they glide. Moved here
//  from `_ZStackCore`, so the two composite their children by one loop.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {
    /// `layers` drawn in order, each at its place, onto a blank `width` ×
    /// `height` canvas: a later layer over an earlier one, as a `ZStack` draws
    /// its children in ascending z-index.
    ///
    /// Character-level compositing, so a narrower layer does not truncate a
    /// wider one beneath it — the uncovered sides of the lower layer show
    /// through — and each layer keeps its fills, blank-but-coloured cells
    /// included (``compositedCarryingClaimsOverNothing(with:at:palette:linearLight:)``).
    ///
    /// A layer that does not fit the canvas is, where `splitsOverhang`, drawn
    /// past it at its place in the stacking order
    /// (``splitPlacing(at:inWidth:height:)``): over what came before it and
    /// under what comes after it. Otherwise it is composited where it lands
    /// and the canvas grows to hold it. A measure draws nothing past the
    /// canvas: it keeps only what is inside.
    ///
    /// Where a later layer shows the field of a lower layer's animated runs,
    /// the run loop is asked to wake for their steps, under `wakeToken`.
    ///
    /// - Parameters:
    ///   - layers: Each layer's picture and where its top-leading corner goes.
    ///   - width: The canvas's width.
    ///   - height: The canvas's height.
    ///   - splitsOverhang: Whether a layer that does not fit is drawn past the
    ///     canvas rather than growing it.
    ///   - wakeToken: Names the wake, asked only when one is needed.
    ///   - context: The compositing container's render context.
    @MainActor
    static func layered(
        _ layers: [(buffer: FrameBuffer, x: Int, y: Int)], width: Int, height: Int,
        splitsOverhang: Bool, wakeToken: @autoclosure () -> String, context: RenderContext
    ) -> FrameBuffer {
        var result = FrameBuffer(lines: Array(repeating: String.spaces(width), count: height))
        // The runs of a lower layer a later one shows the field of, whose frames turn
        // it: punched under the later layer, they ask for a render at their steps.
        var showingThrough: [AnimatedCellRun] = []
        for layer in layers {
            var (buffer, dx, dy) = layer
            if splitsOverhang, !buffer.fits(at: (x: dx, y: dy), inWidth: width, height: height) {
                let placement = buffer.splitPlacing(at: (x: dx, y: dy), inWidth: width, height: height)
                // Before this layer's cells land, so the layers after it cut
                // what it draws past the canvas, as they cut each other.
                if !context.isMeasuring { result.overlays.append(contentsOf: placement.overflow) }
                (buffer, dx, dy) = (placement.inside, placement.insideOrigin.x, placement.insideOrigin.y)
            }
            showingThrough += result.runsShowingThrough(buffer, at: (x: dx, y: dy))
            result = result.compositedCarryingClaimsOverNothing(
                with: buffer, at: (x: dx, y: dy), palette: context.environment.palette,
                linearLight: context.environment.blendsInLinearLight)
        }
        if !showingThrough.isEmpty {
            context.requestWake(
                token: wakeToken(), forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
        }
        return result
    }
}
