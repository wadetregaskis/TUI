//  🖥️ TUI — A Terminal UI framework for Swift
//  DrawnColour.swift
//
//  A colour as a render draws it, for a test that spells the bytes it expects.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIFoundation
@testable import TUIStyling

/// `colour` as it is drawn under `palette`: resolved, so a palette role is the
/// palette's colour and a named colour that follows the scheme (`Color.red`) is
/// that palette's scheme's value.
///
/// The default is the palette a render that sets none draws with, the bare
/// environment's, which is dark: so `asDrawn(.red)` is Apple's DARK red, which is
/// what such a render paints, where `Color.red.foregroundCodes()` spells the
/// light one an unresolved name measures as.
///
/// - Parameters:
///   - colour: The colour.
///   - palette: The palette in force where it is drawn.
/// - Returns: The colour as drawn.
func asDrawn(_ colour: Color, in palette: any Palette = EnvironmentValues().palette) -> Color {
    colour.resolve(with: palette)
}

#endif
