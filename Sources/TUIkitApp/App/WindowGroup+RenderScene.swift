//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowGroup+RenderScene.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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
        TUIkitView.renderToBuffer(_WindowChromeHost(content: content), context: context)
    }
}
