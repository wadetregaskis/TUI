//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedRowPalettes.swift
//
//  Cut from ReversedCursorRowTests.swift: suites of several test targets render under these palettes.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIkitStyling

/// An RGB page and ink whose accent is a terminal slot, which has no RGB until the
/// terminal reports its sixteen. The trap the reversal has to survive: the page is a
/// colour the palette paints, so a bare 7 after a child's reset would fill with the
/// terminal's own foreground instead.
struct ReversedRowSlotAccentPalette: Palette {
    let id = "reversed-row-slot-accent"
    let name = "Slot accent"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.ansi(.blue)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// The page and the ink the terminal decides, with everything else RGB.
///
/// Internal rather than private: `ReversedTextSelectionTests` asks the same question of
/// a text input's selection and caret, and the two suites agreeing about what "the
/// terminal's own pair" means is the point of sharing the fixture.
struct ReversedRowTerminalPairPalette: Palette {
    let id = "reversed-row-terminal-pair"
    let name = "Terminal pair"
    let background = Color(value: .terminalBackground)
    let foreground = Color(value: .terminalForeground)
    let foregroundTertiary = Color(value: .terminalForeground)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

#endif
