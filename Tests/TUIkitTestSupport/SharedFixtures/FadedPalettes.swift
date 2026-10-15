//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadedPalettes.swift
//
//  Cut from FadedPaletteRenderTests.swift: suites of several test targets sweep these palettes.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import TUIkitStyling

/// Every slot translucent. `Palette` requires nine and derives the rest, so this is
/// the smallest type that fades a whole theme — and the reason the second tier of
/// §16.1 exists: nothing normalises what a custom palette returns.
///
/// Internal rather than private: `ScrollbarBreathAlphaTests` sweeps it too, as the
/// palette the scrollbar's breath first came apart under.
struct FadedAll: Palette {
    let id = "faded-all"
    let name = "Faded all"
    let background = Color.rgb(10, 10, 20).opacity(0.5)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let accent = Color.rgb(0, 180, 200).opacity(0.5)
    let success = Color.rgb(40, 200, 40).opacity(0.5)
    let warning = Color.rgb(220, 200, 40).opacity(0.5)
    let error = Color.rgb(220, 40, 40).opacity(0.5)
    let info = Color.rgb(40, 120, 220).opacity(0.5)
    let border = Color.rgb(120, 120, 130).opacity(0.5)
    /// Stated, one step of blue off the value its default derivation gives, rgb(31, 31, 62)
    /// at alpha 128. That derivation steps off the translucent page and carries its alpha,
    /// which made it the translucent well the text editor, caret and hyperlink alpha suites
    /// claim. The environment now derives a default field again from the spent, opaque page
    /// (Opacity as composition §80), so it would be opaque. A stated field is kept, but only
    /// one that differs from its derived default can be told from it: stated at exactly
    /// rgb(31, 31, 62) it was derived again, and those suites failed.
    let fieldBackground = Color.rgb(31, 31, 63).opacity(0.5)
}

/// Every text rung faded by a different amount, so a claim can be traced to the slot
/// that painted it — under `FadedAll` every slot owes 128, and a cell claimed from the
/// wrong one would pass.
///
/// Internal rather than private: the scroll indicator suites trace their tertiary
/// with it too.
struct FadedNavigation: Palette {
    let id = "faded-navigation"
    let name = "Faded navigation"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let foregroundSecondary = Color.rgb(200, 200, 210).opacity(0.7)
    let foregroundTertiary = Color.rgb(150, 150, 160).opacity(0.3)
    let accent = Color.rgb(0, 180, 200).opacity(0.6)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130).opacity(0.4)
}

#endif
