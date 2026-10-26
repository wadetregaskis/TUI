//  🖥️ TUI — A Terminal UI framework for Swift
//  CompositeEnvironment.swift
//
//  What a compositor inside the tree reads from its environment to spend the
//  claims that land in it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling
import TUIView

/// What a compositor inside the tree reads from its environment to spend the
/// claims that land in it: one value, so a compositor passes its environment
/// on whole rather than field by field, and a field added here reaches every
/// composite without another pass over the call sites.
package struct CompositeEnvironment {
    /// Resolves SGR 39, the terminal's own colours and the surface.
    package var palette: any Palette

    /// Whether the claims spent here mix in linear light: the compositor's
    /// ``EnvironmentValues/blendsInLinearLight``, inside a
    /// `drawingGroup(colorMode: .linear)`.
    package var linearLight: Bool

    package init(palette: any Palette, linearLight: Bool) {
        self.palette = palette
        self.linearLight = linearLight
    }

    /// The compositor's own environment's.
    package init(_ environment: EnvironmentValues) {
        self.init(palette: environment.palette, linearLight: environment.blendsInLinearLight)
    }
}
