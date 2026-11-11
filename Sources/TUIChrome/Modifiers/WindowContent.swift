//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// `content`, a buffer rendered for the scene's content area, centred in it
/// over `background`, which fills the area or is placed in it by its
/// alignment.
///
/// Centred vertically in `centringHeight` rows, the area with no tooltip in
/// the status bar, and moved up only as far as the area it has needs
/// (``centredRow(extent:within:centringIn:)``).
///
/// The background renders at an identity of its own under the scene's, so its
/// `@State` is its own. Every cell the content names no field for shows the
/// background's — `.background(alignment:content:)`'s rule, one container out.
@MainActor
func windowContent(
    _ content: FrameBuffer, over background: ContainerBackground, centringHeight: Int, context: RenderContext
) -> FrameBuffer {
    let width = max(0, context.availableWidth)
    let height = max(0, context.availableHeight)
    let backgroundBuffer = TUIView.renderToBuffer(
        background.view,
        context: context.withChildIdentity(type: ContainerBackgroundPlacement.self, index: 1))

    let composite = CompositeEnvironment(context.environment)
    var result = FrameBuffer(emptyWithWidth: width, height: height)
    result.compositeCarryingClaimsOverNothing(
        with: backgroundBuffer,
        at: (
            x: background.alignment.horizontal.childOffset(childWidth: backgroundBuffer.width, in: width),
            y: background.alignment.vertical.childOffset(childHeight: backgroundBuffer.height, in: height)),
        in: composite)
    // Centred as `WindowGroup` centres its content with no background.
    let origin = (
        x: max(0, (width - content.width) / 2),
        y: centredRow(extent: content.height, within: height, centringIn: centringHeight)
    )
    let showingThrough = result.runsShowingThrough(content, at: origin)
    if !showingThrough.isEmpty {
        context.requestWake(
            token: "container-background-run-\(context.identity.path)",
            forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
    }
    result.compositeCarryingClaimsOverNothing(with: content, at: origin, in: composite)
    return result.clamped(toWidth: width, height: height)
}

/// The row a page `extent` rows tall starts on in a content area of `height`
/// rows that has `centringHeight` with no tooltip in the status bar: centred
/// in those, and moved up only as far as it must to end within `height`.
///
/// The bar grows upwards for a tooltip. Centred in the rows left, a page
/// shorter than the window moved up a row and back as help came and went;
/// centred in the rows it has without one, it stays where it is unless the
/// tooltip's rows would cover it (the owner, 2026-11-10: tips "should only
/// move windows / dialogs / etc if _necessary_"), as a dialog over it does
/// (`OverlayLayer.placed(maxWidth:maxHeight:centringHeight:)`). A page that
/// fills the area is laid out in it, and starts at the top either way.
func centredRow(extent: Int, within height: Int, centringIn centringHeight: Int) -> Int {
    let centred: Int = max(0, (max(height, centringHeight) - extent) / 2)
    return min(centred, max(0, height - extent))
}
