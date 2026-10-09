//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiftedSurface.swift
//
//  The surface a container paints to lift its content off what it sits on.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitStyling
import TUIkitView

extension EnvironmentValues {
    /// The surface a container paints under its content to lift it off what it
    /// sits on: one plane's step off ``surfaceBackground`` where a container
    /// above painted one, and otherwise ``Palette/liftedBackground`` — the
    /// palette's app-header tone where it states a visible one, else a derived
    /// step off the page, never the page colour itself.
    ///
    /// A `TabView`'s body is drawn on it. A container inside another surface
    /// steps off THAT, not off the page — the rule a field follows
    /// (``Palette/fieldBackground(on:)``), at the plane's step. Asking for "a
    /// surface on the page" from inside one returned the enclosing surface's
    /// own colour, so the inner island was invisible.
    ///
    /// `liftedBackground`, not `appHeaderBackground`, where nothing was
    /// painted: the latter defaults to the page background, so on a palette
    /// that never overrode it the surface painted the colour that was already
    /// there and the island vanished.
    var liftedSurface: Color {
        if let inherited = surfaceBackground {
            return palette.lifted(from: inherited).resolve(with: palette)
        }
        return palette.liftedBackground.resolve(with: palette)
    }
}
