//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+Scene.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - What the scene configures, each frame

/// The run loop's reading of the scene's own configuration — the modifiers
/// written on a `WindowGroup` that the tree does not read: its mouse support,
/// its chrome style, its undo and redo keys, and its screen selection's copy
/// key and copy-on-release.
///
/// Separate from `RenderLoop.swift` because that file is at its length limit,
/// the bargain `RenderLoop+TerminalColors.swift` makes too; it is why
/// ``baseMouseSupport`` is not private.
extension RenderLoop {

    /// Adopts this frame's scene configuration: called straight after the
    /// scene's root environment is applied to `environment`, before anything
    /// asks either bar's height.
    func applySceneConfiguration(from scene: some Scene, environment: EnvironmentValues) {
        // The app's undo and redo keys, which the scene may have set
        // (`.undoShortcuts`), resolved through its `\.commandKey`, for the keys
        // that arrive before the next frame. Rebuilt only when they changed.
        tuiContext.undoKeys.publish(environment.undoShortcuts, commandKey: environment.commandKey)
        // Capture the scene's base ``MouseSupport`` configuration; the
        // effective per-frame configuration is the union of this and
        // any features requested by view modifiers during render. The
        // AppRunner consults `effectiveMouseSupport` after the render
        // pass completes to update the terminal tracking mode.
        if let mouseScene = scene.primitiveScene as? any MouseSupportProvidingScene {
            // `nil` means no `.mouseSupport(...)` was applied (only pass-through
            // scene wrappers like `.palette(...)`); fall back to `.standard`.
            baseMouseSupport = mouseScene.resolvedMouseSupport() ?? .standard
        } else {
            baseMouseSupport = .standard
        }
        // Make the active support available to handlers right now so
        // any events queued from the previous frame are filtered
        // against the right config.
        tuiContext.mouseEventDispatcher.setActiveSupport(baseMouseSupport)
        applyChromeStyle(from: scene)
        // The screen selection's copy key and the scene's copy-on-release.
        tuiContext.screenSelection.adopt(
            commandKey: environment.commandKey, copiesOnRelease: environment.textSelectionCopiesOnRelease)
    }

    /// Adopts a scene-level `.chromeStyle(...)` for this frame.
    ///
    /// Must run BEFORE anything asks either bar's height: the style decides how
    /// many rows they take, and the page's height is whatever is left. That is
    /// why the status bar's height is read straight after this call rather than
    /// alongside the terminal size, where it used to sit.
    private func applyChromeStyle(from scene: some Scene) {
        guard let chromeScene = scene.primitiveScene as? any RootChromeStyleProvidingScene else { return }
        let chrome = chromeScene.rootChromeStyle()
        if let style = chrome.appHeader { appHeader.style = style }
        if let style = chrome.statusBar { statusBar.style = style }
    }
}
