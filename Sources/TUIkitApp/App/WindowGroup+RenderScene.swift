//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowGroup+RenderScene.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitChrome
import TUIkitFoundation

// MARK: - WindowGroup

/// The bridge from the `Scene` hierarchy to `View` rendering: the window
/// group's content, framed by its chrome, as one ``FrameBuffer`` the size of
/// the terminal. Terminal output (diffing, writing) is handled by `RenderLoop`
/// via `FrameDiffWriter`.
///
/// Like SwiftUI, `WindowGroup` centres its content both horizontally and
/// vertically within the space the chrome leaves it.
extension WindowGroup: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        // The walk of the scene tree ends here: the content is views, which
        // have no scene to be told about.
        var context = context
        context.environment.sceneRenderTarget = nil
        // The overlay scenes the window in front presents, drawn beside its
        // content (`_SceneOverlayHost`).
        if let overlays = context.environment.sceneOverlays?.overlays, !overlays.isEmpty {
            context.environment.sceneOverlays = nil
            return TUIkitView.renderToBuffer(
                _WindowChromeHost(content: _SceneOverlayHost(content: content, overlays: overlays)), context: context)
        }
        return TUIkitView.renderToBuffer(_WindowChromeHost(content: content), context: context)
    }
}
