//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutCore+Composite.swift
//
//  How `_LayoutCore` draws what its subviews drew at the places its layout
//  gave them: through the glide while one is on its way, else in z-order.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

@MainActor extension _LayoutCore {
    /// `pictures`, each of `children`'s drawing at its place in `places` (a
    /// `nil` draws nothing), on a canvas `width` by `height`.
    ///
    /// While a subview is on its way to where the layout now places it under
    /// an animation, each is drawn where it is (`StackGlide`). Otherwise in
    /// ascending z-index, placement order within one, as SwiftUI draws a
    /// layout's subviews; the placement order alone where none has one.
    func composited(
        _ children: [ChildView], pictures: [FrameBuffer?], at places: [ChildPlacement], departing: [ChildView],
        width: Int, height: Int, context: RenderContext
    ) -> FrameBuffer {
        if let gliding = context.glidingStackBuffer(
            children, buffers: pictures, at: places, departing: departing, width: width, height: height)
        {
            return gliding
        }
        // A blank canvas at the size the layout reported, so an arrangement
        // that leaves gaps keeps them — and so the measure it just gave its
        // parent is the size it actually occupies.
        var result = FrameBuffer(emptyWithWidth: width, height: height)
        var drawingOrder = Array(children.indices)
        if children.contains(where: { $0.zIndex != 0 }) {
            drawingOrder.sort { (children[$0].zIndex, $0) < (children[$1].zIndex, $1) }
        }
        var showingThrough: [AnimatedCellRun] = []
        for index in drawingOrder {
            guard let rendered = pictures[index] else { continue }
            let at = (x: places[index].x, y: places[index].y)
            // In place: `composited` rebuilds every line of the canvas per
            // call, so folding n children through it is n × canvas even though
            // each child covers a couple of rows.
            showingThrough += result.runsShowingThrough(rendered, at: at)
            result.compositeCarryingClaimsOverNothing(
                with: rendered, at: at, in: CompositeEnvironment(context.environment))
        }
        // An earlier subview's runs a later one shows the field of, whose frames turn
        // it: punched under the later one, they ask for a render at their steps.
        if !showingThrough.isEmpty {
            context.requestWake(
                token: "layout-base-run-\(context.identity.path)",
                forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
        }
        return result
    }
}
