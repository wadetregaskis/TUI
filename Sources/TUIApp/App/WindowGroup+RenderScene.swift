//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowGroup+RenderScene.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIChrome
import TUIFoundation

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
        // A window but the one opened at launch builds its own: two windows
        // drawing one value would share every box in it — the namespace its
        // `@SceneStorage` resolved, the values its `@Environment` did — and
        // a closure the window behind captured would write where the window
        // drawn after it keeps its values.
        let content = context.environment.windowBuildsItsContent ? (makeContent?() ?? content) : content
        // The overlay scenes the window in front presents, drawn beside its
        // content (`_SceneOverlayHost`).
        if let overlays = context.environment.sceneOverlays?.overlays, !overlays.isEmpty {
            context.environment.sceneOverlays = nil
            return TUIView.renderToBuffer(
                _WindowChromeHost(content: _SceneOverlayHost(content: content, overlays: overlays)), context: context)
        }
        return TUIView.renderToBuffer(_WindowChromeHost(content: content), context: context)
    }
}

private struct WindowBuildsItsContentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the window being drawn builds its content afresh rather than
    /// drawing the one its scene was declared with: every window the scene
    /// presenter draws but the one opened at launch (``WindowGroup/makeContent``).
    var windowBuildsItsContent: Bool {
        get { self[WindowBuildsItsContentKey.self] }
        set { self[WindowBuildsItsContentKey.self] = newValue }
    }
}
