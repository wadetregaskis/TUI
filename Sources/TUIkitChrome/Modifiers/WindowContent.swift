//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// `content`, a buffer rendered for the scene's content area, centred in it
/// over `background`, which fills the area or is placed in it by its
/// alignment.
///
/// The background renders at an identity of its own under the scene's, so its
/// `@State` is its own. Every cell the content names no field for shows the
/// background's — `.background(alignment:content:)`'s rule, one container out.
@MainActor
func windowContent(
    _ content: FrameBuffer, over background: ContainerBackground, context: RenderContext
) -> FrameBuffer {
    let width = max(0, context.availableWidth)
    let height = max(0, context.availableHeight)
    let backgroundBuffer = TUIkitView.renderToBuffer(
        background.view,
        context: context.withChildIdentity(type: ContainerBackgroundPlacement.self, index: 1))

    let palette = context.environment.palette
    var result = FrameBuffer(emptyWithWidth: width, height: height)
    result.compositeCarryingClaimsOverNothing(
        with: backgroundBuffer,
        at: (
            x: background.alignment.horizontal.childOffset(childWidth: backgroundBuffer.width, in: width),
            y: background.alignment.vertical.childOffset(childHeight: backgroundBuffer.height, in: height)),
        palette: palette)
    // Centred as `WindowGroup` centres its content with no background.
    let showingThrough = result.runsShowingThrough(
        content, at: (x: max(0, (width - content.width) / 2), y: max(0, (height - content.height) / 2)))
    if !showingThrough.isEmpty {
        context.requestWake(
            token: "container-background-run-\(context.identity.path)",
            forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
    }
    result.compositeCarryingClaimsOverNothing(
        with: content, at: (x: max(0, (width - content.width) / 2), y: max(0, (height - content.height) / 2)),
        palette: palette)
    return result.clamped(toWidth: width, height: height)
}
