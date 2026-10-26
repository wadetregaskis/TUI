//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+Theme.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIFoundation
import TUIStyling
import TUIView

extension Scene {
    /// Applies a ``Theme``'s palette (with its tint folded in) at the scene
    /// level, so out-of-tree surfaces (app header, status bar) match — the
    /// scene-level counterpart to ``View/theme(_:)``.
    ///
    /// - Note: Scene level applies the theme's **palette + tint**. To also apply
    ///   its scoped styles, control styles, and appearance, use ``View/theme(_:)``
    ///   on the scene's root content.
    public func theme(_ theme: Theme) -> some Scene {
        palette(theme.resolvedPalette)
    }
}
