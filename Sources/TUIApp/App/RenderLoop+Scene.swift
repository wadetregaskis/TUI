//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoop+Scene.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - What the scene configures, each frame

/// The run loop's reading of the scenes: the windows open on them, and the
/// configuration of the window in front — the modifiers written on its scene
/// that the tree does not read: its mouse support, its chrome style and menu
/// bar, its undo and redo keys, and its screen selection's copy key and
/// copy-on-release.
///
/// Separate from `RenderLoop.swift` because that file is at its length limit,
/// the bargain `RenderLoop+TerminalColors.swift` makes too; it is why
/// ``baseMouseSupport`` is not private.
extension RenderLoop {

    /// Adopts this frame's scenes: the presenter's windows follow the
    /// catalogue — the launch window opens on the first frame — the scenes'
    /// watched values are compared, and the window in front's statements and the app's commands are applied to
    /// `environment`, which is kept first, as it is, for the windows held
    /// behind it to start from, on a frame that holds one.
    func adoptScenes(_ catalog: SceneCatalog, environment: inout EnvironmentValues) {
        scenes.sync(with: catalog)
        // The scenes' own `onChange(of:)`, once each, for the scene rather
        // than any window of it; before the windows are read below, since an
        // action may open one.
        catalog.compareWatches(in: tuiContext.stateStorage)
        // Not kept on a frame of one window: the copy would share the
        // environment's storage, which its next write would then duplicate.
        windowBaseEnvironment = scenes.holdsWindows ? environment : nil
        // The window in front's bars, which need not be last frame's.
        environment.windowChrome = windowChrome
        let front = scenes.front.flatMap { scenes.entry(of: $0) }
        applySceneConfiguration(
            front?.configuration ?? SceneConfiguration(), commands: catalog.commands, to: &environment)
    }

    /// The environment a window held behind the one in front draws with,
    /// off-screen: this frame's before any scene's statements, with its own
    /// scene's — not the front window's, which a scene of its own may not
    /// share. `nil` on a frame that holds no window, which never asks.
    func heldWindowEnvironment(_ configuration: SceneConfiguration) -> EnvironmentValues? {
        guard var environment = windowBaseEnvironment else { return nil }
        configuration.applyRootOverrides(to: &environment)
        return environment
    }

    /// Adopts this frame's scene configuration — the configuration of the
    /// window the frame draws, and the app's commands: its root overrides into
    /// `environment` first, then what the run loop reads from it — before
    /// anything asks either bar's height.
    func applySceneConfiguration(
        _ configuration: SceneConfiguration, commands: SceneCommands, to environment: inout EnvironmentValues
    ) {
        configuration.applyRootOverrides(to: &environment)
        // The language the scene states at its root, where it states one
        // (`WindowGroup { … }.environment(\.locale, …)`): what the app's words
        // are read in where no view is drawing — the bars' labels, undo
        // titles, a title read at an init (the owner's A-APPSTATE-1,
        // 2026-10-28). `stringLanguage` is set exactly where a locale was
        // written, so a scene that writes none leaves the process's.
        tuiContext.appState.noteRootLanguage(environment.stringLanguage)
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
        applyChromeStyle(from: configuration, commands: commands)
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
    private func applyChromeStyle(from configuration: SceneConfiguration, commands: SceneCommands) {
        windowChrome.style = configuration.toolbarStyle ?? .bordered
        windowChrome.showsTitle = configuration.showsTitle ?? true
        // The menu bar, if a scene declares commands: its row is the scenes'
        // statement, so it is known before the walk, as the style is.
        windowChrome.menuBar = commands.menuBar()
    }
}
