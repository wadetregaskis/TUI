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

    /// Adopts this frame's scene configuration: its root overrides into
    /// `environment` first, then what the run loop reads from it — before
    /// anything asks either bar's height.
    func applySceneConfiguration(_ configuration: SceneConfiguration, to environment: inout EnvironmentValues) {
        configuration.applyRootOverrides(to: &environment)
        // The app's undo and redo keys, which the scene may have set
        // (`.undoShortcuts`), resolved through its `\.commandKey`, for the keys
        // that arrive before the next frame. Rebuilt only when they changed.
        tuiContext.undoKeys.publish(environment.undoShortcuts, commandKey: environment.commandKey)
        // Capture the scene's base ``MouseSupport`` configuration; the
        // effective per-frame configuration is the union of this and
        // any features requested by view modifiers during render. The
        // AppRunner consults `effectiveMouseSupport` after the render
        // pass completes to update the terminal tracking mode.
        //
        // `nil` means no `.mouseSupport(...)` was applied; fall back to
        // `.standard`.
        baseMouseSupport = configuration.mouseSupport ?? .standard
        // Make the active support available to handlers right now so
        // any events queued from the previous frame are filtered
        // against the right config.
        tuiContext.mouseEventDispatcher.setActiveSupport(baseMouseSupport)
        applyChromeStyle(from: configuration)
        // The screen selection's copy key and the scene's copy-on-release.
        tuiContext.screenSelection.adopt(
            commandKey: environment.commandKey, copiesOnRelease: environment.textSelectionCopiesOnRelease)
        // Whether a drag's preview may travel — its lift and its flight home —
        // for the drags the input between this frame and the next begins and
        // ends. The scene's own `.reduceMotion(_:)` is in `environment` by now.
        tuiContext.dragAndDropSession.reducesMotion = environment.accessibilityReduceMotion
    }

    /// Adopts a scene-level `.windowToolbarStyle(_:)` for this frame.
    ///
    /// Must run BEFORE anything asks either bar's rows: the style decides how
    /// many they take, and the page's height is whatever is left — and before
    /// the tooltip is wrapped, to the bottom bar's content width.
    private func applyChromeStyle(from configuration: SceneConfiguration) {
        windowChrome.style = configuration.toolbarStyle ?? .bordered
        windowChrome.showsTitle = configuration.showsTitle ?? true
    }
}
