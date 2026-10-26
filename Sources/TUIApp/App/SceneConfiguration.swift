//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneConfiguration.swift
//
//  What the modifiers written on a scene configure, gathered in one walk.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - Scene Configuration

/// Everything the modifiers written on a scene state for the frame: the values
/// the run loop reads before it renders anything, because they decide either
/// the frame's root environment (`.environment`, `.palette`, `.appearance`) or
/// the window's chrome (`.mouseSupport`, `.windowToolbarStyle`). The commands
/// are the app's rather than a window's, and the catalogue gathers them apart.
///
/// Gathered for each window scene by the walk that catalogues the app's scenes
/// (``SceneCatalog``), from the outermost modifier in. Each modifier
/// writes over what the ones outside it wrote, so the modifier closest to the
/// content wins, field by field — the rule a view's environment follows, and
/// the one every scene modifier documents.
///
/// One struct and one walk, rather than a protocol per concern that every
/// wrapper forwards: with five concerns that was thirty forwarding
/// conformances, each wrapper passing on the four it did not own, and a sixth
/// concern would have been six more protocols' worth of them. A field here is
/// one line in the modifier that sets it and nothing anywhere else.
struct SceneConfiguration {
    /// The scene-level environment writes (`.environment(_:_:)`,
    /// `.transformEnvironment`, `.undoShortcuts`, `.reduceMotion`), outermost
    /// first — the order they run in, so the innermost write lands last.
    var environmentWrites: [(inout EnvironmentValues) -> Void] = []

    /// The palette a `.palette(_:)` stated, on the scene or on the
    /// `WindowGroup`'s root view; `nil` when neither did.
    var palette: (any Palette)?

    /// The appearance a scene-level `.appearance(_:)` stated; `nil` defers to
    /// the appearance manager (F2/F3/the appearance picker).
    var appearance: Appearance?

    /// The mouse support a `.mouseSupport(_:)` stated; `nil` when none did,
    /// which the run loop reads as ``MouseSupport/standard``.
    var mouseSupport: MouseSupport?

    /// The frame every bar of the window draws, if a `.windowToolbarStyle`
    /// named one.
    var toolbarStyle: ChromeStyle?

    /// Whether the top bar's title slot shows the window's title, if a
    /// `.windowToolbarStyle` said.
    var showsTitle: Bool?

    /// The display options the scene's environment writes state — an
    /// `.environment(_:_:)` of the palette, appearance or control style, on the
    /// scene or as an environment modifier of the window group's root view.
    /// With ``palette`` and ``appearance``, what ``applyRootOverrides(to:)``
    /// publishes as ``EnvironmentValues/displayOptionsSetByScene``.
    var displayOptionsWritten: SceneDisplayOptions = []

    /// The key the scene opens on, if a `.keyboardShortcut` said: `.some(nil)`
    /// where it took the scene's default key away.
    var keyboardShortcut: KeyboardShortcut??

    /// Runs the scene's environment writes over `environment`, in order.
    func applyEnvironmentWrites(to environment: inout EnvironmentValues) {
        for write in environmentWrites { write(&environment) }
    }

    /// Installs the scene's root overrides into the frame's root environment,
    /// for the WHOLE frame — the content tree and the chrome alike. `RenderLoop`
    /// calls it once per frame.
    func applyRootOverrides(to environment: inout EnvironmentValues) {
        // Scene-level `.environment(…)` values first, so a scene palette still
        // wins over an `.environment(\.palette, …)` written beside it: the
        // palette modifier is the more specific statement.
        applyEnvironmentWrites(to: &environment)
        if let palette { environment.palette = palette }
        // A scene-level `.appearance(...)` wins over the appearance manager's
        // current selection. `nil` (no scene override) leaves the
        // manager-derived appearance from `buildEnvironment()` intact, so
        // F2/F3/the appearance picker keep working.
        if let appearance { environment.appearance = appearance }
        // What the scene states for itself of what the app's managers hold, for
        // `DisplayCommands`, which then offers no choice that would show
        // nothing. Written only where there is something to say.
        var displayOptions = displayOptionsWritten
        if palette != nil { displayOptions.insert(.palette) }
        if appearance != nil { displayOptions.insert(.appearance) }
        if !displayOptions.isEmpty { environment.displayOptionsSetByScene = displayOptions }
    }
}

// MARK: - Configuring Scenes

/// A scene that states part of the frame's ``SceneConfiguration``: the
/// framework's scene-modifier wrappers, and `WindowGroup` at the end of the
/// chain.
///
/// Internal, as `SceneRenderable` is: a scene outside the framework says what
/// it has to say through the modifiers its `body` returns.
@MainActor
protocol ConfiguringScene: Scene {
    /// Writes this scene's own statements over what the scenes outside it
    /// wrote. A modifier that states nothing (`.onChange`) writes nothing.
    func configure(_ configuration: inout SceneConfiguration)

    /// The scene this one wraps, or `nil` at the end of the chain.
    var configuredContent: (any Scene)? { get }
}
