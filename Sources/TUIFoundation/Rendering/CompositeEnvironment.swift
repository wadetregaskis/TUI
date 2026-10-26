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

    /// The pictures this app has put in the terminal, so a translucent layer
    /// spent over one draws a copy of it with the layer applied
    /// (`OpacityBlend+Pictures.swift`); `nil` where there are none to know.
    package var images: TerminalImageStore?

    package init(palette: any Palette, linearLight: Bool, images: TerminalImageStore? = nil) {
        self.palette = palette
        self.linearLight = linearLight
        self.images = images
    }

    /// The compositor's own environment's.
    package init(_ environment: EnvironmentValues) {
        self.init(
            palette: environment.palette, linearLight: environment.blendsInLinearLight,
            images: environment.terminalImageStore)
    }
}
