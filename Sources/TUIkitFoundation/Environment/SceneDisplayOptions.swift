//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneDisplayOptions.swift
//
//  Which of the display options the app's managers hold — the palette, the
//  border appearance, the control style — the scene states for itself, so a
//  manager's choice would not show.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling
import TUIkitView

/// The display options a window's scene states for itself: those for which
/// the app's palette, appearance or control style manager no longer decides
/// what is drawn.
///
/// The run loop publishes the window in front's at the root of each frame
/// (``EnvironmentValues/displayOptionsSetByScene``), from what its scene's
/// modifiers stated (`SceneConfiguration`): a `.palette(_:)` or `.theme(_:)`,
/// a `.appearance(_:)` with an appearance, an `.environment(_:_:)` of one of
/// the three values, or an environment modifier of one on the window group's
/// root view. `DisplayCommands` reads it, so a submenu whose choice would show
/// nothing is not offered as if it would.
///
/// A `.transformEnvironment` is not counted: it changes the manager's value
/// rather than replacing it, so the manager's choice still shows through it.
package struct SceneDisplayOptions: OptionSet, Sendable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The palette (the palette manager's).
    package static let palette = Self(rawValue: 1 << 0)

    /// The border appearance (the appearance manager's).
    package static let appearance = Self(rawValue: 1 << 1)

    /// The control style (the control style manager's).
    package static let controlStyle = Self(rawValue: 1 << 2)

    /// The option a write of `keyPath` into the environment states: none, for
    /// a value no manager holds.
    package init(writing keyPath: AnyKeyPath) {
        // Compared by identity of the property, as `WindowGroup` finds its root
        // view's palette (Tools/DedupCheck/manifest.json, `SceneDisplayOptions.init(writing:`).
        // swiftlint:disable key_path_identity
        if keyPath == \EnvironmentValues.palette {
            self = .palette
        } else if keyPath == \EnvironmentValues.appearance {
            self = .appearance
        } else if keyPath == \EnvironmentValues.controlStyle {
            self = .controlStyle
        } else {
            self = []
        }
        // swiftlint:enable key_path_identity
    }
}

private struct SceneDisplayOptionsKey: EnvironmentKey {
    static let defaultValue: SceneDisplayOptions = []
}

extension EnvironmentValues {
    /// The display options the window in front's scene states for itself — see
    /// ``SceneDisplayOptions``. Empty below the root of a frame the run loop
    /// did not draw.
    package var displayOptionsSetByScene: SceneDisplayOptions {
        get { self[SceneDisplayOptionsKey.self] }
        set { self[SceneDisplayOptionsKey.self] = newValue }
    }
}
